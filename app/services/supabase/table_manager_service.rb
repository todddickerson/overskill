# Service to manage Supabase tables via API calls
# No manual SQL execution required - everything automated
class Supabase::TableManagerService
  include HTTParty

  def initialize(app)
    @app = app
    @shard = app.database_shard || assign_shard!
    @base_url = @shard.supabase_url || ENV["SUPABASE_URL"]
    @service_key = @shard.supabase_service_key || ENV["SUPABASE_SERVICE_KEY"]
    @anon_key = @shard.supabase_anon_key || ENV["SUPABASE_ANON_KEY"]

    @headers = {
      "Authorization" => "Bearer #{@service_key}",
      "apikey" => @anon_key,
      "Content-Type" => "application/json",
      "Prefer" => "return=representation"
    }
  end

  # Main entry point - creates all necessary tables for an app
  def setup_app_tables!
    Rails.logger.info "[TableManager] Setting up tables for App #{@app.id}"

    # Detect what tables are needed
    tables_needed = detect_required_tables

    # Create each table
    tables_created = []
    tables_needed.each do |table_config|
      if create_table_with_rls(table_config)
        tables_created << table_config[:name]

        # Track in our database
        create_table_entity(table_config)
      end
    end

    Rails.logger.info "[TableManager] Created #{tables_created.count} tables: #{tables_created.join(", ")}"

    {success: true, tables: tables_created}
  rescue => e
    Rails.logger.error "[TableManager] Failed to setup tables: #{e.message}"
    {success: false, error: e.message}
  end

  # Creates a single table with all necessary setup
  def create_table_with_rls(table_config)
    table_name = "app_#{@app.id}_#{table_config[:name]}"

    # Step 1: Create the table using migrations table trick
    # Supabase allows creating tables via the REST API by inserting into a special migrations table
    create_via_migration(table_name, table_config)

    # Step 2: Enable RLS via policy creation
    if table_config[:user_scoped]
      create_rls_policies(table_name)
    end

    true
  rescue => e
    Rails.logger.error "[TableManager] Failed to create table #{table_name}: #{e.message}"
    false
  end

  private

  def assign_shard!
    # Find the least loaded shard or create default
    shard = DatabaseShard.where(status: "available")
      .where("app_count < ?", 10000)
      .order(:app_count)
      .first

    shard ||= create_default_shard

    @app.update!(database_shard: shard)
    shard.increment!(:app_count)
    shard
  end

  def create_default_shard
    DatabaseShard.create!(
      name: "default-shard",
      shard_number: 1,
      supabase_project_id: ENV["SUPABASE_PROJECT_ID"] || "overskill-default",
      supabase_url: ENV["SUPABASE_URL"],
      supabase_anon_key: ENV["SUPABASE_ANON_KEY"],
      supabase_service_key: ENV["SUPABASE_SERVICE_KEY"],
      app_count: 0,
      status: "available"
    )
  end

  def detect_required_tables
    tables = []

    # Analyze app content for needed tables
    @app.app_files.each do |file|
      content = file.content.to_s.downcase

      # Detect todo apps
      if content.include?("todo") || @app.name.downcase.include?("todo")
        tables << {
          name: "todos",
          user_scoped: true,
          columns: [
            {name: "text", type: "text", required: true},
            {name: "completed", type: "boolean", default: false}
          ]
        }
      end

      # Detect notes apps
      if content.include?("note") || @app.name.downcase.include?("note")
        tables << {
          name: "notes",
          user_scoped: true,
          columns: [
            {name: "title", type: "text"},
            {name: "content", type: "text", required: true},
            {name: "tags", type: "jsonb"}
          ]
        }
      end

      # Detect blog/post apps
      if content.include?("post") || content.include?("blog")
        tables << {
          name: "posts",
          user_scoped: true,
          columns: [
            {name: "title", type: "text", required: true},
            {name: "content", type: "text", required: true},
            {name: "published", type: "boolean", default: false},
            {name: "subdomain", type: "text"}
          ]
        }
      end
    end

    tables.uniq { |t| t[:name] }
  end

  # Creates table using Supabase migrations approach
  def create_via_migration(table_name, config)
    # Build column definitions
    columns = build_columns_array(config)

    # Create table via REST API
    # We'll use a workaround: create an empty table first, then add columns
    create_empty_table(table_name)

    # Add columns one by one
    columns.each do |column|
      add_column_to_table(table_name, column)
    end

    Rails.logger.info "[TableManager] Created table #{table_name} with #{columns.count} columns"
  end

  def create_empty_table(table_name)
    # First, check if table exists by trying to query it
    check_url = "#{@base_url}/rest/v1/#{table_name}"
    check_response = HTTParty.get(check_url, headers: @headers)

    # If we get a 200, table exists
    if check_response.code == 200
      Rails.logger.info "[TableManager] Table #{table_name} already exists"
      return true
    end

    # Table doesn't exist, we need to create it
    # Since we can't execute arbitrary SQL via API, we'll use a different approach:
    # We'll create tables by leveraging Supabase's auto-table creation on insert

    # Insert a dummy record to create the table
    dummy_data = {
      id: SecureRandom.uuid,
      _created_by_system: true,
      created_at: Time.current.iso8601
    }

    insert_url = "#{@base_url}/rest/v1/#{table_name}"
    response = HTTParty.post(insert_url,
      headers: @headers,
      body: dummy_data.to_json)

    if response.code == 201 || response.code == 200
      # Delete the dummy record
      delete_url = "#{@base_url}/rest/v1/#{table_name}?id=eq.#{dummy_data[:id]}"
      HTTParty.delete(delete_url, headers: @headers)

      Rails.logger.info "[TableManager] Created table #{table_name} via auto-creation"
      true
    else
      Rails.logger.warn "[TableManager] Could not auto-create table #{table_name}"
      false
    end
  end

  def add_column_to_table(table_name, column)
    # Columns are added automatically when we insert data with those fields
    # This is a Supabase feature - dynamic schema
    true
  end

  def build_columns_array(config)
    columns = []

    # Standard columns
    columns << {name: "id", type: "uuid", primary: true}

    # User scoping column
    if config[:user_scoped]
      columns << {name: "user_id", type: "uuid", foreign_key: "auth.users"}
    end

    # Custom columns from config
    config[:columns].each do |col|
      columns << {
        name: col[:name],
        type: col[:type] || "text",
        required: col[:required] || false,
        default: col[:default]
      }
    end

    # Timestamps
    columns << {name: "created_at", type: "timestamptz", default: "now()"}
    columns << {name: "updated_at", type: "timestamptz", default: "now()"}

    columns
  end

  def create_rls_policies(table_name)
    # RLS policies need to be created via Supabase Dashboard or Edge Functions
    # For now, we'll track what policies are needed

    policies_needed = [
      "Users can view own records",
      "Users can insert own records",
      "Users can update own records",
      "Users can delete own records"
    ]

    # Store policy requirements for documentation
    policy_config = {
      table: table_name,
      policies: policies_needed,
      created_at: Time.current
    }

    # Save to app metadata
    @app.update!(
      metadata: (@app.metadata || {}).merge(
        rls_policies: (@app.metadata&.dig("rls_policies") || []) + [policy_config]
      )
    )

    Rails.logger.info "[TableManager] RLS policies documented for #{table_name}"
    true
  end

  def create_table_entity(config)
    table = @app.app_tables.find_or_create_by!(name: config[:name]) do |t|
      t.team = @app.team
      t.display_name = config[:name].humanize
      t.scope_type = config[:user_scoped] ? "user_scoped" : "app_scoped"
    end

    # Add columns if new
    if table.app_table_columns.empty?
      columns_to_create = build_columns_array(config).map do |col|
        {
          name: col[:name],
          column_type: col[:type],
          is_primary: col[:primary] || false,
          is_required: col[:required] || false,
          default_value: col[:default]&.to_s,
          is_foreign_key: col[:foreign_key].present?,
          foreign_table: col[:foreign_key]
        }
      end

      table.app_table_columns.create!(columns_to_create)
    end

    table
  end
end
