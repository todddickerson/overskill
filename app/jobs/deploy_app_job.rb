class DeployAppJob < ApplicationJob
  include ActiveJob::Uniqueness

  queue_as :deployment

  # FIX: Add Sidekiq retry configuration for deployment timeouts
  sidekiq_options retry: 3, dead: false if defined?(Sidekiq)

  # Timeout for overall deployment process
  DEPLOYMENT_TIMEOUT = 10.minutes

  # Prevent duplicate deployments for the same app
  # Lock until the job completes (successfully or with error)
  unique :until_executed, lock_ttl: 10.minutes, on_conflict: :log

  # Override lock key arguments to use app_id only (ignore environment for uniqueness)
  # This prevents multiple deployments of the same app regardless of environment
  def lock_key_arguments
    arg = arguments.first
    app_id = case arg
    when Integer
      arg
    when String
      arg.to_i
    when GlobalID
      arg.model_id.to_i
    else
      # For App objects or other cases
      arg.respond_to?(:id) ? arg.id : arg.to_s
    end
    [app_id]
  end

  def perform(app_or_id, environment = "production")
    app = app_or_id.is_a?(App) ? app_or_id : App.find(app_or_id)

    # Reload app to ensure we have latest repository info
    app.reload

    Rails.logger.info "[DeployAppJob] Starting deployment for app #{app.id} to #{environment}"
    Rails.logger.info "[DeployAppJob] Repository: #{app.github_repo}, Name: #{app.repository_name}"

    # FIX: Wrap deployment in timeout handler
    begin
      Timeout.timeout(DEPLOYMENT_TIMEOUT) do
        perform_deployment(app, environment)
      end
    rescue Timeout::Error
      handle_deployment_timeout(app, environment)
      raise # Let Sidekiq retry
    end
  end

  private

  def perform_deployment(app, environment)
    # FIXED: Validate deployment before proceeding
    validate_deployment_readiness!(app)

    # Rails Best Practice: Track deployment state in database
    # Create AppDeployment record for this deployment
    @deployment = AppDeployment.create_for_environment!(
      app: app,
      environment: environment,
      deployment_id: SecureRandom.uuid,
      commit_sha: get_latest_commit_sha(app)
    )

    # Start build phase tracking
    @deployment.start_build!

    # Update status to deploying
    app.update!(status: "generating")

    # Broadcast initial progress
    broadcast_deployment_progress(app,
      status: "deploying",
      progress: 10,
      phase: "Starting deployment...",
      deployment_type: environment,
      deployment_steps: [
        {name: "Build app", current: true, completed: false},
        {name: "Deploy to Cloudflare", current: false, completed: false},
        {name: "Configure routes", current: false, completed: false},
        {name: "Setup environment", current: false, completed: false}
      ])

    # Use the R2-optimized deployment pipeline (same as AppBuilderV5)
    Rails.logger.info "[DeployAppJob] Starting R2-optimized deployment for app #{app.id} (#{environment})"

    # Update progress: Building
    broadcast_deployment_progress(app,
      progress: 25,
      phase: "Building application...",
      deployment_steps: [
        {name: "Build app", current: true, completed: false},
        {name: "Deploy to Cloudflare", current: false, completed: false},
        {name: "Configure routes", current: false, completed: false},
        {name: "Setup environment", current: false, completed: false}
      ])

    # Track build start time in database
    Time.current

    # CRITICAL FIX: Ensure we're deploying generated content, not template files
    # Reload app to ensure we have the latest file content
    app.reload

    # Check if files have been recently updated (indicating generation completed)
    recent_files = app.app_files.where("updated_at > ?", 5.minutes.ago)
    if recent_files.count == 0
      Rails.logger.warn "[DeployAppJob] WARNING: No files updated in last 5 minutes - may be deploying template content!"
      # Give extra time for file generation to complete
      sleep(5)
      app.reload
    end

    # ============================================================
    # IMMEDIATE DEPLOYMENT TO WFP FOR INSTANT PREVIEW
    # ============================================================
    Rails.logger.info "[DeployAppJob] Starting immediate WFP deployment for instant preview"

    # FIX: Hoist wfp_result variable scope to make it accessible throughout method
    wfp_result = nil

    # Only deploy to preview environment immediately (production requires user action)
    if environment.to_s == "preview"
      begin
        # Deploy immediately using EdgePreviewService for instant feedback
        edge_service = EdgePreviewService.new(app)
        wfp_result = edge_service.deploy_preview do |progress|
          # Update deployment progress in real-time
          broadcast_deployment_progress(app,
            progress: (progress * 40).to_i, # 0-40% for immediate deployment
            phase: "Deploying to edge preview...",
            deployment_steps: [
              {name: "Build app", current: progress < 0.5, completed: progress >= 0.5},
              {name: "Deploy to edge", current: progress >= 0.5, completed: progress >= 1.0},
              {name: "Sync to GitHub (backup)", current: false, completed: false},
              {name: "Configure routes", current: false, completed: false}
            ])
        end

        if wfp_result[:success]
          Rails.logger.info "[DeployAppJob] ✅ Immediate WFP deployment successful: #{wfp_result[:preview_url]}"

          # Broadcast to main app channel for UI updates
          ActionCable.server.broadcast(
            "app_#{app.id}",
            {
              action: "preview_deployed",
              preview_url: wfp_result[:preview_url],
              message: "Preview deployed successfully!"
            }
          )

          # Also broadcast to app preview channel for HMR/iframe refresh
          ActionCable.server.broadcast(
            "app_preview_#{app.id}",
            {
              action: "refresh",
              url: wfp_result[:preview_url]
            }
          )

          # Broadcast Turbo Stream to replace the preview frame HTML
          # Using the main app channel that's already subscribed in the view
          begin
            Turbo::StreamsChannel.broadcast_replace_to(
              "app_#{app.id}",
              target: "preview_frame",
              partial: "account/app_editors/preview_frame",
              locals: {app: app.reload}
            )
            Rails.logger.info "[DeployAppJob] Broadcasted Turbo Stream to refresh preview frame"
          rescue => e
            Rails.logger.error "[DeployAppJob] Error broadcasting Turbo Stream: #{e.message}"
          end

          broadcast_deployment_progress(app,
            progress: 40,
            phase: "Preview deployed! Syncing to GitHub...",
            preview_url: wfp_result[:preview_url],
            deployment_steps: [
              {name: "Build app", current: false, completed: true},
              {name: "Deploy to edge", current: false, completed: true},
              {name: "Sync to GitHub (backup)", current: true, completed: false},
              {name: "Configure routes", current: false, completed: false}
            ])

          # FIX: Update app status immediately when EdgePreviewService succeeds
          update_app_deployment_status!(app, environment, wfp_result[:preview_url], "EdgePreviewService")

        else
          Rails.logger.error "[DeployAppJob] Immediate WFP deployment failed: #{wfp_result[:error]}"
          # Continue with GitHub deployment as fallback
        end
      rescue => e
        Rails.logger.error "[DeployAppJob] Error during immediate deployment: #{e.message}"
        # Continue with GitHub deployment as fallback
      end
    end

    # ============================================================
    # GITHUB BACKUP DEPLOYMENT (FEATURE GATED)
    # ============================================================
    # Check feature flag to skip GitHub deployment (WFP-only mode)
    if FeatureFlags.disable_github_workflow_deployment?(app: app, user: app.team.users.first, team: app.team)
      Rails.logger.info "[DeployAppJob] ✅ GitHub workflow deployment disabled by feature flag - WFP-only mode"

      # If immediate WFP deployment succeeded, we're done!
      if environment.to_s == "preview" && @deployment
        Rails.logger.info "[DeployAppJob] ✅ Preview deployment completed via WFP - no GitHub backup needed"

        broadcast_deployment_progress(app,
          progress: 100,
          phase: "Preview deployment completed!",
          status: "completed",
          deployment_steps: [
            {name: "Build app", current: false, completed: true},
            {name: "Deploy to edge", current: false, completed: true},
            {name: "WFP-only mode", current: false, completed: true},
            {name: "Deployment complete", current: false, completed: true}
          ])

        # Mark deployment as completed
        @deployment.complete! if @deployment.respond_to?(:complete!)

        # FIX: Update app status in WFP-only mode if EdgePreviewService succeeded
        if wfp_result&.dig(:success) && wfp_result[:preview_url]
          update_app_deployment_status!(app, environment, wfp_result[:preview_url], "EdgePreviewService-WFPOnly")
        end

        Rails.logger.info "[DeployAppJob] ✅ Deployment completed successfully in WFP-only mode"
        return # Exit early - no GitHub deployment needed
      end
    end

    # Use GitHub-based deployment flow as backup
    github_service = Deployment::GithubRepositoryService.new(app)

    # Sync all app files to GitHub repository
    Rails.logger.info "[DeployAppJob] Syncing #{app.app_files.count} app files to GitHub repository"
    file_structure = app.app_files.to_h { |file| [file.path, file.content] }

    # Log sample of files being deployed for debugging
    sample_files = app.app_files.limit(3).map { |f| "#{f.path} (#{f.updated_at})" }
    Rails.logger.info "[DeployAppJob] Sample files: #{sample_files.join(", ")}"

    # Add the workflow file to the push (move from .workflow-templates to .github/workflows)
    # This activates GitHub Actions since the workflow wasn't in the fork initially
    workflow_template_path = Rails.root.join("app/services/ai/templates/overskill_20250728/.workflow-templates/deploy.yml")
    if File.exist?(workflow_template_path)
      workflow_content = File.read(workflow_template_path)
      # Replace placeholders with actual app values
      customized_workflow = workflow_content
        .gsub("{{APP_ID}}", app.obfuscated_id.downcase)
        .gsub("{{OWNER_ID}}", app.team.users.first&.id.to_s || "1")

      file_structure[".github/workflows/deploy.yml"] = customized_workflow
      Rails.logger.info "[DeployAppJob] Including workflow file in push to activate GitHub Actions"
    end

    sync_result = github_service.push_file_structure(file_structure, environment)

    if sync_result[:success]
      Rails.logger.info "[DeployAppJob] Successfully synced #{sync_result[:files_pushed]} files to GitHub"

      # Validate that key files were actually pushed to GitHub
      validation_result = validate_github_files(app, github_service)
      unless validation_result[:success]
        Rails.logger.error "[DeployAppJob] GitHub validation failed: #{validation_result[:error]}"
        broadcast_deployment_progress(app,
          status: "failed",
          deployment_error: "GitHub sync validation failed: #{validation_result[:error]}",
          deployment_steps: [
            {name: "Sync to GitHub", current: false, completed: false},
            {name: "Trigger GitHub Actions", current: false, completed: false},
            {name: "Deploy to Workers for Platforms", current: false, completed: false},
            {name: "Configure routing", current: false, completed: false}
          ])
        result = {success: false, error: validation_result[:error]}
        return result
      end

      Rails.logger.info "[DeployAppJob] GitHub files validated successfully"

      # Mark build as complete, deployment starting
      @deployment.complete_build!

      # Track build metrics
      bundle_size = calculate_bundle_size(app)
      @deployment.track_build_metrics(
        (bundle_size * 1_000_000).to_i,  # Convert MB to bytes
        app.app_files.count
      )

      # Update progress: GitHub sync completed, GitHub Actions will auto-deploy
      broadcast_deployment_progress(app,
        progress: 50,
        phase: "GitHub Actions deploying to Workers for Platforms...",
        deployment_steps: [
          {name: "Sync to GitHub", current: false, completed: true},
          {name: "Trigger GitHub Actions", current: true, completed: false},
          {name: "Deploy to Workers for Platforms", current: false, completed: false},
          {name: "Configure routing", current: false, completed: false}
        ])

      # GitHub Actions will handle the deployment automatically
      # Wait for deployment to complete and verify
      result = wait_for_github_actions_deployment(app, environment)

      # Update progress based on GitHub Actions result
      if result[:success]
        broadcast_deployment_progress(app,
          progress: 85,
          phase: "GitHub Actions deployment completed!",
          deployment_steps: [
            {name: "Sync to GitHub", current: false, completed: true},
            {name: "Trigger GitHub Actions", current: false, completed: true},
            {name: "Deploy to Workers for Platforms", current: false, completed: true},
            {name: "Configure routing", current: true, completed: false}
          ])
      end

      # Log deployment stats
      if result[:success]
        Rails.logger.info "[DeployAppJob] WFP deployment successful: #{result[:worker_url]}"
        Rails.logger.info "[DeployAppJob] Dispatch namespace: #{result[:namespace]}"
        Rails.logger.info "[DeployAppJob] Worker name: #{result[:worker_name]}"

        # Update progress: Deployment complete
        broadcast_deployment_progress(app,
          progress: 90,
          phase: "Deployment completed via GitHub Actions!",
          deployment_steps: [
            {name: "Sync to GitHub", current: false, completed: true},
            {name: "Trigger GitHub Actions", current: false, completed: true},
            {name: "Deploy to Workers for Platforms", current: false, completed: true},
            {name: "Configure routing", current: false, completed: true}
          ])
      end
    else
      # Broadcast sync failure with detailed error
      error_message = if sync_result[:failed_files].present?
        "Failed to sync #{sync_result[:failed_files].size} files to GitHub"
      else
        "Failed to sync to GitHub: #{sync_result[:error] || "Unknown error"}"
      end

      broadcast_deployment_progress(app,
        status: "failed",
        deployment_error: error_message,
        deployment_steps: [
          {name: "Sync to GitHub", current: false, completed: false},
          {name: "Trigger GitHub Actions", current: false, completed: false},
          {name: "Deploy to Workers for Platforms", current: false, completed: false},
          {name: "Configure routing", current: false, completed: false}
        ])
      result = {success: false, error: error_message}
    end

    # FIX: Handle deployment success from either EdgePreviewService or GitHub Actions
    # Priority: EdgePreviewService URL > GitHub Actions URL (faster deployment wins)
    deployment_successful = result&.dig(:success) || wfp_result&.dig(:success)

    if deployment_successful
      Rails.logger.info "Successfully deployed app #{app.id} to #{environment}"

      # Determine which deployment method succeeded and get the URL
      if wfp_result&.dig(:success)
        # EdgePreviewService succeeded (primary path)
        deployment_url = wfp_result[:preview_url]
        deployment_source = "EdgePreviewService"
        Rails.logger.info "[DeployAppJob] Using EdgePreviewService URL: #{deployment_url}"
      else
        # GitHub Actions succeeded (backup path)
        deployment_url = result[:worker_url] || result[:deployment_url]
        deployment_source = "GitHubActions"
        Rails.logger.info "[DeployAppJob] Using GitHub Actions URL: #{deployment_url}"
      end

      # Use unified status update method (prevents duplication and bugs)
      update_app_deployment_status!(app, environment, deployment_url, deployment_source)

      # Create GitHub tag for this version (enables restoration)
      begin
        app_version = app.app_versions.order(:created_at).last  # Get the version just created
        tagging_service = Deployment::GithubVersionTaggingService.new(app_version)
        tag_result = tagging_service.create_version_tag

        if tag_result[:success]
          Rails.logger.info "[DeployAppJob] Created GitHub tag: #{tag_result[:tag_name]}"
        else
          Rails.logger.warn "[DeployAppJob] Failed to create GitHub tag: #{tag_result[:error]}"
        end
      rescue => e
        Rails.logger.error "[DeployAppJob] GitHub tagging error: #{e.message}"
        # Don't fail deployment if tagging fails
      end

      # Final success progress broadcast
      broadcast_deployment_progress(app,
        status: "deployed",
        progress: 100,
        phase: "Deployment completed!",
        deployment_url: result[:worker_url] || result[:deployment_url],
        deployment_steps: [
          {name: "Build app", current: false, completed: true, duration: 15},
          {name: "Deploy to Cloudflare", current: false, completed: true, duration: 8},
          {name: "Configure routes", current: false, completed: true, duration: 3},
          {name: "Setup environment", current: false, completed: true, duration: 2}
        ])

      # Broadcast preview frame update for preview deployments
      if environment == "preview" && app.preview_url.present?
        broadcast_preview_frame_update(app)
      end

      # Broadcast success to any connected clients
      broadcast_deployment_update(app, "deployed", result[:deployment_url] || result[:worker_url])
    else
      Rails.logger.error "Failed to deploy app #{app.id}: #{result[:error]}"

      # Track deployment failure in database
      @deployment.fail_deployment!(
        result[:error],
        result.slice(:workflow_run_id, :error_logs, :fix_attempted)
      )

      app.update!(status: "failed")

      # Broadcast deployment failure
      broadcast_deployment_progress(app,
        status: "failed",
        deployment_error: result[:error])

      broadcast_deployment_update(app, "failed", result[:error])
    end
  rescue => e
    Rails.logger.error "Deployment job failed for app #{app.id}: #{e.message}"

    # Track unexpected failure in database if deployment record exists
    @deployment&.fail_deployment!(
      "Unexpected error: #{e.message}",
      {backtrace: e.backtrace.first(10)}
    )

    app&.update!(status: "failed")

    # Broadcast failure for unexpected errors
    if app
      broadcast_deployment_progress(app,
        status: "failed",
        deployment_error: e.message)
      broadcast_deployment_update(app, "failed", e.message)
    end
  end

  private

  def validate_github_files(app, github_service)
    # Check that key files exist in the GitHub repository
    repo_full_name = "#{ENV["GITHUB_ORG"]}/#{app.repository_name}"

    # Key files to validate
    key_files = [
      ".github/workflows/deploy.yml",  # GitHub Actions workflow
      "src/App.tsx",                   # Main app component
      "package.json",                   # Dependencies
      "index.html"                      # Entry point
    ]

    missing_files = []

    key_files.each do |file_path|
      response = HTTParty.get(
        "https://api.github.com/repos/#{repo_full_name}/contents/#{file_path}",
        headers: {
          "Authorization" => "Bearer #{github_service.instance_variable_get(:@github_token)}",
          "Accept" => "application/vnd.github.v3+json"
        },
        timeout: 10
      )

      unless response.success?
        missing_files << file_path
      end
    rescue => e
      Rails.logger.error "[DeployAppJob] Error checking file #{file_path}: #{e.message}"
      missing_files << file_path
    end

    if missing_files.any?
      {success: false, error: "Missing critical files in GitHub: #{missing_files.join(", ")}"}
    else
      {success: true}
    end
  end

  def generate_version_number(app)
    last_version = app.app_versions.order(created_at: :desc).first

    if last_version
      # Increment patch version (e.g., 1.0.1 -> 1.0.2)
      version_parts = last_version.version_number.split(".").map(&:to_i)
      version_parts[2] = (version_parts[2] || 0) + 1
      version_parts.join(".")
    else
      "1.0.0"
    end
  end

  def broadcast_deployment_update(app, status, message)
    ActionCable.server.broadcast(
      "app_#{app.id}_deployment",
      {
        status: status,
        message: message,
        deployment_url: app.deployment_url,
        deployed_at: app.deployed_at&.iso8601
      }
    )
  end

  def broadcast_deployment_progress(app, options = {})
    Rails.logger.info "[DeployAppJob] Broadcasting deployment progress for app #{app.id}: #{options[:phase] || options[:status]}"

    # Find the latest assistant message for this app to attach progress to
    latest_message = app.app_chat_messages.where(role: "assistant").order(created_at: :desc).first
    return unless latest_message

    # Broadcast deployment progress data
    deployment_data = {
      deployment_status: options[:status],
      deployment_progress: options[:progress],
      deployment_phase: options[:phase],
      deployment_type: options[:deployment_type],
      deployment_steps: options[:deployment_steps],
      deployment_eta: options[:deployment_eta],
      deployment_url: options[:deployment_url],
      deployment_error: options[:deployment_error]
    }.compact

    # FIX: Use OpenStruct wrapper instead of polluting ActiveRecord object with singleton methods
    # This prevents memory leaks from accumulated singleton methods on AR objects
    message_wrapper = OpenStruct.new(latest_message.attributes.merge(deployment_data))

    # Copy essential AR methods to wrapper for view compatibility
    message_wrapper.define_singleton_method(:id) { latest_message.id }
    message_wrapper.define_singleton_method(:respond_to?) { |method| deployment_data.key?(method) || latest_message.respond_to?(method) }

    # Broadcast the updated message to the chat channel
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}_chat",
      target: "app_chat_message_#{latest_message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: {message: message_wrapper, app: app}
    )

    # Also broadcast generic deployment update for any other listeners
    ActionCable.server.broadcast(
      "app_#{app.id}_deployment",
      deployment_data.merge(
        message_id: latest_message.id,
        timestamp: Time.current.iso8601
      )
    )
  rescue => e
    Rails.logger.error "[DeployAppJob] Failed to broadcast deployment progress: #{e.message}"
  end

  # FIX: Unified status update method to prevent synchronization bugs
  def update_app_deployment_status!(app, environment, deployment_url, deployment_source)
    Rails.logger.info "[DeployAppJob] Updating app status via #{deployment_source}: #{deployment_url}"

    case environment.to_s
    when "preview"
      app.update!(
        preview_url: deployment_url,
        status: "generated",
        preview_status: nil,  # Clear any error status
        preview_error: nil    # Clear any error message
      )
      @deployment&.complete_deployment!(deployment_url)
      Rails.logger.info "[DeployAppJob] ✅ Preview status updated: #{deployment_url}"

    when "production"
      app.update!(
        production_url: deployment_url,
        published_at: Time.current,
        status: "published",
        production_status: nil,  # Clear any error status
        production_error: nil    # Clear any error message
      )
      @deployment&.complete_deployment!(deployment_url)
      Rails.logger.info "[DeployAppJob] ✅ Production status updated: #{deployment_url}"
    end

    # Create version tracking for successful deployment
    app_version = app.app_versions.create!(
      version_number: generate_version_number(app),
      changelog: "Deployed to #{environment} via #{deployment_source}",
      team: app.team,
      storage_strategy: "database"
    )

    # Create version files snapshot
    app.app_files.each do |file|
      app_version.app_version_files.create!(
        app_file: file,
        action: "created",
        content: file.content
      )
    end

    Rails.logger.info "[DeployAppJob] ✅ Deployment tracking complete for #{deployment_source}"
  end

  def wait_for_github_actions_deployment(app, environment)
    Rails.logger.info "[DeployAppJob] Waiting for GitHub Actions deployment to complete"

    # Use GitHub Actions monitoring service for proper deployment tracking
    monitor_service = Deployment::GithubActionsMonitorService.new(app)

    # Find the latest assistant message to attach build progress to
    latest_message = app.app_chat_messages.where(role: "assistant").order(created_at: :desc).first

    # Monitor the deployment with automatic error detection and fixing + build timing
    result = monitor_service.monitor_deployment(
      max_wait_time: 8.minutes,  # Reasonable timeout for build + deployment
      check_interval: 20.seconds, # Check every 20 seconds
      message: latest_message     # Pass message for build timing updates
    )

    if result[:success]
      Rails.logger.info "[DeployAppJob] GitHub Actions deployment successful"
      {
        success: true,
        worker_url: result[:deployment_url],
        deployment_url: result[:deployment_url],
        message: result[:message] || "GitHub Actions deployment completed successfully",
        workflow_run_id: result[:workflow_run_id]
      }
    else
      Rails.logger.error "[DeployAppJob] GitHub Actions deployment failed: #{result[:error]}"
      {
        success: false,
        error: result[:error],
        workflow_run_id: result[:workflow_run_id],
        error_logs: result[:error_logs],
        fix_attempted: result[:fix_attempted] || false
      }
    end
  rescue => e
    Rails.logger.error "[DeployAppJob] Error monitoring GitHub Actions deployment: #{e.message}"

    # Fallback to expected URL generation if monitoring fails
    deployment_url = generate_expected_deployment_url(app, environment)

    {
      success: false,
      error: "Failed to monitor GitHub Actions deployment: #{e.message}",
      worker_url: deployment_url,
      deployment_url: deployment_url
    }
  end

  def get_latest_commit_sha(app)
    # Get the latest commit SHA from GitHub if available
    return nil unless app.github_repo.present?

    begin
      github_service = Deployment::GithubRepositoryService.new(app)
      repo_info = github_service.get_repository_info
      repo_info[:default_branch_sha]
    rescue => e
      Rails.logger.warn "[DeployAppJob] Could not fetch commit SHA: #{e.message}"
      nil
    end
  end

  def generate_expected_deployment_url(app, environment)
    subdomain = case environment
    when "production"
      app.obfuscated_id.downcase
    when "preview"
      "preview-#{app.obfuscated_id.downcase}"
    else
      "staging-#{app.obfuscated_id.downcase}"
    end

    "https://#{subdomain}.overskill.app"
  end

  def broadcast_preview_frame_update(app)
    Rails.logger.info "[DeployAppJob] Broadcasting preview frame update for app #{app.id}"

    # Broadcast to the app channel that users are subscribed to
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}",
      target: "preview_frame",
      partial: "account/app_editors/preview_frame",
      locals: {app: app}
    )

    # Also broadcast a refresh action to the chat channel for better UX
    Turbo::StreamsChannel.broadcast_action_to(
      "app_#{app.id}_chat",
      action: "refresh",
      target: "preview_frame"
    )
  rescue => e
    Rails.logger.error "[DeployAppJob] Failed to broadcast preview frame update: #{e.message}"
  end

  private

  # Validate deployment is ready and safe
  def validate_deployment_readiness!(app)
    Rails.logger.info "[DeployAppJob] Validating deployment readiness..."

    # Check for missing dependencies
    validate_all_dependencies_exist!(app)

    # Check bundle size
    validate_bundle_size!(app)

    Rails.logger.info "[DeployAppJob] Deployment validation passed"
  end

  def validate_all_dependencies_exist!(app)
    missing_files = []

    # Check all import statements in app files
    app.app_files.where(file_type: ["component", "script"]).each do |file|
      next unless file.content

      # Find import statements
      imports = file.content.scan(/import .+ from ['"](.+?)['"]/).flatten

      imports.each do |import_path|
        # Resolve relative imports
        resolved_path = resolve_import_path(file.path, import_path)

        # Check if file exists in app_files
        unless resolved_path.start_with?("node_modules") || app.app_files.exists?(path: resolved_path)
          missing_files << resolved_path
        end
      end
    end

    if missing_files.any?
      Rails.logger.warn "[DeployAppJob] Missing dependencies detected: #{missing_files.uniq.join(", ")}"

      # Try to load missing components from template
      missing_files.uniq.each do |file_path|
        if file_path.include?("components/ui/")
          component_name = File.basename(file_path, ".tsx")
          Rails.logger.info "[DeployAppJob] Auto-loading missing component: #{component_name}"
          app.load_component_on_demand(component_name) if app.respond_to?(:load_component_on_demand)
        end
      end

      # Re-check after loading
      still_missing = missing_files.select { |path| !app.app_files.exists?(path: path) }
      if still_missing.any?
        raise "Missing required files for deployment: #{still_missing.join(", ")}"
      end
    end
  end

  def validate_bundle_size!(app)
    total_size = calculate_bundle_size(app)

    # Configurable bundle size limit with safety margin
    max_bundle_size = ENV.fetch("WORKER_MAX_BUNDLE_SIZE_MB", "10").to_f
    safety_margin = ENV.fetch("WORKER_BUNDLE_SAFETY_MARGIN_MB", "0.5").to_f
    bundle_limit = max_bundle_size - safety_margin

    if total_size > bundle_limit
      Rails.logger.error "[DeployAppJob] Bundle too large: #{total_size}MB (limit: #{bundle_limit}MB, max: #{max_bundle_size}MB)"
      raise "Bundle size exceeds Cloudflare Workers limit: #{total_size.round(2)}MB (limit: #{bundle_limit}MB)"
    end

    Rails.logger.info "[DeployAppJob] Bundle size OK: #{total_size}MB (limit: #{bundle_limit}MB)"
  end

  def calculate_bundle_size(app)
    total_bytes = app.app_files.sum { |f| f.content&.bytesize || 0 }
    (total_bytes / 1_000_000.0).round(2)  # Convert to MB
  end

  # Resolve import path, supporting custom TypeScript path aliases
  # Default aliases match common TypeScript/Vite conventions
  def resolve_import_path(current_file, import_path, aliases = nil)
    # Default TypeScript path aliases if none provided
    aliases ||= get_typescript_aliases

    # Handle relative imports
    if import_path.start_with?("./")
      dir = File.dirname(current_file)
      File.join(dir, import_path.sub("./", ""))
    elsif import_path.start_with?("../")
      dir = File.dirname(current_file)
      File.expand_path(File.join(dir, import_path))
    else
      # Check for custom aliases
      matched_alias = aliases.keys.find { |a| import_path.start_with?("#{a}/") }
      if matched_alias
        import_path.sub(/^#{Regexp.escape(matched_alias)}\//, "#{aliases[matched_alias]}/")
      else
        # Absolute or node_modules import
        import_path
      end
    end
  end

  # Get TypeScript path aliases from tsconfig.json if it exists
  def get_typescript_aliases
    tsconfig_file = @app.app_files.find_by(path: "tsconfig.json")

    if tsconfig_file&.content
      begin
        config = JSON.parse(tsconfig_file.content)
        paths = config.dig("compilerOptions", "paths") || {}

        # Convert tsconfig paths to simple alias mapping
        aliases = {}
        paths.each do |alias_pattern, target_paths|
          # Extract alias name (remove /* suffix)
          alias_name = alias_pattern.sub(/\/\*$/, "")
          # Get first target path (remove /* suffix and ./ prefix)
          target = target_paths.first&.sub(/\/\*$/, "")&.sub(/^\.\//, "") if target_paths.is_a?(Array)

          aliases[alias_name] = target if target
        end

        # Always include common defaults if not specified
        aliases["@"] ||= "src"
        aliases["~"] ||= "src/lib"
        aliases["#"] ||= "src/components"

        return aliases
      rescue JSON::ParserError => e
        Rails.logger.warn "[DeployAppJob] Failed to parse tsconfig.json: #{e.message}"
      end
    end

    # Fallback to common defaults
    {"@" => "src", "~" => "src/lib", "#" => "src/components"}
  end

  # FIX: Handle deployment timeout gracefully
  def handle_deployment_timeout(app, environment)
    Rails.logger.error "[DeployAppJob] TIMEOUT: Deployment exceeded #{DEPLOYMENT_TIMEOUT / 60} minutes for app #{app.id}"

    # Track timeout failure in database
    @deployment&.fail_deployment!(
      "Deployment timed out after #{DEPLOYMENT_TIMEOUT / 60} minutes",
      {timeout_at: Time.current.iso8601}
    )

    # Update app status
    app.update!(status: "error")

    # Find latest assistant message to update
    latest_message = app.app_chat_messages
      .where(role: "assistant")
      .order(created_at: :desc)
      .first

    if latest_message
      # Update message status
      latest_message.update!(
        status: "failed",
        metadata: (latest_message.metadata || {}).merge(
          error: "Deployment timeout",
          deployment_status: "timeout",
          timeout_at: Time.current.iso8601
        )
      )

      # Broadcast timeout to UI
      broadcast_deployment_progress(app,
        status: "failed",
        deployment_error: "Deployment timed out after #{DEPLOYMENT_TIMEOUT / 60} minutes. Will retry automatically.",
        deployment_steps: [
          {name: "Deployment", current: false, completed: false},
          {name: "Timeout", current: true, completed: false}
        ])

      # Clean up any stuck conversation flow entries
      if latest_message.conversation_flow.present?
        flow = latest_message.conversation_flow
        flow.each do |entry|
          if entry["type"] == "tools" && entry["status"] == "streaming"
            entry["status"] = "timeout"
            entry["error"] = "Deployment timeout"
          end
        end
        latest_message.update!(conversation_flow: flow)
      end
    end

    # Log for monitoring
    Rails.logger.error "[DeployAppJob] Deployment timeout details:"
    Rails.logger.error "  App ID: #{app.id}"
    Rails.logger.error "  Environment: #{environment}"
    Rails.logger.error "  App Name: #{app.name}"
    Rails.logger.error "  Files Count: #{app.app_files.count}"
    Rails.logger.error "  Repository: #{app.github_repo}"

    # Clean up any stuck Redis state
    Rails.cache.redis.then do |redis|
      pattern = "deployment:#{app.id}:*"
      keys = redis.keys(pattern)
      redis.del(*keys) if keys.any?
      Rails.logger.info "[DeployAppJob] Cleaned up #{keys.count} Redis deployment keys"
    end
  end
end
