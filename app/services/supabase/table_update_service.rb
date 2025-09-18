# Service to update/modify existing tables when app requirements change
# Never deletes tables or columns for safety - only adds new ones
class Supabase::TableUpdateService
  include HTTParty

  def initialize(app)
    @app = app
    @base_url = ENV["SUPABASE_URL"]
    @anon_key = ENV["SUPABASE_ANON_KEY"]
    @service_key = ENV["SUPABASE_SERVICE_KEY"]

    @headers = {
      "Authorization" => "Bearer #{@service_key}",
      "apikey" => @anon_key,
      "Content-Type" => "application/json",
      "Prefer" => "return=representation"
    }
  end

  # Main method called when app is updated
  def update_tables_for_app!
    Rails.logger.info "[TableUpdate] Checking for table updates in app #{@app.id}"

    # Detect current table requirements
    required_tables = detect_required_tables
    existing_tables = @app.app_tables.pluck(:name)

    # Find new tables to create
    new_tables = required_tables.reject { |t| existing_tables.include?(t[:name]) }

    # Create new tables
    new_tables.each do |table_config|
      create_new_table(table_config)
    end

    # Update existing tables (add new columns if needed)
    existing_tables.each do |table_name|
      update_existing_table(table_name)
    end

    {
      success: true,
      new_tables: new_tables.map { |t| t[:name] },
      updated_tables: existing_tables
    }
  rescue => e
    Rails.logger.error "[TableUpdate] Failed: #{e.message}"
    {success: false, error: e.message}
  end

  private

  def detect_required_tables
    tables = []

    @app.app_files.each do |file|
      content = file.content.to_s

      # Look for Supabase table references in the code
      content.scan(/\.from\(['"`]app_#{@app.id}_(\w+)['"`]\)/).each do |match|
        table_name = match[0]
        tables << build_table_config(table_name)
      end

      # Also detect based on common patterns
      detect_table_patterns(content, tables)
    end

    tables.uniq { |t| t[:name] }
  end

  def detect_table_patterns(content, tables)
    content_lower = content.downcase

    # Todo pattern
    if content_lower.include?("todo") && !tables.any? { |t| t[:name] == "todos" }
      tables << build_table_config("todos")
    end

    # Notes pattern
    if content_lower.include?("note") && !tables.any? { |t| t[:name] == "notes" }
      tables << build_table_config("notes")
    end

    # Posts/Blog pattern
    if (content_lower.include?("post") || content_lower.include?("blog")) &&
        !tables.any? { |t| t[:name] == "posts" }
      tables << build_table_config("posts")
    end

    # Messages/Chat pattern
    if (content_lower.include?("message") || content_lower.include?("chat")) &&
        !tables.any? { |t| t[:name] == "messages" }
      tables << {
        name: "messages",
        user_scoped: true,
        columns: [
          {name: "content", type: "text", required: true},
          {name: "sender_id", type: "uuid"},
          {name: "recipient_id", type: "uuid"},
          {name: "read", type: "boolean", default: false}
        ]
      }
    end

    # Events/Calendar pattern
    if (content_lower.include?("event") || content_lower.include?("calendar")) &&
        !tables.any? { |t| t[:name] == "events" }
      tables << {
        name: "events",
        user_scoped: true,
        columns: [
          {name: "title", type: "text", required: true},
          {name: "description", type: "text"},
          {name: "start_date", type: "timestamptz", required: true},
          {name: "end_date", type: "timestamptz"},
          {name: "location", type: "text"},
          {name: "attendees", type: "jsonb"}
        ]
      }
    end
  end

  def build_table_config(table_name)
    config = {
      name: table_name,
      user_scoped: true
    }

    # Define standard columns based on table type
    config[:columns] = case table_name
    when "todos"
      [
        {name: "text", type: "text", required: true},
        {name: "completed", type: "boolean", default: false},
        {name: "due_date", type: "date"},
        {name: "priority", type: "text"}
      ]
    when "notes"
      [
        {name: "title", type: "text"},
        {name: "content", type: "text", required: true},
        {name: "tags", type: "jsonb"},
        {name: "folder", type: "text"}
      ]
    when "posts"
      [
        {name: "title", type: "text", required: true},
        {name: "content", type: "text", required: true},
        {name: "published", type: "boolean", default: false},
        {name: "subdomain", type: "text"},
        {name: "tags", type: "jsonb"},
        {name: "views", type: "integer", default: 0}
      ]
    else
      # Generic columns for unknown table types
      [
        {name: "name", type: "text"},
        {name: "description", type: "text"},
        {name: "data", type: "jsonb"},
        {name: "status", type: "text"}
      ]
    end

    config
  end

  def create_new_table(table_config)
    table_name = "app_#{@app.id}_#{table_config[:name]}"

    Rails.logger.info "[TableUpdate] Creating new table: #{table_name}"

    # Use AutoTableService to create the table
    Supabase::AutoTableService.new(@app)

    # Build template record for auto-creation
    template_record = {
      id: SecureRandom.uuid,
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601
    }

    if table_config[:user_scoped]
      template_record[:user_id] = "00000000-0000-0000-0000-000000000000"
    end

    table_config[:columns].each do |col|
      template_record[col[:name].to_sym] = get_default_value(col)
    end

    # Insert to create table
    insert_url = "#{@base_url}/rest/v1/#{table_name}"
    response = HTTParty.post(insert_url,
      headers: @headers,
      body: template_record.to_json)

    if response.code == 201 || response.code == 200
      # Delete template record
      delete_url = "#{@base_url}/rest/v1/#{table_name}?id=eq.#{template_record[:id]}"
      HTTParty.delete(delete_url, headers: @headers)

      # Save table metadata
      save_table_metadata(table_config)

      Rails.logger.info "[TableUpdate] Successfully created table #{table_name}"
      true
    else
      Rails.logger.error "[TableUpdate] Failed to create table #{table_name}: #{response.body}"
      false
    end
  end

  def update_existing_table(table_name)
    full_table_name = "app_#{@app.id}_#{table_name}"

    # Detect new columns needed
    new_columns = detect_new_columns_for_table(table_name)

    return if new_columns.empty?

    Rails.logger.info "[TableUpdate] Adding #{new_columns.count} new columns to #{full_table_name}"

    # Add new columns by inserting a record with those fields
    # Supabase will auto-add columns
    new_columns.each do |column|
      add_column_to_table(full_table_name, column)
    end
  end

  def detect_new_columns_for_table(table_name)
    new_columns = []

    # Analyze app code for new field references
    @app.app_files.each do |file|
      content = file.content.to_s

      # Look for field references in insert/update operations

      # Match patterns like: .insert([{ field: value }])
      content.scan(/\.insert\s*\(\s*\[?\s*\{([^}]+)\}/).each do |match|
        fields = match[0]
        extract_field_names(fields).each do |field|
          unless column_exists?(table_name, field)
            new_columns << {name: field, type: "text"}
          end
        end
      end

      # Match patterns like: .update({ field: value })
      content.scan(/\.update\s*\(\s*\{([^}]+)\}/).each do |match|
        fields = match[0]
        extract_field_names(fields).each do |field|
          unless column_exists?(table_name, field)
            new_columns << {name: field, type: "text"}
          end
        end
      end
    end

    new_columns.uniq { |c| c[:name] }
  end

  def extract_field_names(fields_string)
    # Extract field names from JavaScript object notation
    field_names = []

    # Match patterns like: fieldName: value or 'fieldName': value or "fieldName": value
    fields_string.scan(/['"]?(\w+)['"]?\s*:/).each do |match|
      field_name = match[0]
      # Skip standard fields we already have
      next if %w[id user_id created_at updated_at].include?(field_name)
      field_names << field_name
    end

    field_names
  end

  def column_exists?(table_name, column_name)
    table = @app.app_tables.find_by(name: table_name)
    return false unless table

    table.app_table_columns.exists?(name: column_name)
  end

  def add_column_to_table(full_table_name, column)
    # Insert a dummy record with the new field to trigger auto-column creation
    dummy_record = {
      :id => SecureRandom.uuid,
      column[:name] => get_default_value(column),
      :created_at => Time.current.iso8601
    }

    insert_url = "#{@base_url}/rest/v1/#{full_table_name}"
    response = HTTParty.post(insert_url,
      headers: @headers,
      body: dummy_record.to_json)

    if response.code == 201 || response.code == 200
      # Delete the dummy record
      delete_url = "#{@base_url}/rest/v1/#{full_table_name}?id=eq.#{dummy_record[:id]}"
      HTTParty.delete(delete_url, headers: @headers)

      Rails.logger.info "[TableUpdate] Added column #{column[:name]} to #{full_table_name}"

      # Update our metadata
      update_column_metadata(full_table_name, column)
      true
    else
      Rails.logger.warn "[TableUpdate] Could not add column #{column[:name]}: #{response.body}"
      false
    end
  end

  def get_default_value(column)
    return column[:default] if column[:default]

    case column[:type]
    when "text" then "_default_"
    when "boolean" then false
    when "integer", "number" then 0
    when "date", "timestamptz" then Time.current.iso8601
    when "jsonb", "json" then {}
    when "uuid" then SecureRandom.uuid
    else ""
    end
  end

  def save_table_metadata(config)
    table = @app.app_tables.find_or_create_by!(name: config[:name]) do |t|
      t.team = @app.team
      t.display_name = config[:name].humanize
      t.scope_type = config[:user_scoped] ? "user_scoped" : "app_scoped"
    end

    # Add columns if not already tracked
    config[:columns].each do |col|
      table.app_table_columns.find_or_create_by!(name: col[:name]) do |c|
        c.column_type = col[:type] || "text"
        c.is_required = col[:required] || false
        c.default_value = col[:default]&.to_s
      end
    end

    table
  end

  def update_column_metadata(table_name, column)
    # Extract just the table name without prefix
    simple_name = table_name.gsub(/^app_\d+_/, "")

    table = @app.app_tables.find_by(name: simple_name)
    return unless table

    table.app_table_columns.find_or_create_by!(name: column[:name]) do |c|
      c.column_type = column[:type] || "text"
      c.is_required = false
      c.default_value = column[:default]&.to_s
    end
  end
end
