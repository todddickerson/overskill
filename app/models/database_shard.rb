class DatabaseShard < ApplicationRecord
  # Manages horizontal sharding across multiple Supabase projects
  # Each shard handles 10,000 apps with perfect RLS isolation

  APPS_PER_SHARD = 10_000

  # Shard states
  enum :status, {
    provisioning: 0,
    available: 1,
    at_capacity: 2,
    maintenance: 3,
    decommissioned: 4
  }

  validates :name, presence: true, uniqueness: true
  validates :supabase_project_id, presence: true, uniqueness: true
  validates :supabase_url, presence: true, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validates :supabase_anon_key, presence: true
  validates :app_count, numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: APPS_PER_SHARD}

  # Encrypt sensitive keys
  encrypts :supabase_anon_key
  encrypts :supabase_service_key

  # Associations
  has_many :apps, dependent: :restrict_with_error

  # Scopes
  scope :available, -> { where(status: "available") }
  scope :with_capacity, -> { available.where("app_count < ?", APPS_PER_SHARD) }
  scope :ordered_by_usage, -> { order(app_count: :asc) }

  class << self
    # Get the best shard for a new app (least loaded with capacity)
    def current_shard
      # Skip during Rails initialization and testing
      return nil if Rails.application.config.eager_load == false

      # Prevent infinite recursion by using a thread-local variable
      return nil if Thread.current[:database_shard_current_shard_called]

      Thread.current[:database_shard_current_shard_called] = true

      begin
        return nil unless ApplicationRecord.connection.table_exists?("database_shards")
        return nil unless ApplicationRecord.connection.active?

        with_capacity.ordered_by_usage.first
      ensure
        Thread.current[:database_shard_current_shard_called] = false
      end
    rescue => e
      Rails.logger.warn "[DatabaseShard] Error in current_shard: #{e.message}"
      nil
    end

    # Create a new shard when needed
    def create_new_shard!
      shard_number = maximum(:shard_number).to_i + 1
      shard_name = "shard-%03d" % shard_number

      Rails.logger.info "[Sharding] Creating new shard: #{shard_name}"

      # Provision new Supabase project
      supabase_config = provision_supabase_project(shard_name)

      create!(
        name: shard_name,
        shard_number: shard_number,
        supabase_project_id: supabase_config[:project_id],
        supabase_url: supabase_config[:url],
        supabase_anon_key: supabase_config[:anon_key],
        supabase_service_key: supabase_config[:service_key],
        app_count: 0,
        status: :available
      )
    end

    private

    def provision_supabase_project(shard_name)
      # TODO: Implement Supabase Management API call
      # For now, return mock data
      {
        project_id: "overskill-#{shard_name}",
        url: "https://#{shard_name}.supabase.co",
        anon_key: SecureRandom.hex(32),
        service_key: SecureRandom.hex(32)
      }
    end
  end

  # Check if shard has capacity
  def has_capacity?
    app_count < APPS_PER_SHARD
  end

  # Assign an app to this shard
  def assign_app!(app)
    transaction do
      app.update!(database_shard: self)
      increment!(:app_count)
      update!(status: :at_capacity) if app_count >= APPS_PER_SHARD
    end
  end

  # Get Supabase client for this shard
  def supabase_client(use_service_key: false)
    require "supabase"

    Supabase::Client.new(
      supabase_url: supabase_url,
      supabase_key: use_service_key ? supabase_service_key : supabase_anon_key
    )
  end

  # Initialize shard database with required schema
  def initialize_schema!
    client = supabase_client(use_service_key: true)

    # Create base tables
    create_app_tables_sql = <<~SQL
      -- Apps data table with RLS
      CREATE TABLE IF NOT EXISTS app_data (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        app_id text NOT NULL,
        owner_rails_id bigint NOT NULL,
        data jsonb DEFAULT '{}',
        created_at timestamptz DEFAULT now(),
        updated_at timestamptz DEFAULT now()
      );
      
      -- Analytics events table
      CREATE TABLE IF NOT EXISTS analytics_events (
        id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
        app_id text NOT NULL,
        owner_rails_id bigint NOT NULL,
        event_type text NOT NULL,
        event_data jsonb DEFAULT '{}',
        timestamp timestamptz DEFAULT now(),
        ip_address inet,
        user_agent text
      );
      
      -- Enable RLS
      ALTER TABLE app_data ENABLE ROW LEVEL SECURITY;
      ALTER TABLE analytics_events ENABLE ROW LEVEL SECURITY;
      
      -- RLS Policies for perfect isolation
      CREATE POLICY "app_data_isolation" ON app_data
      FOR ALL USING (
        owner_rails_id = current_setting('app.current_user_id', true)::bigint
      );
      
      CREATE POLICY "analytics_isolation" ON analytics_events
      FOR ALL USING (
        owner_rails_id = current_setting('app.current_user_id', true)::bigint
      );
      
      -- Helper function to set RLS context
      CREATE OR REPLACE FUNCTION set_config(setting_name text, new_value text, is_local boolean)
      RETURNS void AS $$
      BEGIN
        PERFORM set_config(setting_name, new_value, is_local);
      END;
      $$ LANGUAGE plpgsql SECURITY DEFINER;
    SQL

    # Execute schema creation
    client.rpc("exec_sql", {sql: create_app_tables_sql})

    Rails.logger.info "[Sharding] Initialized schema for #{name}"
  rescue => e
    Rails.logger.error "[Sharding] Failed to initialize schema for #{name}: #{e.message}"
    raise
  end

  # Health check for shard
  def healthy?
    client = supabase_client
    client.from("app_data").select("count").limit(1).execute
    true
  rescue
    false
  end

  # Get usage statistics
  def usage_stats
    {
      name: name,
      app_count: app_count,
      capacity_percentage: (app_count * 100.0 / APPS_PER_SHARD).round(2),
      status: status,
      healthy: healthy?
    }
  end
end
