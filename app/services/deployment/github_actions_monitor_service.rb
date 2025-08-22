class Deployment::GithubActionsMonitorService
  include HTTParty
  base_uri 'https://api.github.com'
  
  def initialize(app)
    @app = app
    @github_auth = Deployment::GithubAppAuthenticator.new
  end

  # Helper method to get the organization from the github_repo
  def organization_name
    @organization_name ||= @app.github_repo&.split('/')&.first || 'Overskill-apps'
  end
  
  def monitor_deployment(max_wait_time: 10.minutes, check_interval: 30.seconds, message: nil)
    Rails.logger.info "[GithubActionsMonitor] Starting workflow monitoring for app #{@app.id}"
    
    # Retry getting workflow runs for up to 3 minutes for new repos
    workflow_runs = get_workflow_runs_with_retry(max_retry_time: 3.minutes)
    return { success: false, error: "No workflow runs found after 3 minutes of retrying" } if workflow_runs.empty?
    
    latest_run = workflow_runs.first
    build_start_time = Time.parse(latest_run['created_at'])
    monitoring_start = Time.current
    
    Rails.logger.info "[GithubActionsMonitor] Monitoring workflow run #{latest_run['id']} (#{latest_run['status']})"
    
    # Store build timing information in the message if provided
    if message
      Rails.logger.info "[GithubActionsMonitor] Updating message #{message.id} metadata with workflow_run_id: #{latest_run['id']}, status: #{latest_run['status']}"
      
      message.update!(
        metadata: (message.metadata || {}).merge({
          build_started_at: build_start_time,
          workflow_run_id: latest_run['id'],
          build_status: latest_run['status']
        })
      )
      
      Rails.logger.info "[GithubActionsMonitor] Message metadata after update: #{message.reload.metadata.inspect}"
      
      # Broadcast initial build status
      broadcast_build_status(message, {
        status: 'in_progress',
        elapsed_seconds: 0,
        estimated_total_seconds: 120, # 2 minutes default estimate
        workflow_run_id: latest_run['id']
      })
    end
    
    while Time.current < monitoring_start + max_wait_time
      run_status = get_workflow_run_status(latest_run['id'])
      elapsed_seconds = (Time.current - build_start_time).to_i
      
      # Update build status in real-time
      if message
        broadcast_build_status(message, {
          status: run_status['status'],
          elapsed_seconds: elapsed_seconds,
          estimated_total_seconds: 120,
          workflow_run_id: latest_run['id']
        })
      end
      
      case run_status['status']
      when 'completed'
        total_build_time = (Time.current - build_start_time).to_i
        
        # Update final build timing
        if message
          message.update!(
            metadata: message.metadata.merge({
              build_completed_at: Time.current,
              total_build_seconds: total_build_time,
              build_status: 'completed',
              build_conclusion: run_status['conclusion']
            })
          )
        end
        
        if run_status['conclusion'] == 'success'
          Rails.logger.info "[GithubActionsMonitor] Deployment successful for app #{@app.id} in #{total_build_time}s"
          
          # Broadcast final success status
          if message
            broadcast_build_status(message, {
              status: 'completed',
              conclusion: 'success',
              elapsed_seconds: total_build_time,
              workflow_run_id: latest_run['id']
            })
          end
          
          return {
            success: true,
            workflow_run_id: latest_run['id'],
            deployment_url: generate_deployment_url,
            message: "GitHub Actions deployment completed successfully",
            build_time_seconds: total_build_time
          }
        else
          Rails.logger.error "[GithubActionsMonitor] Deployment failed for app #{@app.id}: #{run_status['conclusion']}"
          
          # Broadcast failure status
          if message
            broadcast_build_status(message, {
              status: 'completed',
              conclusion: 'failure',
              elapsed_seconds: total_build_time,
              workflow_run_id: latest_run['id']
            })
          end
          
          return handle_deployment_failure(latest_run['id'])
        end
      when 'in_progress', 'queued'
        Rails.logger.info "[GithubActionsMonitor] Workflow still running (#{elapsed_seconds}s elapsed), checking again in #{check_interval} seconds"
        sleep check_interval.to_i
        next
      else
        Rails.logger.error "[GithubActionsMonitor] Unknown workflow status: #{run_status['status']}"
        break
      end
    end
    
    # Timeout occurred
    total_elapsed = (Time.current - build_start_time).to_i
    Rails.logger.error "[GithubActionsMonitor] Timeout waiting for deployment completion after #{total_elapsed}s"
    
    if message
      broadcast_build_status(message, {
        status: 'timeout',
        elapsed_seconds: total_elapsed,
        workflow_run_id: latest_run['id']
      })
    end
    
    {
      success: false,
      error: "Deployment timed out after #{total_elapsed} seconds",
      workflow_run_id: latest_run['id'],
      build_time_seconds: total_elapsed
    }
  end
  
  private
  
  def get_workflow_runs_with_retry(max_retry_time: 5.minutes)
    Rails.logger.info "[GithubActionsMonitor] Will retry getting workflow runs for up to #{max_retry_time}"
    
    start_time = Time.current
    attempt = 0
    delay = 10 # Start with 10 second delay
    
    while Time.current < start_time + max_retry_time
      attempt += 1
      Rails.logger.info "[GithubActionsMonitor] Attempt #{attempt} to get workflow runs"
      
      runs = get_workflow_runs
      if runs.any?
        Rails.logger.info "[GithubActionsMonitor] Found #{runs.count} workflow runs"
        return runs
      end
      
      # Calculate remaining time
      elapsed = Time.current - start_time
      remaining = max_retry_time - elapsed
      
      if remaining > delay
        Rails.logger.info "[GithubActionsMonitor] No runs found, waiting #{delay}s before retry (#{remaining.to_i}s remaining)"
        sleep delay
        delay = [delay * 1.5, 30].min # Increase delay up to max 30s
      else
        Rails.logger.warn "[GithubActionsMonitor] Exhausted retry time after #{attempt} attempts"
        break
      end
    end
    
    []
  end
  
  def get_workflow_runs
    Rails.logger.info "[GithubActionsMonitor] Fetching workflow runs for #{@app.github_repo}"
    
    retries = 0
    max_retries = 3
    delay = 5 # Start with 5 second delay
    
    begin
      # Always wait on first attempt for new deployments to allow GitHub propagation
      # Check if GitHub repo was recently created (within last 10 minutes)
      # Using updated_at as proxy since that's when repo info is set
      repo_is_new = @app.github_repo.present? && @app.updated_at > 10.minutes.ago
      
      if repo_is_new && retries == 0
        Rails.logger.info "[GithubActionsMonitor] Recently updated repo detected, waiting #{delay}s for GitHub to propagate permissions"
        sleep delay
      end
      
      response = self.class.get(
        "/repos/#{@app.github_repo}/actions/runs",
        headers: {
          'Authorization' => "token #{@github_auth.get_installation_token(organization_name)}",
          'Accept' => 'application/vnd.github.v3+json'
        },
        query: {
          per_page: 5,
          status: 'completed,in_progress,queued'
        }
      )
      
      if response.success?
        runs = response['workflow_runs'] || []
        
        # If no runs found and repo was recently updated, retry
        # This handles the race condition where workflow hasn't started yet
        if runs.empty? && repo_is_new && retries < max_retries
          raise "No runs found for recently updated repo, retrying..."
        end
        
        return runs
      elsif response.code == 404 && retries < max_retries
        raise "404 error, likely permissions not ready"
      else
        Rails.logger.error "[GithubActionsMonitor] Failed to fetch workflow runs: #{response.code} - #{response.body}"
        return []
      end
      
    rescue => e
      retries += 1
      if retries <= max_retries
        Rails.logger.info "[GithubActionsMonitor] Retry #{retries}/#{max_retries} after #{delay}s: #{e.message}"
        sleep delay
        delay *= 2 # Exponential backoff
        retry
      else
        Rails.logger.error "[GithubActionsMonitor] All retries exhausted: #{e.message}"
        return []
      end
    end
  end
  
  def get_workflow_run_status(run_id)
    Rails.logger.info "[GithubActionsMonitor] Checking status of workflow run #{run_id}"
    
    response = self.class.get(
      "/repos/#{@app.github_repo}/actions/runs/#{run_id}",
      headers: {
        'Authorization' => "token #{@github_auth.get_installation_token(organization_name)}",
        'Accept' => 'application/vnd.github.v3+json'
      }
    )
    
    if response.success?
      response.parsed_response
    else
      Rails.logger.error "[GithubActionsMonitor] Failed to fetch workflow run status: #{response.code} - #{response.body}"
      { 'status' => 'unknown', 'conclusion' => 'failure' }
    end
  end
  
  def get_workflow_run_logs(run_id)
    Rails.logger.info "[GithubActionsMonitor] Fetching logs for workflow run #{run_id}"
    
    # Get jobs for this workflow run
    jobs_response = self.class.get(
      "/repos/#{@app.github_repo}/actions/runs/#{run_id}/jobs",
      headers: {
        'Authorization' => "token #{@github_auth.get_installation_token(organization_name)}",
        'Accept' => 'application/vnd.github.v3+json'
      }
    )
    
    return { error: "Failed to fetch jobs" } unless jobs_response.success?
    
    logs = []
    jobs_response['jobs'].each do |job|
      if job['conclusion'] == 'failure'
        # Get logs for failed job
        logs_response = self.class.get(
          "/repos/#{@app.github_repo}/actions/jobs/#{job['id']}/logs",
          headers: {
            'Authorization' => "token #{@github_auth.get_installation_token(organization_name)}",
            'Accept' => 'application/vnd.github.v3+json'
          }
        )
        
        if logs_response.success?
          logs << {
            job_name: job['name'],
            job_id: job['id'],
            logs: logs_response.body,
            steps: extract_failed_steps(job)
          }
        end
      end
    end
    
    logs
  end
  
  def extract_failed_steps(job)
    failed_steps = []
    
    job['steps']&.each do |step|
      if step['conclusion'] == 'failure'
        failed_steps << {
          name: step['name'],
          number: step['number'],
          conclusion: step['conclusion']
        }
      end
    end
    
    failed_steps
  end
  
  def handle_deployment_failure(run_id, retry_count = 0)
    Rails.logger.info "[GithubActionsMonitor] Handling deployment failure (attempt #{retry_count + 1}), attempting automatic fix"
    
    # Get detailed error logs
    error_logs = get_workflow_run_logs(run_id)
    
    if error_logs.any?
      # Attempt automatic fix using error detection service
      fix_result = attempt_automatic_fix(error_logs, retry_count)
      
      if fix_result[:success]
        Rails.logger.info "[GithubActionsMonitor] Automatic fix successful, retriggering deployment"
        
        # Broadcast success to chat
        broadcast_auto_fix_success(fix_result)
        
        # Re-trigger deployment by making a new commit
        push_result = push_fix_and_retrigger(fix_result[:fixes])
        
        if push_result[:success]
          # Monitor the new deployment with retry tracking
          return monitor_deployment_with_retry(max_wait_time: 8.minutes, retry_count: retry_count)
        else
          Rails.logger.error "[GithubActionsMonitor] Failed to push fixes: #{push_result[:error]}"
          return handle_retry_strategy(error_logs, fix_result, retry_count, "Push failed: #{push_result[:error]}")
        end
      else
        Rails.logger.warn "[GithubActionsMonitor] Automatic fix failed: #{fix_result[:error]}"
        return handle_retry_strategy(error_logs, fix_result, retry_count, fix_result[:error])
      end
    else
      Rails.logger.error "[GithubActionsMonitor] No error logs available for automatic fixing"
      return handle_retry_strategy([], { success: false, error: "No error logs available" }, retry_count, "No error logs available")
    end
  end
  
  def handle_retry_strategy(error_logs, fix_result, retry_count, error_message)
    max_retries = determine_max_retries(error_logs)
    
    if retry_count < max_retries && should_retry?(error_logs, fix_result, retry_count)
      Rails.logger.info "[GithubActionsMonitor] Scheduling retry #{retry_count + 1}/#{max_retries} with delay"
      
      # Calculate progressive delay: 30s, 60s, 120s
      delay_seconds = [30, 60, 120][retry_count] || 180
      
      # Broadcast retry status to chat
      broadcast_retry_attempt(retry_count + 1, max_retries, delay_seconds, error_message)
      
      # Schedule retry with delay
      sleep(delay_seconds)
      
      # Get fresh workflow run for retry
      latest_runs = get_workflow_runs
      if latest_runs.any?
        latest_run = latest_runs.first
        return handle_deployment_failure(latest_run['id'], retry_count + 1)
      else
        Rails.logger.error "[GithubActionsMonitor] No workflow runs found for retry"
        return build_final_failure_response(error_logs, fix_result, retry_count, "No workflow runs found for retry")
      end
    else
      Rails.logger.warn "[GithubActionsMonitor] Maximum retries exceeded or not retryable, reporting to AI chat"
      broadcast_build_error_to_chat(error_logs, error_message)
      return build_final_failure_response(error_logs, fix_result, retry_count, error_message)
    end
  end
  
  def monitor_deployment_with_retry(max_wait_time:, retry_count:)
    result = monitor_deployment(max_wait_time: max_wait_time)
    
    # If deployment fails again, check if we should retry
    if !result[:success] && result[:workflow_run_id]
      return handle_deployment_failure(result[:workflow_run_id], retry_count)
    end
    
    result
  end
  
  def determine_max_retries(error_logs)
    # Analyze error logs to determine appropriate retry count
    error_detector = Deployment::BuildErrorDetectorService.new(@app)
    detected_errors = error_detector.analyze_build_errors(error_logs)
    
    return 0 if detected_errors.empty? # No retries if we can't detect errors
    
    auto_fixable_count = detected_errors.count { |error| error[:auto_fixable] }
    total_errors = detected_errors.length
    
    case
    when auto_fixable_count == total_errors && total_errors <= 3
      3 # High confidence in fixing simple errors
    when auto_fixable_count >= (total_errors * 0.7) && total_errors <= 5
      2 # Good confidence in fixing most errors
    when auto_fixable_count > 0
      1 # Some confidence in fixing at least some errors
    else
      0 # No auto-fixable errors detected
    end
  end
  
  def should_retry?(error_logs, fix_result, retry_count)
    # Don't retry if this is a completely different type of failure
    return false if error_logs.empty?
    
    # Don't retry if we've already tried and the error types haven't changed
    if retry_count > 0 && fix_result[:error]&.include?("No fixable errors detected")
      return false
    end
    
    # Don't retry dependency conflicts or infrastructure issues
    error_detector = Deployment::BuildErrorDetectorService.new(@app)
    detected_errors = error_detector.analyze_build_errors(error_logs)
    
    non_retryable_types = [:dependency_conflict, :dependency_resolution_error]
    return false if detected_errors.any? { |error| non_retryable_types.include?(error[:type]) }
    
    # Retry if we have any auto-fixable errors
    detected_errors.any? { |error| error[:auto_fixable] }
  end
  
  def build_final_failure_response(error_logs, fix_result, retry_count, error_message)
    {
      success: false,
      error: "Build failed after #{retry_count + 1} attempts: #{error_message}",
      error_logs: error_logs,
      fix_attempted: true,
      retry_count: retry_count,
      fix_error: fix_result[:error]
    }
  end
  
  def broadcast_retry_attempt(attempt_number, max_attempts, delay_seconds, error_message)
    # Find the latest assistant message to attach the retry notification
    latest_message = @app.app_chat_messages.where(role: 'assistant').order(created_at: :desc).first
    return unless latest_message
    
    retry_message = "🔄 **Auto-Retry #{attempt_number}/#{max_attempts}**\n\n" \
                   "Build failed with: #{error_message}\n\n" \
                   "Retrying in #{delay_seconds} seconds with enhanced error detection and fixing..."
    
    @app.app_chat_messages.create!(
      role: 'assistant',
      content: retry_message,
      team: @app.team,
      metadata: {
        retry_attempt: attempt_number,
        max_attempts: max_attempts,
        delay_seconds: delay_seconds,
        error_message: error_message
      }
    )
  end
  
  def attempt_automatic_fix(error_logs, retry_count = 0)
    Rails.logger.info "[GithubActionsMonitor] Attempting automatic error fix (retry #{retry_count})"
    
    error_detector = Deployment::BuildErrorDetectorService.new(@app)
    fix_service = Deployment::AutoFixService.new(@app)
    
    detected_errors = error_detector.analyze_build_errors(error_logs)
    
    return { success: false, error: "No fixable errors detected" } if detected_errors.empty?
    
    fixes_applied = []
    
    detected_errors.each do |error|
      Rails.logger.info "[GithubActionsMonitor] Attempting to fix: #{error[:type]} in #{error[:file]}"
      
      fix_result = fix_service.apply_fix(error)
      
      if fix_result[:success]
        fixes_applied << {
          error_type: error[:type],
          file: error[:file],
          fix_description: fix_result[:description],
          changes: fix_result[:changes]
        }
      else
        Rails.logger.warn "[GithubActionsMonitor] Failed to fix #{error[:type]}: #{fix_result[:error]}"
        return {
          success: false,
          error: "Failed to apply fix for #{error[:type]}: #{fix_result[:error]}",
          partial_fixes: fixes_applied
        }
      end
    end
    
    {
      success: true,
      fixes: fixes_applied,
      message: "Applied #{fixes_applied.length} automatic fixes"
    }
  end
  
  def push_fix_and_retrigger(fixes)
    Rails.logger.info "[GithubActionsMonitor] Pushing automatic fixes to GitHub"
    
    github_service = Deployment::GithubRepositoryService.new(@app)
    
    # Create commit message describing the fixes
    commit_message = "🔧 Auto-fix build errors\n\n" + 
                    fixes.map { |fix| "- Fix #{fix[:error_type]} in #{fix[:file]}: #{fix[:fix_description]}" }.join("\n")
    
    # Get current file structure and apply fixes
    file_structure = @app.app_files.to_h { |file| [file.path, file.content] }
    
    push_result = github_service.push_file_structure(
      file_structure,
      commit_message: commit_message
    )
    
    unless push_result[:success]
      Rails.logger.error "[GithubActionsMonitor] Failed to push fixes: #{push_result[:error]}"
    end
    
    push_result
  end
  
  def broadcast_auto_fix_success(fix_result)
    # Find the latest assistant message to attach the fix notification
    latest_message = @app.app_chat_messages.where(role: 'assistant').order(created_at: :desc).first
    return unless latest_message
    
    fix_summary = fix_result[:fixes].map { |fix| "✅ Fixed #{fix[:error_type]} in #{fix[:file]}" }.join("\n")
    
    # Create a new message about the successful auto-fix
    @app.app_chat_messages.create!(
      role: 'assistant',
      content: "🔧 **Auto-Fix Successful**\n\nI detected build errors and automatically fixed them:\n\n#{fix_summary}\n\nDeployment has been retriggered and should complete successfully.",
      team: @app.team
    )
  end
  
  def broadcast_build_error_to_chat(error_logs, fix_error)
    # Create a comprehensive error report for the AI to respond to
    error_summary = error_logs.map do |log|
      "**#{log[:job_name]}** - Failed Steps:\n" + 
      log[:steps].map { |step| "- #{step[:name]}" }.join("\n") + 
      "\n\nBuild Output:\n```\n#{log[:logs].lines.last(20).join}```"
    end.join("\n\n")
    
    @app.app_chat_messages.create!(
      role: 'assistant',
      content: "❌ **Build Failed - Manual Intervention Needed**\n\nThe GitHub Actions build failed and automatic fixing was unsuccessful.\n\n**Error Details:**\n#{error_summary}\n\n**Auto-fix Error:** #{fix_error}\n\nPlease review the errors and let me know how you'd like to proceed. I can help fix these issues manually.",
      team: @app.team
    )
  end
  
  def broadcast_build_status(message, status_data)
    # Broadcast build status updates via ActionCable for real-time UI updates
    # This is used by the build_countdown_controller.js to update the timer in real-time
    ActionCable.server.broadcast(
      "app_#{@app.id}_build_status",
      {
        type: 'build_status_update',
        message_id: message.id,
        build_status: status_data,
        app_id: @app.id
      }
    )
    
    Rails.logger.info "[GithubActionsMonitor] Broadcasting build status: #{status_data[:status]} (#{status_data[:elapsed_seconds]}s elapsed)"
    
    # Note: The AppChatMessage model will automatically broadcast the updated partial
    # when metadata changes via its after_update_commit callback, so we don't need
    # to manually broadcast the Turbo Stream update here anymore.
  end

  def generate_deployment_url
    subdomain = @app.obfuscated_id.downcase
    "https://#{subdomain}.overskill.app"
  end
end