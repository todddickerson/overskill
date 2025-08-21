class FastPreviewDeploymentJob < ApplicationJob
  include ActiveJob::Uniqueness
  
  queue_as :deployment
  
  # Prevent duplicate fast preview deployments for the same app
  unique :until_executed, lock_ttl: 5.minutes, on_conflict: :log
  
  # Define uniqueness based on app_id
  def lock_key
    "fast_preview_deploy:app:#{arguments.first}"
  end
  
  # Deploy app instantly without build step (< 3 seconds)
  def perform(app_id)
    app = App.find(app_id)
    
    Rails.logger.info "[FastPreview] Deploying app #{app.id} instantly"
    
    # Use the fast preview service
    service = Deployment::FastPreviewService.new(app)
    result = service.deploy_instant_preview!
    
    if result[:success]
      Rails.logger.info "[FastPreview] Deployed successfully to #{result[:preview_url]}"
      
      # Broadcast success
      broadcast_deployment_status(app, 'deployed', result[:preview_url])
      
      # Also refresh the preview iframe
      broadcast_preview_refresh(app, result[:preview_url])
    else
      Rails.logger.error "[FastPreview] Deployment failed: #{result[:error]}"
      
      app.update!(deployment_status: 'failed', deployment_error: result[:error])
      broadcast_deployment_status(app, 'failed', result[:error])
    end
    
  rescue => e
    Rails.logger.error "[FastPreview] Exception: #{e.message}"
    broadcast_deployment_status(app, 'failed', e.message) if app
  end
  
  private
  
  def broadcast_deployment_status(app, status, message)
    ActionCable.server.broadcast(
      "app_#{app.id}_deployment",
      {
        status: status,
        message: message,
        preview_url: app.preview_url,
        timestamp: Time.current.iso8601
      }
    )
  end
  
  def broadcast_preview_refresh(app, preview_url)
    # Send JavaScript to refresh preview iframe
    javascript_code = <<~JS
      window.dispatchEvent(new CustomEvent('preview-updated', {
        detail: {
          appId: '#{app.id}',
          previewUrl: '#{preview_url}'
        }
      }));
    JS
    
    Turbo::StreamsChannel.broadcast_action_to(
      "app_#{app.id}_chat",
      action: "append",
      target: "body",
      html: "<script>#{javascript_code}</script>"
    )
  end
end