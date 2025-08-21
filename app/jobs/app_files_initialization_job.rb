# Background job for optimizing app file storage after app generation
# This ONLY handles R2 syncing for storage optimization
# Files are already created and available in the database by AiToolService
# This job runs after generation to move large files to R2 for cost optimization
class AppFilesInitializationJob < ApplicationJob
  include ActiveJob::Uniqueness
  
  queue_as :default  # Use default queue since this is important for app functionality
  
  # Prevent duplicate initialization for the same app
  unique :until_executed, lock_ttl: 10.minutes, on_conflict: :log
  
  # Define uniqueness based on app_id
  def lock_key
    app_id = arguments.first
    "app_files_init:app:#{app_id}"
  end
  
  # Retry up to 3 times with exponential backoff for transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    app_id = job.arguments.first
    Rails.logger.error "[AppFilesInitializationJob] Final failure for App ##{app_id}: #{error.message}"
    
    # Mark the app as having file initialization issues
    app = App.find_by(id: app_id)
    if app
      app.update_columns(
        file_sync_status: 'failed',
        file_sync_error: error.message,
        file_sync_attempted_at: Time.current
      )
      
      # Notify via chat message
      app.app_chat_messages.create!(
        role: "assistant",
        content: "⚠️ File initialization encountered an issue: #{error.message}\n\nThe app may still function, but some files might not be optimally stored. You can continue working with the app.",
        status: "warning"
      )
    end
  end
  
  def perform(app_id, options = {})
    @app = App.find(app_id)
    @options = options
    
    Rails.logger.info "[AppFilesInitializationJob] Starting file initialization for App ##{@app.id}"
    
    # Track metrics
    start_time = Time.current
    files_processed = 0
    files_synced_to_r2 = 0
    errors = []
    
    begin
      # Update app status
      @app.update_columns(
        file_sync_status: 'processing',
        file_sync_started_at: Time.current
      )
      
      # Process files based on initialization type
      if @options[:clone_from_app_id]
        # Clone files from another app (for templates or duplication)
        files_processed, files_synced_to_r2 = clone_files_from_app(@options[:clone_from_app_id])
      elsif @options[:from_template]
        # Initialize from a template
        files_processed, files_synced_to_r2 = initialize_from_template(@options[:template_name])
      else
        # Standard initialization: sync existing files to R2
        files_processed, files_synced_to_r2 = sync_existing_files_to_r2
      end
      
      # Calculate duration
      duration = Time.current - start_time
      
      Rails.logger.info "[AppFilesInitializationJob] Completed initialization for App ##{@app.id}: " \
                       "#{files_processed} files processed, #{files_synced_to_r2} synced to R2 in #{duration.round(2)}s"
      
      # Update app with success status
      @app.update_columns(
        file_sync_status: 'completed',
        file_sync_completed_at: Time.current,
        file_sync_stats: {
          files_processed: files_processed,
          files_synced_to_r2: files_synced_to_r2,
          duration_seconds: duration.round(2),
          errors: errors
        }.to_json
      )
      
      # Broadcast completion if needed
      broadcast_completion if @options[:broadcast]
      
    rescue => e
      Rails.logger.error "[AppFilesInitializationJob] Error for App ##{@app.id}: #{e.message}"
      Rails.logger.error e.backtrace&.first(5)&.join("\n")
      
      # Update app with error status
      @app.update_columns(
        file_sync_status: 'failed',
        file_sync_error: e.message,
        file_sync_attempted_at: Time.current
      )
      
      raise # Re-raise for job retry logic
    end
  end
  
  private
  
  def sync_existing_files_to_r2
    files_processed = 0
    files_synced = 0
    
    # Get all app files that need R2 syncing
    files_to_sync = @app.app_files
      .where(r2_object_key: nil)  # Not already in R2
      .where.not(content: nil)    # Has content to sync
    
    # Determine which files should go to R2 based on size
    files_to_sync.find_each.with_index do |file, index|
      files_processed += 1
      
      # Log progress every 10 files
      if index % 10 == 0
        Rails.logger.info "[AppFilesInitializationJob] Processing file #{index + 1}/#{files_to_sync.count} for App ##{@app.id}"
      end
      
      # Skip small files (< 1KB) unless they're marked for R2 storage
      next if file.size_bytes < 1.kilobyte && file.storage_location != 'r2'
      
      # Sync to R2
      if sync_file_to_r2(file)
        files_synced += 1
      end
    end
    
    [files_processed, files_synced]
  end
  
  def clone_files_from_app(source_app_id)
    source_app = App.find(source_app_id)
    files_processed = 0
    files_synced = 0
    
    Rails.logger.info "[AppFilesInitializationJob] Cloning files from App ##{source_app.id} to App ##{@app.id}"
    
    source_app.app_files.find_each do |source_file|
      files_processed += 1
      
      # Create new file in target app
      new_file = @app.app_files.build(
        path: source_file.path,
        file_type: source_file.file_type,
        content: source_file.content,  # This will fetch from R2 if needed
        storage_location: 'database',  # Start in database, sync to R2 later
        size_bytes: source_file.size_bytes,
        content_hash: source_file.content_hash,
        team_id: @app.team_id
      )
      
      # Save without triggering after_create callbacks
      new_file.save!(validate: false)
      
      # Sync to R2 if appropriate
      if source_file.r2_object_key.present? || new_file.size_bytes >= 1.kilobyte
        if sync_file_to_r2(new_file)
          files_synced += 1
        end
      end
    end
    
    [files_processed, files_synced]
  end
  
  def initialize_from_template(template_name)
    # This would load files from a predefined template
    # For now, just return empty results
    Rails.logger.info "[AppFilesInitializationJob] Template initialization not yet implemented for: #{template_name}"
    [0, 0]
  end
  
  def sync_file_to_r2(file)
    return false if file.content.blank?
    
    service = Storage::R2FileStorageService.new
    result = service.store_file_content(@app.id, file.path, file.content)
    
    if result && result[:object_key]
      # Update file with R2 information
      case file.storage_location
      when 'r2'
        # R2-only: clear database content
        file.update_columns(
          r2_object_key: result[:object_key],
          content: nil
        )
      else
        # Hybrid or database: keep content, add R2 key
        file.update_columns(
          r2_object_key: result[:object_key],
          storage_location: 'hybrid'
        )
      end
      
      Rails.logger.debug "[AppFilesInitializationJob] Synced #{file.path} to R2: #{result[:object_key]}"
      true
    else
      Rails.logger.warn "[AppFilesInitializationJob] Failed to sync #{file.path} to R2"
      false
    end
  rescue => e
    Rails.logger.error "[AppFilesInitializationJob] Error syncing file #{file.id} to R2: #{e.message}"
    false
  end
  
  def broadcast_completion
    # Broadcast to ActionCable if needed
    ActionCable.server.broadcast(
      "app_#{@app.id}_files",
      {
        type: 'files_initialized',
        message: 'App files have been initialized successfully',
        stats: {
          files_processed: @app.file_sync_stats
        }
      }
    )
  rescue => e
    Rails.logger.warn "[AppFilesInitializationJob] Failed to broadcast: #{e.message}"
  end
  
  # Class method to queue initialization for all recent apps
  def self.initialize_recent_apps(since: 1.hour.ago)
    apps_to_process = App
      .where('created_at > ?', since)
      .where(file_sync_status: [nil, 'pending'])
    
    Rails.logger.info "[AppFilesInitializationJob] Queueing initialization for #{apps_to_process.count} recent apps"
    
    apps_to_process.find_each do |app|
      AppFilesInitializationJob.perform_later(app.id)
    end
  end
end