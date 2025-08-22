class Deployment::GithubActionsMonitorService
  include HTTParty
  base_uri 'https://api.github.com'
  
  def initialize(app)
    @app = app
    @github_auth = Deployment::GithubAppAuthenticator.new
  end
  
  def monitor_deployment(max_wait_time: 10.minutes, check_interval: 30.seconds)
    Rails.logger.info "[GithubActionsMonitor] Starting workflow monitoring for app #{@app.id}"
    
    # Retry getting workflow runs for up to 3 minutes for new repos
    workflow_runs = get_workflow_runs_with_retry(max_retry_time: 3.minutes)
    return { success: false, error: "No workflow runs found after 3 minutes of retrying" } if workflow_runs.empty?
    
    latest_run = workflow_runs.first
    Rails.logger.info "[GithubActionsMonitor] Monitoring workflow run #{latest_run['id']} (#{latest_run['status']})"
    
    start_time = Time.current
    
    while Time.current < start_time + max_wait_time
      run_status = get_workflow_run_status(latest_run['id'])
      
      case run_status['status']
      when 'completed'
        if run_status['conclusion'] == 'success'
          Rails.logger.info "[GithubActionsMonitor] Deployment successful for app #{@app.id}"
          return {
            success: true,
            workflow_run_id: latest_run['id'],
            deployment_url: generate_deployment_url,
            message: "GitHub Actions deployment completed successfully"
          }
        else
          Rails.logger.error "[GithubActionsMonitor] Deployment failed for app #{@app.id}: #{run_status['conclusion']}"
          return handle_deployment_failure(latest_run['id'])
        end
      when 'in_progress', 'queued'
        Rails.logger.info "[GithubActionsMonitor] Workflow still running, checking again in #{check_interval} seconds"
        sleep check_interval.to_i
        next
      else
        Rails.logger.error "[GithubActionsMonitor] Unknown workflow status: #{run_status['status']}"
        break
      end
    end
    
    # Timeout occurred
    Rails.logger.error "[GithubActionsMonitor] Timeout waiting for deployment completion"
    {
      success: false,
      error: "Deployment timed out after #{max_wait_time} seconds",
      workflow_run_id: latest_run['id']
    }
  end
  
  private
  
  def get_workflow_runs_with_retry(max_retry_time: 3.minutes)
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
    Rails.logger.info "[GithubActionsMonitor] Fetching workflow runs for #{@app.repository_name}"
    
    retries = 0
    max_retries = 3
    delay = 5 # Start with 5 second delay
    
    begin
      # Wait before first attempt if this is a new repo (created within last 2 minutes)
      if @app.created_at > 2.minutes.ago && retries == 0
        Rails.logger.info "[GithubActionsMonitor] New repo detected, waiting #{delay}s for GitHub to propagate permissions"
        sleep delay
      end
      
      response = self.class.get(
        "/repos/#{@app.repository_name}/actions/runs",
        headers: {
          'Authorization' => "token #{@github_auth.get_installation_token(@app.repository_name)}",
          'Accept' => 'application/vnd.github.v3+json'
        },
        query: {
          per_page: 5,
          status: 'completed,in_progress,queued'
        }
      )
      
      if response.success?
        runs = response['workflow_runs'] || []
        
        # If no runs found but repo is very new, retry
        if runs.empty? && @app.created_at > 1.minute.ago && retries < max_retries
          raise "No runs found for new repo, retrying..."
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
      "/repos/#{@app.repository_name}/actions/runs/#{run_id}",
      headers: {
        'Authorization' => "token #{@github_auth.get_installation_token(@app.repository_name)}",
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
      "/repos/#{@app.repository_name}/actions/runs/#{run_id}/jobs",
      headers: {
        'Authorization' => "token #{@github_auth.get_installation_token(@app.repository_name)}",
        'Accept' => 'application/vnd.github.v3+json'
      }
    )
    
    return { error: "Failed to fetch jobs" } unless jobs_response.success?
    
    logs = []
    jobs_response['jobs'].each do |job|
      if job['conclusion'] == 'failure'
        # Get logs for failed job
        logs_response = self.class.get(
          "/repos/#{@app.repository_name}/actions/jobs/#{job['id']}/logs",
          headers: {
            'Authorization' => "token #{@github_auth.get_installation_token(@app.repository_name)}",
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
  
  def handle_deployment_failure(run_id)
    Rails.logger.info "[GithubActionsMonitor] Handling deployment failure, attempting automatic fix"
    
    # Get detailed error logs
    error_logs = get_workflow_run_logs(run_id)
    
    if error_logs.any?
      # Attempt automatic fix using error detection service
      fix_result = attempt_automatic_fix(error_logs)
      
      if fix_result[:success]
        Rails.logger.info "[GithubActionsMonitor] Automatic fix successful, retriggering deployment"
        
        # Broadcast success to chat
        broadcast_auto_fix_success(fix_result)
        
        # Re-trigger deployment by making a new commit
        push_fix_and_retrigger(fix_result[:fixes])
        
        # Monitor the new deployment
        return monitor_deployment(max_wait_time: 8.minutes)
      else
        Rails.logger.warn "[GithubActionsMonitor] Automatic fix failed, reporting error to AI chat"
        
        # Report error back to AI chat for manual intervention
        broadcast_build_error_to_chat(error_logs, fix_result[:error])
        
        return {
          success: false,
          error: "Build failed and automatic fix unsuccessful",
          workflow_run_id: run_id,
          error_logs: error_logs,
          fix_attempted: true,
          fix_error: fix_result[:error]
        }
      end
    else
      return {
        success: false,
        error: "Build failed but unable to retrieve error logs",
        workflow_run_id: run_id
      }
    end
  end
  
  def attempt_automatic_fix(error_logs)
    Rails.logger.info "[GithubActionsMonitor] Attempting automatic error fix"
    
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
  
  def generate_deployment_url
    subdomain = @app.obfuscated_id.downcase
    "https://#{subdomain}.overskill.app"
  end
end