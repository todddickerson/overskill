class CleanupExportJob < ApplicationJob
  queue_as :low

  def perform(export_path)
    Rails.logger.info "Cleaning up export at: #{export_path}"

    if File.exist?(export_path)
      FileUtils.rm_rf(export_path)
      Rails.logger.info "Successfully removed export directory: #{export_path}"
    else
      Rails.logger.info "Export directory already removed: #{export_path}"
    end
  rescue => e
    Rails.logger.error "Failed to cleanup export: #{e.message}"
    # Don't retry - old exports aren't critical
  end
end
