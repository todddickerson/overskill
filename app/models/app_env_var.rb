class AppEnvVar < ApplicationRecord
  include Records::Base
  # 🚅 add concerns above.

  # 🚅 add attribute accessors above.

  belongs_to :app
  # 🚅 add belongs_to associations above.

  # 🚅 add has_many associations above.

  has_one :team, through: :app
  # 🚅 add has_one associations above.

  # Scopes
  scope :user_defined, -> { where(is_system: false) }
  scope :system_defined, -> { where(is_system: true) }
  scope :secrets, -> { where(is_secret: true) }
  scope :public_vars, -> { where(is_secret: false) }
  # 🚅 add scopes above.

  # Validations
  validates :key, presence: true, uniqueness: {scope: :app_id}
  validates :value, presence: true
  validates :key, format: {
    with: /\A[A-Z][A-Z0-9_]*\z/,
    message: "must be uppercase letters, numbers, and underscores only (e.g., API_KEY)"
  }
  # 🚅 add validations above.

  # Callbacks
  before_save :encrypt_secret_values
  after_commit :sync_to_cloudflare, if: :saved_change_to_value?
  # 🚅 add callbacks above.

  # 🚅 add delegations above.

  # Class methods
  def self.system_defaults
    {
      "SUPABASE_URL" => {value: ENV["SUPABASE_URL"], description: "Supabase database URL", is_secret: false},
      "SUPABASE_ANON_KEY" => {value: ENV["SUPABASE_ANON_KEY"], description: "Supabase anonymous key", is_secret: true},
      "APP_ID" => {value: nil, description: "Unique app identifier", is_secret: false},
      "OWNER_ID" => {value: nil, description: "App owner ID", is_secret: false},
      "ENVIRONMENT" => {value: "production", description: "Deployment environment", is_secret: false}
    }
  end

  def self.create_defaults_for_app(app)
    system_defaults.each do |key, config|
      value = config[:value]

      # Set app-specific values
      value = app.id.to_s if key == "APP_ID"
      value = app.team.id.to_s if key == "OWNER_ID"

      next if value.blank? && key != "ENVIRONMENT"

      app.app_env_vars.find_or_create_by(key: key) do |env_var|
        env_var.value = value
        env_var.description = config[:description]
        env_var.is_secret = config[:is_secret]
        env_var.is_system = true
      end
    end
  end

  # Instance methods
  def display_value
    is_secret? ? masked_value : value
  end

  def masked_value
    return "" if value.blank?
    if value.length <= 8
      "****"
    else
      "#{value[0..3]}...#{value[-4..]}"
    end
  end

  def to_cloudflare_format
    {
      name: key,
      value: value,
      type: is_secret? ? "secret_text" : "plain_text"
    }
  end

  def available_for_ai?
    # Make env vars available to AI for code generation
    !is_secret? || key.include?("PUBLIC")
  end

  private

  def encrypt_secret_values
    # In production, use Rails encrypted attributes
    # For now, we'll store as-is but mark as secret
    # TODO: Implement proper encryption
  end

  def sync_to_cloudflare
    # Queue job to update Cloudflare Worker environment variables
    UpdateCloudflareEnvVarsJob.perform_later(app_id) if app.preview_url.present?
  rescue => e
    Rails.logger.error "Failed to queue Cloudflare env var sync: #{e.message}"
  end
  # 🚅 add methods above.
end
