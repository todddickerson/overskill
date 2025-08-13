class DeployBuiltAppJob < ApplicationJob
  queue_as :deployment
  
  # Deploy built app files to Cloudflare Workers
  def perform(app_id)
    app = App.find(app_id)
    
    Rails.logger.info "[DeployBuiltApp] Deploying built app #{app.id}"
    
    # Get built files (from dist/ directory)
    built_files = app.app_files.where("path LIKE ?", "dist/%")
    
    if built_files.empty?
      Rails.logger.warn "[DeployBuiltApp] No built files found, using source files"
      # Fall back to source files
      deploy_source_files(app)
    else
      deploy_built_files(app, built_files)
    end
    
  rescue => e
    Rails.logger.error "[DeployBuiltApp] Failed: #{e.message}"
    app.update!(deployment_status: 'failed', deployment_error: e.message)
  end
  
  private
  
  def deploy_built_files(app, built_files)
    Rails.logger.info "[DeployBuiltApp] Deploying #{built_files.count} built files"
    
    # Create a modified CloudflarePreviewService that serves built files
    service = Deployment::CloudflareBuiltAppService.new(app, built_files)
    result = service.deploy_production!
    
    if result[:success]
      app.update!(
        deployment_status: 'deployed',
        deployment_url: result[:deployment_url],
        deployed_at: Time.current,
        status: 'published'
      )
      
      broadcast_deployment(app, 'success', result[:deployment_url])
    else
      raise "Deployment failed: #{result[:error]}"
    end
  end
  
  def deploy_source_files(app)
    # Fallback: deploy source files directly (current behavior)
    service = Deployment::CloudflarePreviewService.new(app)
    result = service.deploy_production!
    
    if result[:success]
      app.update!(
        deployment_status: 'deployed',
        deployment_url: result[:deployment_url],
        deployed_at: Time.current,
        status: 'published'
      )
      
      broadcast_deployment(app, 'success', result[:deployment_url])
    else
      raise "Deployment failed: #{result[:error]}"
    end
  end
  
  def broadcast_deployment(app, status, url)
    ActionCable.server.broadcast(
      "app_#{app.id}_deployment",
      {
        status: status,
        url: url,
        timestamp: Time.current.iso8601
      }
    )
  end
end