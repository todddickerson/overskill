# Action Cable channel for live preview updates and hot reload
class PreviewChannel < ApplicationCable::Channel
  def subscribed
    app = App.find(params[:app_id])

    # Ensure user has access to this app
    if app.team.users.include?(current_user)
      stream_from "app_preview_#{app.id}"
      stream_for app

      Rails.logger.info "[PreviewChannel] User #{current_user.id} subscribed to preview for app #{app.id}"
    else
      reject
    end
  end

  def unsubscribed
    Rails.logger.info "[PreviewChannel] Unsubscribed from preview channel"
    stop_all_streams
  end

  # Handle file update requests from client
  def update_file(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      file_path = data["file_path"]
      content = data["content"]

      Rails.logger.info "[PreviewChannel] Updating file #{file_path} for app #{app.id}"

      # Update app file in database
      app_file = app.app_files.find_or_initialize_by(path: file_path)
      app_file.content = content
      app_file.save!

      # Update preview environment with new file
      preview_service = Deployment::WfpPreviewService.new(app)
      result = preview_service.update_preview_file(file_path, content)

      # Broadcast file update to all connected clients
      broadcast_to(app, {
        type: "file_updated",
        file_path: file_path,
        content: content,
        timestamp: Time.current,
        success: result[:success]
      })
    end
  end

  # Handle preview reload request
  def reload_preview(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      Rails.logger.info "[PreviewChannel] Reloading preview for app #{app.id}"

      # Trigger preview environment reload
      broadcast_to(app, {
        type: "reload_preview",
        timestamp: Time.current
      })
    end
  end

  # Handle hot module reload request
  def hot_reload_module(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      module_path = data["module_path"]

      Rails.logger.info "[PreviewChannel] Hot reloading module #{module_path} for app #{app.id}"

      # Broadcast HMR update to connected clients
      broadcast_to(app, {
        type: "hot_reload_module",
        module_path: module_path,
        timestamp: Time.current
      })
    end
  end

  # Handle preview environment creation request
  def create_preview_environment(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      Rails.logger.info "[PreviewChannel] Creating preview environment for app #{app.id}"

      # Create preview environment asynchronously
      CreatePreviewEnvironmentJob.perform_async(app.id, current_user.id)

      # Send immediate acknowledgment
      transmit({
        type: "preview_creation_started",
        app_id: app.id,
        message: "Preview environment creation started...",
        timestamp: Time.current
      })
    end
  end

  # Handle file change notifications from file watcher
  def file_changed(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      file_path = data["file_path"]
      change_type = data["change_type"] # 'created', 'modified', 'deleted'

      Rails.logger.info "[PreviewChannel] File #{change_type}: #{file_path} for app #{app.id}"

      # Broadcast file change to connected clients
      broadcast_to(app, {
        type: "file_changed",
        file_path: file_path,
        change_type: change_type,
        timestamp: Time.current
      })
    end
  end

  # Handle preview status updates
  def update_preview_status(data)
    app = App.find(params[:app_id])

    if app.team.users.include?(current_user)
      status = data["status"]

      Rails.logger.info "[PreviewChannel] Preview status update: #{status} for app #{app.id}"

      # Update app preview status
      app.update!(preview_status: status)

      # Broadcast status update
      broadcast_to(app, {
        type: "preview_status_updated",
        status: status,
        timestamp: Time.current
      })
    end
  end
end
