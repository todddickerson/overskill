# Automatic table creation service using Supabase's auto-schema feature
# This leverages Supabase's ability to auto-create tables on first insert
class Supabase::AutoTableService
  include HTTParty
  
  def initialize(app)
    @app = app
    @base_url = ENV['SUPABASE_URL']
    @anon_key = ENV['SUPABASE_ANON_KEY']
    @service_key = ENV['SUPABASE_SERVICE_KEY']
    
    @headers = {
      'Authorization' => "Bearer #{@service_key}",
      'apikey' => @anon_key,
      'Content-Type' => 'application/json',
      'Prefer' => 'return=representation'
    }
  end
  
  # Main method to ensure tables exist for an app
  def ensure_tables_exist!
    Rails.logger.info "[AutoTable] Ensuring tables for App #{@app.id}"
    
    tables_created = []
    
    # Detect what tables are needed based on app content
    tables_needed = detect_required_tables
    
    tables_needed.each do |table_config|
      table_name = "app_#{@app.id}_#{table_config[:name]}"
      
      if ensure_table_exists(table_name, table_config)
        tables_created << table_name
        save_table_metadata(table_config)
      end
    end
    
    Rails.logger.info "[AutoTable] Ensured #{tables_created.count} tables exist"
    
    { success: true, tables: tables_created }
  rescue => e
    Rails.logger.error "[AutoTable] Failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  private
  
  def detect_required_tables
    tables = []
    
    # Check app files for database usage patterns
    @app.app_files.each do |file|
      content = file.content.to_s
      
      # Look for Supabase table references
      content.scan(/\.from\(['"`]app_\d+_(\w+)['"`]\)/).each do |match|
        table_name = match[0]
        tables << build_table_config(table_name)
      end
      
      # Also check for common patterns
      if content.downcase.include?('todo')
        tables << build_table_config('todos')
      elsif content.downcase.include?('note')
        tables << build_table_config('notes')
      elsif content.downcase.include?('post') || content.downcase.include?('blog')
        tables << build_table_config('posts')
      end
    end
    
    tables.uniq { |t| t[:name] }
  end
  
  def build_table_config(table_name)
    config = {
      name: table_name,
      user_scoped: true
    }
    
    # Define schema based on table type
    case table_name
    when 'todos'
      config[:columns] = [
        { name: 'text', type: 'text', required: true },
        { name: 'completed', type: 'boolean', default: false }
      ]
    when 'notes'
      config[:columns] = [
        { name: 'title', type: 'text' },
        { name: 'content', type: 'text', required: true },
        { name: 'tags', type: 'jsonb' }
      ]
    when 'posts'
      config[:columns] = [
        { name: 'title', type: 'text', required: true },
        { name: 'content', type: 'text', required: true },
        { name: 'published', type: 'boolean', default: false },
        { name: 'slug', type: 'text' }
      ]
    else
      # Generic columns
      config[:columns] = [
        { name: 'name', type: 'text' },
        { name: 'data', type: 'jsonb' }
      ]
    end
    
    config
  end
  
  def ensure_table_exists(table_name, config)
    # First, try to query the table
    check_url = "#{@base_url}/rest/v1/#{table_name}?limit=1"
    check_response = HTTParty.get(check_url, headers: @headers)
    
    if check_response.code == 200
      Rails.logger.info "[AutoTable] Table #{table_name} already exists"
      return true
    end
    
    # Table doesn't exist - create it by inserting a template record
    # Supabase will auto-create the table with the schema we provide
    template_record = build_template_record(config)
    
    insert_url = "#{@base_url}/rest/v1/#{table_name}"
    insert_response = HTTParty.post(insert_url,
      headers: @headers,
      body: template_record.to_json
    )
    
    if insert_response.code == 201 || insert_response.code == 200
      # Successfully created table and inserted template
      # Now delete the template record
      if template_record[:id]
        delete_url = "#{@base_url}/rest/v1/#{table_name}?id=eq.#{template_record[:id]}"
        HTTParty.delete(delete_url, headers: @headers)
      end
      
      Rails.logger.info "[AutoTable] Created table #{table_name} via auto-schema"
      
      # Enable RLS (this requires the Edge Function)
      enable_rls_for_table(table_name) if config[:user_scoped]
      
      return true
    else
      Rails.logger.error "[AutoTable] Failed to create #{table_name}: #{insert_response.body}"
      return false
    end
  end
  
  def build_template_record(config)
    record = {
      id: SecureRandom.uuid,
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601
    }
    
    # Add user_id for user-scoped tables
    if config[:user_scoped]
      # Use a placeholder UUID that we'll delete
      record[:user_id] = '00000000-0000-0000-0000-000000000000'
    end
    
    # Add columns from config with default values
    config[:columns].each do |col|
      value = case col[:type]
      when 'text'
        col[:default] || '_template_'
      when 'boolean'
        col[:default] || false
      when 'jsonb'
        col[:default] || {}
      when 'integer', 'number'
        col[:default] || 0
      else
        col[:default] || ''
      end
      
      record[col[:name].to_sym] = value
    end
    
    record
  end
  
  def enable_rls_for_table(table_name)
    # Try to enable RLS via Edge Function if available
    edge_function_url = "#{@base_url}/functions/v1/execute-sql"
    
    rls_sql = <<~SQL
      -- Enable RLS
      ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;
      
      -- Create policies for user isolation
      CREATE POLICY "Users can view own #{table_name}" ON #{table_name}
        FOR SELECT USING (auth.uid()::text = user_id::text OR user_id = '00000000-0000-0000-0000-000000000000'::uuid);
      
      CREATE POLICY "Users can insert own #{table_name}" ON #{table_name}
        FOR INSERT WITH CHECK (auth.uid()::text = user_id::text);
      
      CREATE POLICY "Users can update own #{table_name}" ON #{table_name}
        FOR UPDATE USING (auth.uid()::text = user_id::text);
      
      CREATE POLICY "Users can delete own #{table_name}" ON #{table_name}
        FOR DELETE USING (auth.uid()::text = user_id::text);
      
      -- Grant permissions
      GRANT ALL ON #{table_name} TO authenticated;
      GRANT ALL ON #{table_name} TO service_role;
    SQL
    
    response = HTTParty.post(edge_function_url,
      headers: @headers,
      body: { sql: rls_sql }.to_json
    )
    
    if response.code == 200
      Rails.logger.info "[AutoTable] RLS enabled for #{table_name}"
    else
      Rails.logger.warn "[AutoTable] Could not enable RLS for #{table_name} - manual setup may be required"
      
      # Save RLS requirements for manual setup
      save_rls_requirements(table_name, rls_sql)
    end
  rescue => e
    Rails.logger.warn "[AutoTable] RLS setup error: #{e.message}"
    save_rls_requirements(table_name, rls_sql)
  end
  
  def save_rls_requirements(table_name, sql)
    # Save to a file for manual execution if needed
    sql_file = Rails.root.join('tmp', "rls_#{table_name}.sql")
    File.write(sql_file, sql)
    
    # Also save to app metadata
    @app.update!(
      metadata: (@app.metadata || {}).merge(
        pending_rls: (@app.metadata&.dig('pending_rls') || []) + [{
          table: table_name,
          sql_file: sql_file.to_s,
          created_at: Time.current
        }]
      )
    )
  end
  
  def save_table_metadata(config)
    # Create AppTable record to track the table
    table = @app.app_tables.find_or_create_by!(name: config[:name]) do |t|
      t.team = @app.team
      t.display_name = config[:name].humanize
      t.scope_type = config[:user_scoped] ? 'user_scoped' : 'app_scoped'
    end
    
    # Add column definitions
    if table.app_table_columns.empty?
      columns = [
        { name: 'id', column_type: 'uuid', is_primary: true }
      ]
      
      if config[:user_scoped]
        columns << { name: 'user_id', column_type: 'uuid', is_foreign_key: true, foreign_table: 'auth.users' }
      end
      
      config[:columns].each do |col|
        columns << {
          name: col[:name],
          column_type: col[:type] || 'text',
          is_required: col[:required] || false,
          default_value: col[:default]&.to_s
        }
      end
      
      columns += [
        { name: 'created_at', column_type: 'timestamptz', default_value: 'now()' },
        { name: 'updated_at', column_type: 'timestamptz', default_value: 'now()' }
      ]
      
      table.app_table_columns.create!(columns)
    end
    
    table
  end
end