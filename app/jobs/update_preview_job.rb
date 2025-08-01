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
      
      # Also broadcast via Turbo Stream to refresh the preview iframe
      broadcast_preview_refresh(app, result[:preview_url])
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
  
  def broadcast_preview_refresh(app, preview_url)
    # Broadcast a Turbo Stream with JavaScript to dispatch a custom event
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