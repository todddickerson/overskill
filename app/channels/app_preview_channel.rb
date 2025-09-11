# AppPreviewChannel - Real-time preview updates and HMR via ActionCable
# Provides WebSocket connection for instant code updates without page refresh
# Part of the Fast Deployment Architecture for sub-10s preview updates
#
# Rails ActionCable best practice: Use channels for real-time bidirectional communication
class AppPreviewChannel < ApplicationCable::Channel
  def subscribed
    # Stream from app-specific channel for isolated updates
    app = App.find(params[:app_id])
    stream_for app
    
    # Track active preview sessions for analytics
    Rails.cache.increment("preview_sessions:#{app.id}")
    
    # Send initial connection confirmation
    transmit({
      type: 'connected',
      app_id: app.id,
      preview_url: app.preview_url,
      hmr_enabled: true,
      session_id: SecureRandom.uuid
    })
    
    Rails.logger.info "[AppPreviewChannel] Client subscribed to app #{app.id} preview updates"
  end

  def unsubscribed
    # Clean up any preview session data
    if params[:app_id]
      Rails.cache.decrement("preview_sessions:#{params[:app_id]}")
      Rails.logger.info "[AppPreviewChannel] Client unsubscribed from app #{params[:app_id]} preview"
    end
  end

  # Handle file updates from the editor
  def update_file(data)
    app = App.find(params[:app_id])
    file_path = data['path']
    content = data['content']
    
    Rails.logger.info "[AppPreviewChannel] Updating file #{file_path} for app #{app.id}"
    
    # Update file in database
    app_file = app.app_files.find_or_initialize_by(path: file_path)
    app_file.update!(
      content: content,
      file_type: determine_file_type(file_path)
    )
    
    # Trigger fast build for this file using Vite
    FastBuildService.new(app).build_file_async(file_path, content) do |result|
      if result[:success]
        # Broadcast HMR update to all connected clients
        broadcast_hmr_update(app, file_path, result[:compiled_content])
      else
        # Send error to the specific client
        transmit({
          type: 'build_error',
          path: file_path,
          error: result[:error]
        })
      end
    end
  end

  # Handle component hot reload requests
  def reload_component(data)
    app = App.find(params[:app_id])
    component_name = data['component']
    
    Rails.logger.info "[AppPreviewChannel] Hot reloading component #{component_name}"
    
    # Get component file
    component_path = "src/components/#{component_name}.tsx"
    app_file = app.app_files.find_by(path: component_path)
    
    return unless app_file
    
    # Fast compile just this component using Vite
    FastBuildService.new(app).transform_file_with_vite(component_path, app_file.content) do |result|
      if result[:success]
        # Send HMR update specifically for this component
        transmit({
          type: 'hmr_component',
          component: component_name,
          code: result[:compiled_content],
          source_map: result[:source_map]
        })
      end
    end
  end

  # Handle preview refresh requests
  def refresh_preview(data)
    app = App.find(params[:app_id])
    
    # Trigger edge deployment update
    EdgePreviewService.new(app).deploy_preview do |result|
      transmit({
        type: 'preview_refreshed',
        url: result[:preview_url],
        deployment_id: result[:deployment_id],
        timestamp: Time.current.to_i
      })
    end
  end

  # Handle PuckEditor save events
  def save_puck_changes(data)
    app = App.find(params[:app_id])
    puck_data = data['puck_data']
    
    Rails.logger.info "[AppPreviewChannel] Saving PuckEditor changes for app #{app.id}"
    
    # Store PuckEditor configuration
    app.update!(
      puck_config: puck_data,
      last_edited_at: Time.current
    )
    
    # Convert Puck data to React components
    PuckToReactService.new(app).convert(puck_data) do |result|
      if result[:success]
        # Update app files with generated components
        result[:files].each do |file_path, content|
          app_file = app.app_files.find_or_initialize_by(path: file_path)
          app_file.update!(content: content)
        end
        
        # Trigger HMR for all updated files
        broadcast_hmr_batch(app, result[:files])
      end
    end
  end

  private

  def broadcast_hmr_update(app, file_path, compiled_content)
    # Broadcast to all connected clients watching this app
    AppPreviewChannel.broadcast_to(app, {
      type: 'hmr_update',
      path: file_path,
      content: compiled_content,
      timestamp: Time.current.to_i,
      hot_reload: true
    })
  end

  def broadcast_hmr_batch(app, files)
    # Broadcast multiple file updates at once
    AppPreviewChannel.broadcast_to(app, {
      type: 'hmr_batch',
      files: files,
      timestamp: Time.current.to_i,
      hot_reload: true
    })
  end

  def determine_file_type(path)
    case File.extname(path)
    when '.tsx', '.jsx'
      'component'
    when '.ts', '.js'
      'script'
    when '.css'
      'style'
    when '.html'
      'markup'
    else
      'other'
    end
  end
end