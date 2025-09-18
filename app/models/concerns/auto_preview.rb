module AutoPreview
  extend ActiveSupport::Concern

  included do
    after_create :create_preview_worker
    after_update :update_preview_if_needed
  end

  private

  def create_preview_worker
    # Create auto-preview worker when app is first created
    UpdatePreviewJob.perform_later(id) if app_files.any?
  end

  def update_preview_if_needed
    # Update preview if files were changed (handled by jobs)
    # This is more of a safety net - main updates happen via jobs
  end
end
