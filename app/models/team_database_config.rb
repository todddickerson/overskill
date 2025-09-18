class TeamDatabaseConfig < ApplicationRecord
  # This model allows teams to configure their own Supabase instance
  # instead of using our managed one - a key advantage over Base44

  belongs_to :team

  # Encryption for sensitive credentials
  encrypts :supabase_service_key
  encrypts :supabase_anon_key

  # Validations
  validates :team, presence: true, uniqueness: true
  validates :database_mode, presence: true, inclusion: {in: %w[managed custom hybrid]}

  # Custom Supabase fields
  validates :supabase_url, presence: true, if: :uses_custom_supabase?
  validates :supabase_service_key, presence: true, if: :uses_custom_supabase?
  validates :supabase_anon_key, presence: true, if: :uses_custom_supabase?

  # Callbacks
  before_validation :set_defaults
  after_update :sync_apps_configuration, if: :saved_change_to_database_mode?

  # Scopes
  scope :managed, -> { where(database_mode: "managed") }
  scope :custom, -> { where(database_mode: "custom") }
  scope :hybrid, -> { where(database_mode: "hybrid") }

  def uses_custom_supabase?
    database_mode.in?(["custom", "hybrid"])
  end

  def uses_managed_supabase?
    database_mode.in?(["managed", "hybrid"])
  end

  def supabase_config_for_app(app)
    # Determine which Supabase instance to use for a specific app
    case database_mode
    when "managed"
      # Use OverSkill's managed Supabase
      {
        url: ENV["SUPABASE_URL"],
        service_key: ENV["SUPABASE_SERVICE_KEY"],
        anon_key: ENV["SUPABASE_ANON_KEY"],
        mode: "managed"
      }
    when "custom"
      # Use team's own Supabase
      {
        url: supabase_url,
        service_key: supabase_service_key,
        anon_key: supabase_anon_key,
        mode: "custom"
      }
    when "hybrid"
      # Let each app decide (useful for migration)
      if app.use_custom_database?
        {
          url: supabase_url,
          service_key: supabase_service_key,
          anon_key: supabase_anon_key,
          mode: "custom"
        }
      else
        {
          url: ENV["SUPABASE_URL"],
          service_key: ENV["SUPABASE_SERVICE_KEY"],
          anon_key: ENV["SUPABASE_ANON_KEY"],
          mode: "managed"
        }
      end
    end
  end

  def test_connection
    # Test if the custom Supabase credentials work
    return {success: true, message: "Using managed database"} unless uses_custom_supabase?

    begin
      require "net/http"
      uri = URI("#{supabase_url}/rest/v1/")

      request = Net::HTTP::Get.new(uri)
      request["apikey"] = supabase_anon_key
      request["Authorization"] = "Bearer #{supabase_service_key}"

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(request)
      end

      if response.code == "200"
        {success: true, message: "Connection successful"}
      else
        {success: false, message: "Connection failed: #{response.code} #{response.message}"}
      end
    rescue => e
      {success: false, message: "Connection error: #{e.message}"}
    end
  end

  private

  def set_defaults
    self.database_mode ||= "managed"
    self.migration_status ||= "not_started" if database_mode == "hybrid"
  end

  def sync_apps_configuration
    # Queue job to update all apps when database mode changes
    TeamDatabaseSyncJob.perform_later(team)
  end
end
