# Background job for publishing apps to production
class PublishAppToProductionJob < ApplicationJob
  queue_as :deployment
  
  def perform(app)
    Rails.logger.info "[PublishJob] Starting production deployment for app ##{app.id}"
    
    begin
      # Deploy to production
      service = Deployment::ProductionDeploymentService.new(app)
      result = service.deploy_to_production!
      
      if result[:success]
        Rails.logger.info "[PublishJob] Successfully published app ##{app.id} to #{result[:production_url]}"
        
        # Notify user via chat message
        create_success_message(app, result)
        
        # Broadcast success via ActionCable if chat is open
        broadcast_success(app, result)
      else
        Rails.logger.error "[PublishJob] Failed to publish app ##{app.id}: #{result[:error]}"
        
        # Notify user of failure
        create_failure_message(app, result[:error])
        
        # Reset status
        app.update!(status: 'ready')
      end
    rescue => e
      Rails.logger.error "[PublishJob] Exception publishing app ##{app.id}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      
      # Notify user of error
      create_failure_message(app, e.message)
      
      # Reset status
      app.update!(status: 'ready')
      
      # Re-raise for job retry if needed
      raise
    end
  end
  
  private
  
  def create_success_message(app, result)
    AppChatMessage.create!(
      app: app,
      user: app.creator.user,
      role: 'assistant',
      content: "🎉 **App successfully published to production!**\n\n" +
               "🔗 Production URL: #{result[:production_url]}\n" +
               "📦 Version: #{result[:version_number] || '1.0.0'}\n" +
               "⏱️ Deployed at: #{result[:deployed_at]&.strftime('%B %d, %Y at %I:%M %p')}\n\n" +
               "Your app is now live and accessible to users!",
      metadata: {
        type: 'deployment_success',
        production_url: result[:production_url],
        subdomain: result[:subdomain],
        worker_name: result[:worker_name]
      }.to_json
    )
  end
  
  def create_failure_message(app, error)
    AppChatMessage.create!(
      app: app,
      user: app.creator.user,
      role: 'assistant',
      content: "❌ **Failed to publish app to production**\n\n" +
               "Error: #{error}\n\n" +
               "Please try again or contact support if the issue persists.\n" +
               "Your preview deployment is still available at: #{app.preview_url}",
      metadata: {
        type: 'deployment_failure',
        error: error
      }.to_json
    )
  end
  
  def broadcast_success(app, result)
    # Broadcast to chat channel if user is watching
    ActionCable.server.broadcast(
      "app_#{app.id}_chat",
      {
        action: 'deployment_complete',
        status: 'success',
        production_url: result[:production_url],
        message: 'App published to production!'
      }
    )
  rescue => e
    Rails.logger.warn "[PublishJob] Failed to broadcast: #{e.message}"
  end
end