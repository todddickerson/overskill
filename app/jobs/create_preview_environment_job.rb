class CreatePreviewEnvironmentJob < ApplicationJob
  include ActiveJob::Uniqueness

  queue_as :deployment
  
  # Prevent duplicate preview environment creation for the same app
  unique :until_executed, lock_ttl: 5.minutes, on_conflict: :log
  
  def lock_key_arguments
    [arguments.first.to_i] # app_id
  end
  
  def perform(app_id, user_id = nil)
    app = App.find(app_id)
    user = user_id ? User.find(user_id) : nil
    
    Rails.logger.info "[CreatePreviewEnvironmentJob] Creating preview environment for app #{app.id}"
    
    # Update preview status to creating
    app.update!(preview_status: 'creating')
    
    # Broadcast initial progress
    broadcast_preview_progress(app, 
      status: 'creating', 
      progress: 10, 
      message: 'Initializing preview environment...'
    )
    
    # Create preview environment with WFP service
    preview_service = Deployment::WfpPreviewService.new(app)
    
    # Track deployment time
    start_time = Time.current
    
    begin
      # Create the preview environment
      broadcast_preview_progress(app, 
        status: 'creating', 
        progress: 30, 
        message: 'Deploying preview worker...'
      )
      
      result = preview_service.create_preview_environment
      
      if result[:success] != false
        deployment_time = Time.current - start_time
        
        Rails.logger.info "[CreatePreviewEnvironmentJob] Preview environment created in #{deployment_time.round(2)}s"
        Rails.logger.info "[CreatePreviewEnvironmentJob] Preview URL: #{result[:preview_url]}"
        
        # Update app with success status
        app.update!(
          preview_status: 'ready',
          preview_deployment_time: deployment_time
        )
        
        # Broadcast completion
        broadcast_preview_progress(app,
          status: 'ready',
          progress: 100,
          message: 'Preview environment ready!',
          preview_url: result[:preview_url],
          websocket_url: result[:websocket_url],
          deployment_time: deployment_time.round(2)
        )
        
        Rails.logger.info "[CreatePreviewEnvironmentJob] Successfully created preview environment for app #{app.id}"
        
      else
        raise StandardError.new("Preview creation failed: #{result[:error]}")
      end
      
    rescue => e
      Rails.logger.error "[CreatePreviewEnvironmentJob] Failed to create preview environment: #{e.message}"
      
      # Update app with error status
      app.update!(
        preview_status: 'error',
        preview_error: e.message
      )
      
      # Broadcast error
      broadcast_preview_progress(app,
        status: 'error',
        progress: 0,
        message: "Preview creation failed: #{e.message}",
        error: e.message
      )
      
      raise e
    end
  end
  
  private
  
  def broadcast_preview_progress(app, data)
    # Broadcast to the app's preview channel
    ActionCable.server.broadcast(
      "app_preview_#{app.id}",
      {
        type: 'preview_progress',
        app_id: app.id,
        timestamp: Time.current
      }.merge(data)
    )
    
    # Also broadcast to unified app channel for UI updates
    ActionCable.server.broadcast(
      "unified_app_#{app.id}",
      {
        type: 'preview_progress',
        app_id: app.id,
        timestamp: Time.current
      }.merge(data)
    )
  end
end