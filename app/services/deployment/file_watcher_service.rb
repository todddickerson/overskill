# Service for watching file changes and triggering hot reload
# Now uses ActiveRecord callbacks instead of inefficient polling
class Deployment::FileWatcherService
  def initialize(app)
    @app = app
    @active = false
  end

  # Start watching files for changes (callback-based, no polling)
  def start_watching
    return if @active

    Rails.logger.info "[FileWatcher] Starting callback-based file watcher for app #{@app.id}"
    @active = true

    # Store the watcher in class-level registry
    self.class.register_watcher(@app.id, self)
  end

  # Stop watching files
  def stop_watching
    return unless @active

    Rails.logger.info "[FileWatcher] Stopping file watcher for app #{@app.id}"
    @active = false

    # Remove from class-level registry
    self.class.unregister_watcher(@app.id)
  end

  # Manually trigger file update (for API-driven changes)
  def trigger_file_update(file_path, content)
    Rails.logger.info "[FileWatcher] Manual file update: #{file_path} for app #{@app.id}"

    # Update app file in database
    app_file = @app.app_files.find_or_initialize_by(path: file_path)
    app_file.content = content
    app_file.save!
    # Note: AppFile.after_update_commit will handle the preview update
  end

  # Called by AppFile callback when file changes
  def handle_file_change(app_file, change_type = "modified")
    return unless @active
    return unless watchable_file?(app_file.path)

    Rails.logger.info "[FileWatcher] File changed via callback: #{app_file.path} for app #{@app.id}"
    queue_preview_update(app_file.path, app_file.content, change_type)
  end

  # Watch for specific file types that should trigger hot reload
  def self.watchable_extensions
    %w[.tsx .ts .jsx .js .css .html .json .yml .yaml]
  end

  private

  def queue_preview_update(file_path, content, change_type)
    # Update preview environment with new file
    if @app.preview_status == "ready"
      begin
        preview_service = Deployment::WfpPreviewService.new(@app)
        preview_service.update_preview_file(file_path, content)

        # Broadcast file change via ActionCable
        ActionCable.server.broadcast(
          "app_preview_#{@app.id}",
          {
            type: "file_changed",
            file_path: file_path,
            change_type: change_type,
            content: content,
            timestamp: Time.current,
            app_id: @app.id
          }
        )

        Rails.logger.info "[FileWatcher] Preview updated for file: #{file_path}"
      rescue => e
        Rails.logger.error "[FileWatcher] Failed to update preview for #{file_path}: #{e.message}"
      end
    else
      Rails.logger.warn "[FileWatcher] Skipping preview update - preview not ready (status: #{@app.preview_status})"
    end
  end

  def watchable_file?(file_path)
    extension = File.extname(file_path.downcase)
    self.class.watchable_extensions.include?(extension)
  end

  # Callback-based registry to manage watchers globally
  class << self
    def watchers
      @watchers ||= {}
    end

    def register_watcher(app_id, watcher)
      watchers[app_id] = watcher
    end

    def unregister_watcher(app_id)
      watchers.delete(app_id)
    end

    def start_watching_app(app)
      stop_watching_app(app) if watchers[app.id]

      watcher = new(app)
      watcher.start_watching
    end

    def stop_watching_app(app)
      watcher = watchers[app.id]
      watcher&.stop_watching
    end

    def get_watcher(app)
      watchers[app.id]
    end

    def trigger_file_update(app, file_path, content)
      watcher = watchers[app.id]
      if watcher
        watcher.trigger_file_update(file_path, content)
      else
        Rails.logger.warn "[FileWatcher] No watcher found for app #{app.id}"
      end
    end

    # Notify all relevant watchers when a file changes (called by AppFile callback)
    def notify_file_change(app_file, change_type = "modified")
      watcher = watchers[app_file.app_id]
      watcher&.handle_file_change(app_file, change_type)
    end

    # Cleanup method for shutting down all watchers
    def stop_all_watchers
      watchers.each { |_, watcher| watcher.stop_watching }
      watchers.clear
    end
  end
end
