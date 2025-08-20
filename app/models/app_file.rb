class AppFile < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  # 🚅 add belongs_to associations above.

  has_many :app_version_files, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # Storage location tracking
  enum :storage_location, { database: 'database', r2: 'r2', hybrid: 'hybrid' }
  
  # Scopes for different storage strategies
  scope :in_database, -> { where(storage_location: ['database', 'hybrid']) }
  scope :in_r2, -> { where(storage_location: ['r2', 'hybrid']) }
  scope :database_only, -> { where(storage_location: 'database') }
  scope :r2_only, -> { where(storage_location: 'r2') }
  scope :migrable_to_r2, -> { where(storage_location: 'database').where('size_bytes > ?', 1.kilobyte) }
  
  # 🚅 add scopes above.

  validates :app, scope: true
  validates :path, presence: true
  validate :content_or_r2_key_present
  validates :storage_location, inclusion: { in: %w[database r2 hybrid] }
  validates :r2_object_key, uniqueness: true, allow_blank: true
  # 🚅 add validations above.

  before_save :update_content_hash, if: :content_changed?
  before_save :update_size_bytes, if: :content_changed?
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  # Content management with R2 fallback
  def content
    case storage_location
    when 'database', 'hybrid'
      super # Use database content
    when 'r2'
      fetch_from_r2
    else
      super || fetch_from_r2 # Fallback strategy
    end
  end
  
  def content=(new_content)
    return if new_content.blank?
    
    strategy = determine_storage_strategy(new_content)
    
    case strategy
    when :database_only
      super(new_content)
      self.storage_location = 'database'
      self.r2_object_key = nil
    when :r2_only  
      store_in_r2(new_content)
      super(nil) # Clear database content
      self.storage_location = 'r2'
    when :hybrid
      super(new_content) # Store in database
      store_in_r2(new_content) # Also store in R2
      self.storage_location = 'hybrid'
    end
    
    self.content_hash = Digest::SHA256.hexdigest(new_content)
    self.size_bytes = new_content.bytesize
  end
  
  # Migration methods
  def migrate_to_r2!
    return false if content.blank? || storage_location == 'r2'
    
    begin
      original_content = read_attribute(:content) || content
      result = store_in_r2(original_content)
      
      # Update to hybrid first (safety)
      update!(
        storage_location: 'hybrid',
        r2_object_key: result[:object_key],
        content_hash: result[:checksum]
      )
      
      Rails.logger.info "Migrated AppFile #{id} (#{path}) to R2"
      true
    rescue => e
      Rails.logger.error "Failed to migrate AppFile #{id} to R2: #{e.message}"
      false
    end
  end
  
  def migrate_to_r2_only!
    return false unless migrate_to_r2! || storage_location == 'hybrid'
    
    # Verify R2 content matches database
    if verify_r2_content
      update_column(:storage_location, 'r2')
      update_column(:content, nil) # Clear database content
      Rails.logger.info "Migrated AppFile #{id} (#{path}) to R2-only"
      true
    else
      Rails.logger.error "R2 content verification failed for AppFile #{id}"
      false
    end
  end
  
  def rollback_to_database!
    return false if storage_location == 'database' || r2_object_key.blank?
    
    begin
      r2_content = fetch_from_r2
      return false if r2_content.blank?
      
      # Store content back in database
      update_columns(
        content: r2_content,
        storage_location: 'database',
        r2_object_key: nil,
        content_hash: Digest::SHA256.hexdigest(r2_content)
      )
      
      Rails.logger.info "Rolled back AppFile #{id} (#{path}) to database storage"
      true
    rescue => e
      Rails.logger.error "Failed to rollback AppFile #{id} to database: #{e.message}"
      false
    end
  end
  
  # Utility methods
  def storage_size_category
    return :unknown if size_bytes.blank?
    
    case size_bytes
    when 0..1.kilobyte
      :small
    when 1.kilobyte..10.kilobytes
      :medium  
    else
      :large
    end
  end
  
  def should_be_in_r2?
    storage_size_category.in?([:medium, :large])
  end
  
  def content_available?
    case storage_location
    when 'database', 'hybrid'
      read_attribute(:content).present?
    when 'r2'
      r2_object_key.present?
    else
      read_attribute(:content).present? || r2_object_key.present?
    end
  end
  
  def r2_cdn_url
    return nil if r2_object_key.blank?
    
    if ENV['CLOUDFLARE_R2_CDN_DOMAIN'].present?
      "https://#{ENV['CLOUDFLARE_R2_CDN_DOMAIN']}/#{r2_object_key}"
    else
      account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      bucket_name = ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'] || 'overskill-dev'
      "https://#{bucket_name}.#{account_id}.r2.cloudflarestorage.com/#{r2_object_key}"
    end
  end

  # 🚅 add methods above.

  private
  
  def determine_storage_strategy(new_content)
    size = new_content.bytesize
    
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
  
  def fetch_from_r2
    return nil if r2_object_key.blank?
    
    Rails.cache.fetch("r2_content_#{r2_object_key.gsub('/', '_')}", expires_in: 10.minutes) do
      Storage::R2FileStorageService.new.retrieve_file_content(r2_object_key)
    end
  rescue Storage::R2FileStorageService::R2DownloadError => e
    Rails.logger.error "Failed to fetch R2 content for #{r2_object_key}: #{e.message}"
    # If this is a hybrid file, try to fallback to database content
    if storage_location == 'hybrid'
      Rails.logger.info "Falling back to database content for AppFile #{id}"
      read_attribute(:content)
    else
      nil
    end
  end
  
  def store_in_r2(content)
    service = Storage::R2FileStorageService.new
    result = service.store_file_content(app.id, path, content)
    self.r2_object_key = result[:object_key]
    result
  end
  
  def verify_r2_content
    return false if r2_object_key.blank?
    
    begin
      r2_content = fetch_from_r2
      db_content = read_attribute(:content)
      
      return false if r2_content.blank? || db_content.blank?
      
      r2_hash = Digest::SHA256.hexdigest(r2_content)
      db_hash = Digest::SHA256.hexdigest(db_content)
      
      r2_hash == db_hash
    rescue => e
      Rails.logger.error "Content verification failed for AppFile #{id}: #{e.message}"
      false
    end
  end
  
  def r2_storage_enabled?
    # Feature flag check - can be controlled globally or per-app
    return false unless ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'].present?
    
    # Check app-level setting if exists
    app.try(:r2_storage_enabled?) != false
  end
  
  def content_or_r2_key_present
    if read_attribute(:content).blank? && r2_object_key.blank?
      errors.add(:base, "Either content or R2 object key must be present")
    end
  end
  
  def update_content_hash
    return unless content_changed? && content.present?
    self.content_hash = Digest::SHA256.hexdigest(content)
  end
  
  def update_size_bytes
    return unless content_changed?
    self.size_bytes = content.present? ? content.bytesize : 0
  end
end
