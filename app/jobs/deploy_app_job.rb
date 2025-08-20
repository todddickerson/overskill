class DeployAppJob < ApplicationJob
  queue_as :deployment
  
  def perform(app_id, environment = "production")
    app = App.find(app_id)
    
    # Update status to deploying
    app.update!(status: 'generating')
    
    # Broadcast initial progress
    broadcast_deployment_progress(app, 
      status: 'deploying', 
      progress: 10, 
      phase: 'Starting deployment...',
      deployment_type: environment,
      deployment_steps: [
        { name: 'Build app', current: true, completed: false },
        { name: 'Deploy to Cloudflare', current: false, completed: false },
        { name: 'Configure routes', current: false, completed: false },
        { name: 'Setup environment', current: false, completed: false }
      ]
    )
    
    # Use the R2-optimized deployment pipeline (same as AppBuilderV5)
    Rails.logger.info "[DeployAppJob] Starting R2-optimized deployment for app #{app.id} (#{environment})"
    
    # Update progress: Building
    broadcast_deployment_progress(app, 
      progress: 25, 
      phase: 'Building application...',
      deployment_steps: [
        { name: 'Build app', current: true, completed: false },
        { name: 'Deploy to Cloudflare', current: false, completed: false },
        { name: 'Configure routes', current: false, completed: false },
        { name: 'Setup environment', current: false, completed: false }
      ]
    )
    
    # Use new GitHub-based deployment flow (GitHub migration architecture)
    github_service = Deployment::GithubRepositoryService.new(app)
    
    # Sync all app files to GitHub repository
    Rails.logger.info "[DeployAppJob] Syncing app files to GitHub repository"
    file_structure = app.app_files.to_h { |file| [file.path, file.content] }
    
    sync_result = github_service.push_file_structure(file_structure)
    
    unless sync_result[:success]
      # Broadcast sync failure
      broadcast_deployment_progress(app, 
        status: 'failed', 
        deployment_error: "Failed to sync to GitHub: #{sync_result[:error]}",
        deployment_steps: [
          { name: 'Sync to GitHub', current: false, completed: false },
          { name: 'Trigger GitHub Actions', current: false, completed: false },
          { name: 'Deploy to Workers for Platforms', current: false, completed: false },
          { name: 'Configure routing', current: false, completed: false }
        ]
      )
      result = { success: false, error: "GitHub sync failed: #{sync_result[:error]}" }
    else
      Rails.logger.info "[DeployAppJob] Successfully synced #{sync_result[:files_pushed]} files to GitHub"
      
      # Update progress: GitHub sync completed, GitHub Actions will auto-deploy
      broadcast_deployment_progress(app, 
        progress: 50, 
        phase: 'GitHub Actions deploying to Workers for Platforms...',
        deployment_steps: [
          { name: 'Sync to GitHub', current: false, completed: true },
          { name: 'Trigger GitHub Actions', current: false, completed: true },
          { name: 'Deploy to Workers for Platforms', current: true, completed: false },
          { name: 'Configure routing', current: false, completed: false }
        ]
      )
      
      # Use Workers for Platforms service for WFP deployment
      wfp_service = Deployment::WorkersForPlatformsService.new(app)
      
      # Map environment to deployment type
      deployment_environment = case environment
                              when "production"
                                :production
                              when "preview"
                                :preview
                              else
                                :staging
                              end
      
      # Update progress: Configuring WFP routing
      broadcast_deployment_progress(app, 
        progress: 75, 
        phase: 'Configuring Workers for Platforms routing...',
        deployment_steps: [
          { name: 'Sync to GitHub', current: false, completed: true },
          { name: 'Trigger GitHub Actions', current: false, completed: true },
          { name: 'Deploy to Workers for Platforms', current: false, completed: true },
          { name: 'Configure routing', current: true, completed: false }
        ]
      )
      
      # Deploy using Workers for Platforms
      result = wfp_service.deploy_to_namespace(
        environment: deployment_environment,
        worker_code: nil  # Code will be deployed via GitHub Actions
      )
      
      # Log deployment stats
      if result[:success]
        Rails.logger.info "[DeployAppJob] WFP deployment successful: #{result[:worker_url]}"
        Rails.logger.info "[DeployAppJob] Dispatch namespace: #{result[:namespace]}"
        Rails.logger.info "[DeployAppJob] Worker name: #{result[:worker_name]}"
        
        # Update progress: Deployment complete
        broadcast_deployment_progress(app, 
          progress: 90, 
          phase: 'Deployment completed via GitHub Actions!',
          deployment_steps: [
            { name: 'Sync to GitHub', current: false, completed: true },
            { name: 'Trigger GitHub Actions', current: false, completed: true },
            { name: 'Deploy to Workers for Platforms', current: false, completed: true },
            { name: 'Configure routing', current: false, completed: true }
          ]
        )
      end
    end
    
    if result[:success]
      Rails.logger.info "Successfully deployed app #{app.id} to #{environment}"
      
      # Update app URLs based on deployment type
      if environment == "preview"
        app.update!(
          preview_url: result[:worker_url] || result[:deployment_url],
          status: 'generated'
        )
        Rails.logger.info "[DeployAppJob] Updated preview_url: #{app.preview_url}"
      elsif environment == "production"
        app.update!(
          production_url: result[:worker_url] || result[:deployment_url],
          published_at: Time.current,
          status: 'published'
        )
        Rails.logger.info "[DeployAppJob] Updated production_url: #{app.production_url}"
      end
      
      # Create a new version to track this deployment with snapshot
      app.app_versions.create!(
        version_number: generate_version_number(app),
        changelog: "Deployed to #{environment}",
        team: app.team,
        files_snapshot: app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json
      )
      
      # Final success progress broadcast
      broadcast_deployment_progress(app, 
        status: 'deployed', 
        progress: 100, 
        phase: 'Deployment completed!',
        deployment_url: result[:worker_url] || result[:deployment_url],
        deployment_steps: [
          { name: 'Build app', current: false, completed: true, duration: 15 },
          { name: 'Deploy to Cloudflare', current: false, completed: true, duration: 8 },
          { name: 'Configure routes', current: false, completed: true, duration: 3 },
          { name: 'Setup environment', current: false, completed: true, duration: 2 }
        ]
      )
      
      # Broadcast preview frame update for preview deployments
      if environment == "preview" && app.preview_url.present?
        broadcast_preview_frame_update(app)
      end
      
      # Broadcast success to any connected clients
      broadcast_deployment_update(app, 'deployed', result[:deployment_url] || result[:worker_url])
    else
      Rails.logger.error "Failed to deploy app #{app.id}: #{result[:error]}"
      
      app.update!(status: 'failed')
      
      # Broadcast deployment failure
      broadcast_deployment_progress(app, 
        status: 'failed', 
        deployment_error: result[:error]
      )
      
      broadcast_deployment_update(app, 'failed', result[:error])
    end
  rescue => e
    Rails.logger.error "Deployment job failed for app #{app_id}: #{e.message}"
    
    app&.update!(status: 'failed')
    
    # Broadcast failure for unexpected errors
    if app
      broadcast_deployment_progress(app, 
        status: 'failed', 
        deployment_error: e.message
      )
      broadcast_deployment_update(app, 'failed', e.message)
    end
  end
  
  private
  
  def generate_version_number(app)
    last_version = app.app_versions.order(created_at: :desc).first
    
    if last_version
      # Increment patch version (e.g., 1.0.1 -> 1.0.2)
      version_parts = last_version.version_number.split('.').map(&:to_i)
      version_parts[2] = (version_parts[2] || 0) + 1
      version_parts.join('.')
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
    latest_message = app.app_chat_messages.where(role: 'assistant').order(created_at: :desc).first
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
    
    # IMPORTANT: Dynamically add deployment attributes to message object for view rendering
    # These methods are checked with respond_to? in _agent_reply_v5.html.erb to avoid NoMethodError
    # when deployment is not active. Non-persistent, just for broadcasting.
    deployment_data.each { |key, value| latest_message.define_singleton_method(key) { value } }
    
    # Broadcast the updated message to the chat channel
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}_chat",
      target: "app_chat_message_#{latest_message.id}",
      partial: "account/app_editors/agent_reply_v5",
      locals: { message: latest_message, app: app }
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

  def broadcast_preview_frame_update(app)
    Rails.logger.info "[DeployAppJob] Broadcasting preview frame update for app #{app.id}"
    
    # Broadcast to the app channel that users are subscribed to
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}",
      target: "preview_frame",
      partial: "account/app_editors/preview_frame",
      locals: { app: app }
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
end