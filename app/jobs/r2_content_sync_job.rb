# Background job for syncing AppFile content to R2 storage
# This moves R2 uploads out of the request cycle for better performance
class R2ContentSyncJob < ApplicationJob
  include ActiveJob::Uniqueness

  queue_as :low_priority  # Use low priority queue for storage operations

  # Prevent duplicate syncs for the same file
  unique :until_executed, lock_ttl: 5.minutes, on_conflict: :log

  # Define uniqueness based on app_file_id
  def lock_key
    app_file_id = arguments.first
    "r2_sync:app_file:#{app_file_id}"
  end

  # Retry up to 3 times with exponential backoff for transient failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    app_file_id = job.arguments.first
    Rails.logger.error "[R2ContentSyncJob] Final failure for AppFile ##{app_file_id}: #{error.message}"

    # Mark the file as having failed R2 sync
    app_file = AppFile.find_by(id: app_file_id)
    app_file&.update_columns(
      r2_sync_status: "failed",
      r2_sync_error: error.message,
      r2_sync_attempted_at: Time.current
    )
  end

  def perform(app_file_id, options = {})
    app_file = AppFile.find(app_file_id)

    Rails.logger.info "[R2ContentSyncJob] Starting R2 sync for AppFile ##{app_file.id} (#{app_file.path})"

    # Skip if already synced to R2
    if app_file.r2_object_key.present?
      Rails.logger.info "[R2ContentSyncJob] AppFile ##{app_file.id} already has R2 key: #{app_file.r2_object_key}"
      return
    end

    # Skip if no content to sync
    content_to_store = app_file.read_attribute(:content)
    if content_to_store.blank?
      Rails.logger.warn "[R2ContentSyncJob] AppFile ##{app_file.id} has no content to sync"
      return
    end

    # Skip small files unless explicitly requested
    if !options[:force] && app_file.size_bytes < 1.kilobyte
      Rails.logger.info "[R2ContentSyncJob] Skipping small file ##{app_file.id} (#{app_file.size_bytes} bytes)"
      return
    end

    # Perform the R2 storage
    service = Storage::R2FileStorageService.new
    result = service.store_file_content(app_file.app_id, app_file.path, content_to_store)

    if result && result[:object_key]
      Rails.logger.info "[R2ContentSyncJob] Successfully stored AppFile ##{app_file.id} in R2: #{result[:object_key]}"

      # Update the file based on storage location strategy
      case app_file.storage_location
      when "r2"
        # Clear database content for R2-only storage
        app_file.update_columns(
          r2_object_key: result[:object_key],
          content: nil,  # Clear database content
          r2_sync_status: "completed",
          r2_sync_completed_at: Time.current
        )
      when "hybrid"
        # Keep database content for hybrid storage
        app_file.update_columns(
          r2_object_key: result[:object_key],
          r2_sync_status: "completed",
          r2_sync_completed_at: Time.current
        )
      else
        # Database-only file shouldn't be here, but handle gracefully
        Rails.logger.warn "[R2ContentSyncJob] Unexpected storage_location for AppFile ##{app_file.id}: #{app_file.storage_location}"
        app_file.update_columns(
          r2_object_key: result[:object_key],
          storage_location: "hybrid",  # Update to hybrid since we now have R2
          r2_sync_status: "completed",
          r2_sync_completed_at: Time.current
        )
      end
    else
      error_msg = "Failed to store in R2"
      Rails.logger.error "[R2ContentSyncJob] #{error_msg} for AppFile ##{app_file.id}"

      # Mark as failed but don't raise - file is still accessible from database
      app_file.update_columns(
        r2_sync_status: "failed",
        r2_sync_error: error_msg,
        r2_sync_attempted_at: Time.current
      )
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[R2ContentSyncJob] AppFile not found: #{e.message}"
    # Don't retry for missing records
  rescue => e
    Rails.logger.error "[R2ContentSyncJob] Error syncing AppFile ##{app_file_id}: #{e.message}"
    Rails.logger.error "[R2ContentSyncJob] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    raise # Re-raise for job retry logic
  end

  # Bulk sync method for multiple files
  def self.sync_app_files(app_id, file_ids = nil)
    query = AppFile.where(app_id: app_id)
    query = query.where(id: file_ids) if file_ids.present?

    # Only sync files that need it
    files_to_sync = query
      .where(r2_object_key: nil)  # Not already in R2
      .where.not(content: nil)     # Has content to sync
      .where("size_bytes >= ?", 1.kilobyte)  # Large enough to benefit from R2

    Rails.logger.info "[R2ContentSyncJob] Queueing #{files_to_sync.count} files for R2 sync"

    files_to_sync.find_each do |file|
      R2ContentSyncJob.perform_later(file.id)
    end
  end

  # Sync all files created after a certain time (useful for catching up)
  def self.sync_recent_files(since: 1.hour.ago)
    files_to_sync = AppFile
      .where("created_at > ?", since)
      .where(r2_object_key: nil)
      .where.not(content: nil)
      .where("size_bytes >= ?", 1.kilobyte)

    Rails.logger.info "[R2ContentSyncJob] Syncing #{files_to_sync.count} recent files to R2"

    files_to_sync.find_each do |file|
      R2ContentSyncJob.perform_later(file.id)
    end
  end
end
