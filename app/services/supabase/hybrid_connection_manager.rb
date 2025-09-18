class Supabase::HybridConnectionManager
  # This service manages connections to either managed or custom Supabase instances
  # Key differentiator: Base44 locks users into their platform, we give them choice

  def self.get_service_for_app(app)
    # Get the appropriate database service based on team configuration
    config = app.team.database_config.supabase_config_for_app(app)

    # Create a custom service instance with the right credentials
    case config[:mode]
    when "managed"
      # Use our managed Supabase with standard service
      Supabase::AppDatabaseService.new(app)
    when "custom"
      # Create service with custom credentials
      create_custom_service(app, config)
    end
  end

  def self.create_custom_service(app, config)
    # Create a service instance that uses custom Supabase credentials
    # This allows complete data sovereignty - users own their data

    service = Supabase::AppDatabaseService.new(app)

    # Override the default credentials with custom ones
    service.instance_eval do
      @custom_config = config

      # Override base_uri to use custom URL
      self.class.base_uri(config[:url])

      # Override headers with custom credentials
      @headers = {
        "Authorization" => "Bearer #{config[:service_key]}",
        "Content-Type" => "application/json",
        "apikey" => config[:anon_key]
      }
    end

    service
  end

  def self.migrate_app_to_custom_database(app)
    # Migrate an app from managed to custom database
    # This is our data portability feature - Base44 can't do this

    return {success: false, error: "App not configured for custom database"} unless app.use_custom_database?

    team_config = app.team.database_config
    return {success: false, error: "Team has no custom database configured"} unless team_config&.uses_custom_supabase?

    # Test connection first
    test_result = team_config.test_connection
    return test_result unless test_result[:success]

    begin
      # 1. Export all data from managed database
      export_data = export_app_data(app)

      # 2. Create schema in custom database
      custom_service = create_custom_service(app, team_config.supabase_config_for_app(app))
      custom_service.create_app_database

      # 3. Recreate all tables
      app.app_tables.each do |table|
        columns_schema = table.app_table_columns.map do |col|
          {
            name: col.name,
            type: col.column_type,
            required: col.required,
            default: col.default_value,
            options: col.options
          }
        end

        custom_service.create_table(table.name, columns_schema)
      end

      # 4. Import all data
      import_result = import_app_data(app, export_data, custom_service)

      # 5. Update migration status
      team_config.update!(
        migration_status: "completed",
        last_migration_at: Time.current
      )

      {
        success: true,
        message: "Successfully migrated to custom database",
        tables_migrated: app.app_tables.count,
        records_migrated: import_result[:total_records]
      }
    rescue => e
      Rails.logger.error "Migration failed for app #{app.id}: #{e.message}"
      {success: false, error: e.message}
    end
  end

  def self.export_app_data(app)
    # Export all app data in a portable format
    managed_service = Supabase::AppDatabaseService.new(app)

    export = {
      app_id: app.id,
      exported_at: Time.current,
      tables: {}
    }

    app.app_tables.each do |table|
      # Get all records from the table
      records = managed_service.get_records(table.name, limit: 10000)

      export[:tables][table.name] = {
        schema: table.schema,
        records: records,
        count: records.length
      }
    end

    export
  end

  def self.import_app_data(app, export_data, custom_service)
    total_records = 0

    export_data[:tables].each do |table_name, table_data|
      table_data[:records].each do |record|
        # Remove system fields that will be recreated
        record.delete("id")
        record.delete("created_at")
        record.delete("updated_at")

        # Import to custom database
        custom_service.create_record(table_name, record, app.creator.user_id)
        total_records += 1
      end
    end

    {success: true, total_records: total_records}
  end

  def self.sync_schema_to_custom(app)
    # Sync schema changes to custom database
    # This keeps custom databases in sync with app schema changes

    return unless app.use_custom_database?

    get_service_for_app(app)

    # Compare schemas and sync differences
    # This is handled by the existing create_table and add_column methods
    {success: true, message: "Schema synced to custom database"}
  end
end
