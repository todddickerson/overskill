class AppVersion < ApplicationRecord
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :team
  belongs_to :app
  belongs_to :user, optional: true
  # 🚅 add belongs_to associations above.

  has_many :app_chat_messages, dependent: :nullify
  has_many :app_version_files, dependent: :destroy
  # 🚅 add has_many associations above.

  # 🚅 add has_one associations above.

  # Handle R2 storage after creation for new records
  after_create :handle_r2_storage_after_create

  # Storage strategy tracking
  enum :storage_strategy, {database: "database", r2: "r2", hybrid: "hybrid"}

  # Scopes for different storage strategies
  scope :with_database_snapshots, -> { where(storage_strategy: ["database", "hybrid"]) }
  scope :with_r2_snapshots, -> { where(storage_strategy: ["r2", "hybrid"]) }
  scope :migrable_to_r2, -> { where(storage_strategy: "database").where("files_snapshot IS NOT NULL") }

  # 🚅 add scopes above.

  validates :app, scope: true
  validates :user, scope: true, allow_blank: true
  validates :version_number, presence: true
  validates :storage_strategy, inclusion: {in: %w[database r2 hybrid]}
  validates :r2_snapshot_key, uniqueness: true, allow_blank: true
  validate :snapshot_data_present
  # 🚅 add validations above.

  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  def valid_apps
    team.apps
  end

  def valid_users
    team.users
  end

  # Generate a display name based on changes made
  def generate_display_name!
    return if display_name.present?

    # Generate AI-powered summary of changes
    files_summary = generate_files_summary
    prompt = build_display_name_prompt(files_summary)

    generated_name = begin
      # Use OpenRouter for cost-effective text generation
      client = Ai::OpenRouterClient.new
      response = client.chat(
        [{role: "user", content: prompt}],
        max_tokens: 50,
        temperature: 0.3
      )
      # Extract content from response
      response.dig("choices", 0, "message", "content") || generate_simple_display_name
    rescue => e
      Rails.logger.error "Failed to generate display name: #{e.message}"
      # Fallback to simple name based on file changes
      generate_simple_display_name
    end

    update!(display_name: generated_name.strip)
    generated_name
  end

  def formatted_display_name
    display_name.presence || generate_display_name!
  end

  def has_files_data?
    files_snapshot.present? || app_version_files.exists?
  end

  def can_be_restored?
    has_files_data? || app.app_versions.where("files_snapshot IS NOT NULL").exists?
  end

  # Version snapshot management with R2 support
  def files_snapshot
    case storage_strategy
    when "database", "hybrid"
      super
    when "r2"
      fetch_snapshot_from_r2
    else
      super || fetch_snapshot_from_r2
    end
  end

  def files_snapshot=(new_snapshot)
    return if new_snapshot.blank?

    strategy = determine_snapshot_storage_strategy(new_snapshot)

    case strategy
    when :database_only
      super
      self.storage_strategy = "database"
      self.r2_snapshot_key = nil
    when :r2_only
      store_snapshot_in_r2(new_snapshot)
      super(nil) # Clear database snapshot
      self.storage_strategy = "r2"
    when :hybrid
      super # Store in database
      store_snapshot_in_r2(new_snapshot) # Also store in R2
      self.storage_strategy = "hybrid"
    end
  end

  # Migration methods for version snapshots
  def migrate_snapshot_to_r2!
    return false if files_snapshot.blank? || storage_strategy == "r2"

    begin
      original_snapshot = read_attribute(:files_snapshot) || files_snapshot
      result = store_snapshot_in_r2(original_snapshot)

      # Update to hybrid first (safety)
      update!(
        storage_strategy: "hybrid",
        r2_snapshot_key: result[:object_key]
      )

      Rails.logger.info "Migrated AppVersion #{id} snapshot to R2"
      true
    rescue => e
      Rails.logger.error "Failed to migrate AppVersion #{id} snapshot to R2: #{e.message}"
      false
    end
  end

  def migrate_snapshot_to_r2_only!
    return false unless migrate_snapshot_to_r2! || storage_strategy == "hybrid"

    # Verify R2 content matches database
    if verify_r2_snapshot
      update_column(:storage_strategy, "r2")
      update_column(:files_snapshot, nil) # Clear database snapshot
      Rails.logger.info "Migrated AppVersion #{id} snapshot to R2-only"
      true
    else
      Rails.logger.error "R2 snapshot verification failed for AppVersion #{id}"
      false
    end
  end

  def rollback_snapshot_to_database!
    return false if storage_strategy == "database" || r2_snapshot_key.blank?

    begin
      r2_snapshot = fetch_snapshot_from_r2
      return false if r2_snapshot.blank?

      # Store snapshot back in database
      update_columns(
        files_snapshot: r2_snapshot,
        storage_strategy: "database",
        r2_snapshot_key: nil
      )

      Rails.logger.info "Rolled back AppVersion #{id} snapshot to database storage"
      true
    rescue => e
      Rails.logger.error "Failed to rollback AppVersion #{id} snapshot to database: #{e.message}"
      false
    end
  end

  # Utility methods
  def snapshot_size_bytes
    snapshot_content = files_snapshot
    return 0 if snapshot_content.blank?
    snapshot_content.bytesize
  end

  def snapshot_available?
    case storage_strategy
    when "database", "hybrid"
      read_attribute(:files_snapshot).present?
    when "r2"
      r2_snapshot_key.present?
    else
      read_attribute(:files_snapshot).present? || r2_snapshot_key.present?
    end
  end

  def formatted_file_changes
    app_version_files.includes(:app_file).map do |version_file|
      file_name = extract_file_name(version_file.app_file.path)
      file_type = extract_file_type(version_file.app_file.path)
      action_label = format_action_label(version_file.action)

      {
        action: version_file.action,
        action_label: action_label,
        file_name: file_name,
        file_type: file_type,
        full_path: version_file.app_file.path
      }
    end
  end

  private

  def fetch_snapshot_from_r2
    return nil if r2_snapshot_key.blank?

    Rails.cache.fetch("r2_snapshot_#{r2_snapshot_key.tr("/", "_")}", expires_in: 15.minutes) do
      Storage::R2FileStorageService.new.retrieve_file_content(r2_snapshot_key)
    end
  rescue Storage::R2FileStorageService::R2DownloadError => e
    Rails.logger.error "Failed to fetch R2 snapshot for #{r2_snapshot_key}: #{e.message}"
    # If this is a hybrid version, try to fallback to database snapshot
    if storage_strategy == "hybrid"
      Rails.logger.info "Falling back to database snapshot for AppVersion #{id}"
      read_attribute(:files_snapshot)
    end
  end

  def store_snapshot_in_r2(snapshot_content)
    # Can't store in R2 without an ID (new records)
    return nil unless persisted?

    service = Storage::R2FileStorageService.new

    # Parse JSON if it's a string, to ensure proper formatting
    parsed_snapshot = snapshot_content.is_a?(String) ? JSON.parse(snapshot_content) : snapshot_content
    result = service.store_version_snapshot(app.id, id, parsed_snapshot)

    self.r2_snapshot_key = result[:object_key]
    result
  end

  def verify_r2_snapshot
    return false if r2_snapshot_key.blank?

    begin
      r2_snapshot = fetch_snapshot_from_r2
      db_snapshot = read_attribute(:files_snapshot)

      return false if r2_snapshot.blank? || db_snapshot.blank?

      # Normalize JSON for comparison
      r2_normalized = JSON.parse(r2_snapshot.is_a?(String) ? r2_snapshot : r2_snapshot.to_json)
      db_normalized = JSON.parse(db_snapshot.is_a?(String) ? db_snapshot : db_snapshot.to_json)

      r2_normalized == db_normalized
    rescue => e
      Rails.logger.error "Snapshot verification failed for AppVersion #{id}: #{e.message}"
      false
    end
  end

  def determine_snapshot_storage_strategy(snapshot_content)
    size = snapshot_content.bytesize

    # Check if feature flag allows R2 migration
    return :database_only unless r2_storage_enabled?

    case size
    when 0..10.kilobytes
      :database_only # Keep smaller snapshots in database
    when 10.kilobytes..100.kilobytes
      :hybrid # Safety during migration
    else
      :r2_only # Large snapshots go to R2
    end
  end

  def r2_storage_enabled?
    # Feature flag check - same as AppFile
    return false unless ENV["CLOUDFLARE_R2_BUCKET_DB_FILES"].present?
    app.try(:r2_storage_enabled?) != false
  end

  def snapshot_data_present
    # Skip validation for new records - R2 storage happens after_create
    return if new_record?

    # For existing records with non-database storage, ensure data is present somewhere
    if storage_strategy != "database" && read_attribute(:files_snapshot).blank? && r2_snapshot_key.blank?
      errors.add(:base, "Either files_snapshot or R2 snapshot key must be present for non-database storage")
    end
  end

  def generate_files_summary
    changes_by_action = app_version_files.includes(:app_file).group_by(&:action)

    summary_parts = []

    changes_by_action.each do |action, files|
      file_names = files.map { |f| extract_file_name(f.app_file.path) }
      case action
      when "created"
        summary_parts << "created #{file_names.join(", ")}"
      when "updated"
        summary_parts << "updated #{file_names.join(", ")}"
      when "deleted"
        summary_parts << "deleted #{file_names.join(", ")}"
      when "restored"
        summary_parts << "restored #{file_names.join(", ")}"
      end
    end

    summary_parts.join(", ")
  end

  def build_display_name_prompt(files_summary)
    changelog_context = changelog.present? ? "Context: #{changelog.first(200)}" : ""

    <<~PROMPT
      Generate a concise 2-4 word summary of these code changes:
      
      Files changed: #{files_summary}
      #{changelog_context}
      
      Examples of good summaries:
      - "Fix login errors"
      - "Add user dashboard"
      - "Update styling system"
      - "Complete checkout flow"
      - "Refactor data models"
      
      Summary:
    PROMPT
  end

  def generate_simple_display_name
    file_count = app_version_files.count

    if file_count == 1
      file = app_version_files.first
      file_name = extract_file_name(file.app_file.path)
      action = format_action_label(file.action)
      "#{action} #{file_name}"
    elsif file_count <= 3
      "Update #{file_count} files"
    else
      "Major code changes"
    end
  end

  def extract_file_name(path)
    # Handle empty or just filename cases
    return "Root file" if path.blank? || path == "."

    # Extract meaningful file name or component name
    file_name = File.basename(path, File.extname(path))

    # Handle empty file names (like hidden files or just extensions)
    if file_name.blank? || file_name == "."
      # Use the full path or directory name
      return File.basename(path) if File.basename(path) != "."
      return "Config file"
    end

    # Convert common patterns to readable names
    case file_name.downcase
    when "index", "main", "app"
      parent_dir = File.basename(File.dirname(path))
      if parent_dir == "." || parent_dir.blank?
        file_name.capitalize
      else
        parent_dir.capitalize
      end
    when "style", "styles"
      "Styles"
    when "component", "components"
      "Components"
    when "package"
      "Package config"
    when "readme"
      "Documentation"
    else
      # Convert camelCase or snake_case to Title Case
      cleaned_name = file_name.gsub(/[_-]/, " ").split.map(&:capitalize).join(" ")
      cleaned_name.presence || File.basename(path)
    end
  end

  def extract_file_type(path)
    ext = File.extname(path).downcase

    case ext
    when ".html", ".htm"
      "page"
    when ".js", ".jsx", ".ts", ".tsx"
      "component"
    when ".css", ".scss", ".sass"
      "styles"
    when ".json"
      "config"
    when ".md"
      "documentation"
    when ".vue"
      "component"
    when ".py"
      "script"
    when ".rb"
      "model"
    else
      "file"
    end
  end

  def format_action_label(action)
    case action
    when "created"
      "Creating"
    when "updated"
      "Editing"
    when "deleted"
      "Removing"
    when "restored"
      "Restoring"
    else
      "Modifying"
    end
  end

  def r2_storage_enabled?
    # Feature flag check - must have R2 bucket configured
    return false unless ENV["CLOUDFLARE_R2_BUCKET_DB_FILES"].present?

    # Check if app has opted in
    app.try(:r2_storage_enabled?) != false
  end

  def handle_r2_storage_after_create
    # Only process if we attempted R2 storage during creation
    return unless storage_strategy.in?(["r2", "hybrid"])
    return if r2_snapshot_key.present? # Already stored

    # Now that we have an ID, store in R2
    snapshot_content = read_attribute(:files_snapshot)
    return if snapshot_content.blank?

    begin
      result = store_snapshot_in_r2(snapshot_content)
      if result && result[:object_key]
        update_column(:r2_snapshot_key, result[:object_key])
        Rails.logger.info "AppVersion #{id}: Stored snapshot in R2 after creation"
      end
    rescue => e
      Rails.logger.error "AppVersion #{id}: Failed to store snapshot in R2: #{e.message}"
      # Don't fail the creation if R2 storage fails
    end
  end

  # 🚅 add methods above.
end
