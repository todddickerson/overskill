class UpdatePreviewJob < ApplicationJob
  queue_as :preview_updates
  
  def perform(app_id)
    app = App.find(app_id)
    
    # Update the auto-preview worker with latest files
    service = Deployment::CloudflarePreviewService.new(app)
    result = service.update_preview!
    
    if result[:success]
      Rails.logger.info "Preview updated for app #{app.id} at #{result[:preview_url]}"
      
      # Broadcast update to connected clients
      broadcast_preview_update(app, 'updated', result[:preview_url])
    else
      Rails.logger.error "Failed to update preview for app #{app.id}: #{result[:error]}"
      broadcast_preview_update(app, 'failed', result[:error])
    end
  rescue => e
    Rails.logger.error "Preview update job failed for app #{app_id}: #{e.message}"
  end
  
  private
  
  def broadcast_preview_update(app, status, message)
    ActionCable.server.broadcast(
      "app_#{app.id}_preview",
      {
        status: status,
        message: message,
        preview_url: app.preview_url,
        updated_at: app.preview_updated_at&.iso8601
      }
    )
  end
end