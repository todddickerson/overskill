class DeployAppJob < ApplicationJob
  queue_as :deployment
  
  def perform(app_id, environment = "production")
    app = App.find(app_id)
    
    # Update status to deploying
    app.update!(status: 'generating')
    
    # Use the new preview service
    service = Deployment::CloudflarePreviewService.new(app)
    
    # Deploy based on environment
    result = case environment
    when "staging"
      service.deploy_staging!
    when "production"
      service.deploy_production!
    else
      { success: false, error: "Invalid environment: #{environment}" }
    end
    
    if result[:success]
      Rails.logger.info "Successfully deployed app #{app.id} to #{result[:message]}"
      
      # Create a new version to track this deployment with snapshot
      app.app_versions.create!(
        version_number: generate_version_number(app),
        changelog: "Deployed to production at #{result[:message]}",
        team: app.team,
        files_snapshot: app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json
      )
      
      # Broadcast success to any connected clients
      broadcast_deployment_update(app, 'deployed', result[:message])
    else
      Rails.logger.error "Failed to deploy app #{app.id}: #{result[:error]}"
      
      app.update!(status: 'failed')
      broadcast_deployment_update(app, 'failed', result[:error])
    end
  rescue => e
    Rails.logger.error "Deployment job failed for app #{app_id}: #{e.message}"
    
    app&.update!(status: 'failed')
    broadcast_deployment_update(app, 'failed', e.message) if app
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
end