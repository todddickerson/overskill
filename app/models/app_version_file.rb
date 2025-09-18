class AppVersionFile < ApplicationRecord
  belongs_to :app_version
  belongs_to :app_file

  validate :content_or_r2_key_present
  validates :action, presence: true
  validates :r2_content_key, uniqueness: true, allow_blank: true

  # Actions: created, updated, deleted, restored
  enum :action, {
    created: "create",
    updated: "update",
    deleted: "delete",
    restored: "restored"
  }

  # Scopes for different storage strategies
  scope :in_database, -> { where("content IS NOT NULL") }
  scope :in_r2, -> { where("r2_content_key IS NOT NULL") }
  scope :hybrid, -> { where("content IS NOT NULL AND r2_content_key IS NOT NULL") }
  scope :migrable_to_r2, -> { where("content IS NOT NULL AND r2_content_key IS NULL AND LENGTH(content) > ?", 1.kilobyte) }

  # Content management with R2 support
  def content
    if r2_content_key.present?
      # Try R2 first if available
      fetch_from_r2 || super
    else
      super
    end
  end

  def content=(new_content)
    # AppVersionFiles are historical records - always store in database
    # R2 storage is not appropriate for version tracking
    super
    self.r2_content_key = nil
  end

  # Migration methods
  def migrate_to_r2!
    return false if content.blank? || r2_content_key.present?

    begin
      original_content = read_attribute(:content) || content
      result = store_in_r2(original_content)

      # Keep database content initially (hybrid mode)
      update!(r2_content_key: result[:object_key])

      Rails.logger.info "Migrated AppVersionFile #{id} to R2"
      true
    rescue => e
      Rails.logger.error "Failed to migrate AppVersionFile #{id} to R2: #{e.message}"
      false
    end
  end

  def migrate_to_r2_only!
    return false unless migrate_to_r2! || r2_content_key.present?

    # Verify R2 content matches database
    if verify_r2_content
      update_column(:content, nil) # Clear database content
      Rails.logger.info "Migrated AppVersionFile #{id} to R2-only"
      true
    else
      Rails.logger.error "R2 content verification failed for AppVersionFile #{id}"
      false
    end
  end

  def rollback_to_database!
    return false if r2_content_key.blank?

    begin
      r2_content = fetch_from_r2
      return false if r2_content.blank?

      # Store content back in database
      update_columns(
        content: r2_content,
        r2_content_key: nil
      )

      Rails.logger.info "Rolled back AppVersionFile #{id} to database storage"
      true
    rescue => e
      Rails.logger.error "Failed to rollback AppVersionFile #{id} to database: #{e.message}"
      false
    end
  end

  # Utility methods
  def content_size_bytes
    content_data = content
    return 0 if content_data.blank?
    content_data.bytesize
  end

  def content_available?
    read_attribute(:content).present? || r2_content_key.present?
  end

  def storage_location
    if read_attribute(:content).present? && r2_content_key.present?
      "hybrid"
    elsif r2_content_key.present?
      "r2"
    elsif read_attribute(:content).present?
      "database"
    else
      "none"
    end
  end

  private

  def fetch_from_r2
    return nil if r2_content_key.blank?

    Rails.cache.fetch("r2_version_file_#{r2_content_key.tr("/", "_")}", expires_in: 10.minutes) do
      Storage::R2FileStorageService.new.retrieve_file_content(r2_content_key)
    end
  rescue Storage::R2FileStorageService::R2DownloadError => e
    Rails.logger.error "Failed to fetch R2 version file content for #{r2_content_key}: #{e.message}"
    nil
  end

  def store_in_r2(content_data)
    service = Storage::R2FileStorageService.new
    result = service.store_version_file_content(
      app_version.app.id,
      app_version.id,
      app_file.path,
      content_data
    )
    self.r2_content_key = result[:object_key]
    result
  end

  def verify_r2_content
    return false if r2_content_key.blank?

    begin
      r2_content = fetch_from_r2
      db_content = read_attribute(:content)

      return false if r2_content.blank? || db_content.blank?

      r2_hash = Digest::SHA256.hexdigest(r2_content)
      db_hash = Digest::SHA256.hexdigest(db_content)

      r2_hash == db_hash
    rescue => e
      Rails.logger.error "Content verification failed for AppVersionFile #{id}: #{e.message}"
      false
    end
  end

  def determine_storage_strategy(content_data)
    size = content_data.bytesize

    # Check if feature flag allows R2 migration
    return :database_only unless r2_storage_enabled?

    case size
    when 0..1.kilobyte
      :database_only
    when 1.kilobyte..10.kilobytes
      :hybrid # Safety during migration
    else
      :r2_only
    end
  end

  def r2_storage_enabled?
    # Feature flag check - same as AppFile
    return false unless ENV["CLOUDFLARE_R2_BUCKET_DB_FILES"].present?
    # Check if app_version and app exist before accessing
    return false unless app_version&.app
    app_version.app.try(:r2_storage_enabled?) != false
  end

  def content_or_r2_key_present
    if read_attribute(:content).blank? && r2_content_key.blank?
      errors.add(:base, "Either content or R2 content key must be present")
    end
  end
end
