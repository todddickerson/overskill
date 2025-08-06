class BuildAppJob < ApplicationJob
  queue_as :builds
  
  # Build a React/TypeScript app with Vite
  def perform(app_id)
    app = App.find(app_id)
    
    Rails.logger.info "[BuildAppJob] Building app #{app.id}: #{app.name}"
    
    # Update status
    app.update!(build_status: 'building')
    
    # Broadcast to UI
    broadcast_build_status(app, 'building', 'Starting build process...')
    
    # Run the build
    service = Build::ViteBuildService.new(app)
    result = service.build!
    
    if result[:success]
      Rails.logger.info "[BuildAppJob] Build successful for app #{app.id}"
      
      app.update!(
        build_status: 'success',
        last_built_at: Time.current,
        build_id: result[:build_id]
      )
      
      broadcast_build_status(app, 'success', 'Build complete!')
      
      # Queue deployment with built files
      DeployBuiltAppJob.perform_later(app.id)
    else
      Rails.logger.error "[BuildAppJob] Build failed for app #{app.id}: #{result[:error]}"
      
      app.update!(
        build_status: 'failed',
        build_error: result[:error]
      )
      
      broadcast_build_status(app, 'failed', result[:error])
    end
    
  rescue => e
    Rails.logger.error "[BuildAppJob] Exception: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    app.update!(build_status: 'failed', build_error: e.message) if app
    broadcast_build_status(app, 'failed', e.message) if app
  end
  
  private
  
  def broadcast_build_status(app, status, message)
    # Broadcast to ActionCable
    ActionCable.server.broadcast(
      "app_#{app.id}_build",
      {
        status: status,
        message: message,
        timestamp: Time.current.iso8601
      }
    )
    
    # Also update via Turbo Streams if in editor
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{app.id}_notifications",
      target: "notifications",
      partial: "shared/notification",
      locals: { 
        type: status == 'failed' ? 'error' : 'info',
        message: message 
      }
    )
  end
end