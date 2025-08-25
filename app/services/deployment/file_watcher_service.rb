# Service for watching file changes and triggering hot reload
class Deployment::FileWatcherService
  def initialize(app)
    @app = app
    @watchers = {}
    @running = false
  end
  
  # Start watching files for changes
  def start_watching
    return if @running
    
    Rails.logger.info "[FileWatcher] Starting file watcher for app #{@app.id}"
    
    @running = true
    
    # Watch app files for changes
    watch_app_files
    
    # Start background thread to process changes
    start_change_processor
  end
  
  # Stop watching files
  def stop_watching
    return unless @running
    
    Rails.logger.info "[FileWatcher] Stopping file watcher for app #{@app.id}"
    
    @running = false
    @watchers.each { |_, watcher| watcher&.close }
    @watchers.clear
  end
  
  # Manually trigger file update (for API-driven changes)
  def trigger_file_update(file_path, content)
    Rails.logger.info "[FileWatcher] Manual file update: #{file_path} for app #{@app.id}"
    
    # Update app file in database
    app_file = @app.app_files.find_or_initialize_by(path: file_path)
    app_file.content = content
    app_file.save!
    
    # Queue for preview update
    queue_preview_update(file_path, content, 'modified')
  end
  
  # Watch for specific file types that should trigger hot reload
  def self.watchable_extensions
    %w[.tsx .ts .jsx .js .css .html .json .yml .yaml]
  end
  
  private
  
  def watch_app_files
    # Watch each app file for changes
    @app.app_files.each do |app_file|
      next unless watchable_file?(app_file.path)
      
      create_file_watcher(app_file)
    end
  end
  
  def create_file_watcher(app_file)
    # For file watching, we'll use a polling approach since files are stored in database
    # This creates a lightweight watcher that checks file content periodically
    
    file_path = app_file.path
    last_content = app_file.content
    last_updated = app_file.updated_at
    
    Rails.logger.debug "[FileWatcher] Watching file: #{file_path}"
    
    @watchers[file_path] = {
      app_file: app_file,
      last_content: last_content,
      last_updated: last_updated,
      check_interval: 1.0, # Check every second
      last_checked: Time.current
    }
  end
  
  def start_change_processor
    # Start a background thread to check for file changes
    Thread.new do
      while @running
        begin
          check_for_changes
          sleep(0.5) # Check every 500ms for responsiveness
        rescue => e
          Rails.logger.error "[FileWatcher] Error in change processor: #{e.message}"
          sleep(5) # Wait longer on error
        end
      end
    end
  end
  
  def check_for_changes
    @watchers.each do |file_path, watcher_data|
      next if Time.current - watcher_data[:last_checked] < watcher_data[:check_interval]
      
      watcher_data[:last_checked] = Time.current
      
      # Reload app file to check for changes
      app_file = watcher_data[:app_file]
      app_file.reload
      
      # Check if content or timestamp changed
      if app_file.content != watcher_data[:last_content] ||
         app_file.updated_at > watcher_data[:last_updated]
        
        Rails.logger.info "[FileWatcher] File changed: #{file_path}"
        
        # Update watcher data
        watcher_data[:last_content] = app_file.content
        watcher_data[:last_updated] = app_file.updated_at
        
        # Queue for preview update
        queue_preview_update(file_path, app_file.content, 'modified')
      end
    end
  end
  
  def queue_preview_update(file_path, content, change_type)
    # Update preview environment with new file
    if @app.preview_status == 'ready'
      begin
        preview_service = Deployment::WfpPreviewService.new(@app)
        preview_service.update_preview_file(file_path, content)
        
        # Broadcast file change via ActionCable
        ActionCable.server.broadcast(
          "app_preview_#{@app.id}",
          {
            type: 'file_changed',
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
  
  # Singleton pattern to manage watchers globally
  class << self
    def watchers
      @watchers ||= {}
    end
    
    def start_watching_app(app)
      stop_watching_app(app) if watchers[app.id]
      
      watcher = new(app)
      watcher.start_watching
      watchers[app.id] = watcher
    end
    
    def stop_watching_app(app)
      watcher = watchers.delete(app.id)
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
    
    # Cleanup method for shutting down all watchers
    def stop_all_watchers
      watchers.each { |_, watcher| watcher.stop_watching }
      watchers.clear
    end
  end
end