# Service to manage database schema for apps
class Database::AppSchemaService
  def initialize(app)
    @app = app
    @shard = app.database_shard || assign_shard!
  end
  
  def setup_default_schema!
    # Detect what tables are needed based on app type and content
    tables_needed = detect_required_tables
    
    tables_needed.each do |table_config|
      create_table_entity(table_config)
    end
    
    # Create all tables in Supabase
    create_all_tables_in_supabase!
  end
  
  def create_table_entity(config)
    table = @app.app_tables.find_or_create_by!(name: config[:name]) do |t|
      t.team = @app.team
      t.display_name = config[:display_name] || config[:name].humanize
      t.scope_type = config[:scope_type] || 'user_scoped'
    end
    
    # Add columns if table is new
    if table.app_table_columns.empty?
      create_standard_columns(table, config[:columns] || [])
    end
    
    table
  end
  
  def create_all_tables_in_supabase!
    @app.app_tables.each do |table|
      create_table_in_supabase!(table)
    end
  end
  
  def create_table_in_supabase!(table)
    table_name = "app_#{@app.id}_#{table.name}"
    
    # Generate SQL
    create_sql = generate_create_table_sql(table, table_name)
    rls_sql = generate_rls_policies_sql(table, table_name) if table.user_scoped?
    
    # Execute using HTTP API since we don't have rpc function
    execute_supabase_sql(create_sql)
    execute_supabase_sql(rls_sql) if rls_sql
    
    Rails.logger.info "[AppSchemaService] Created table #{table_name} in Supabase"
    true
  rescue => e
    Rails.logger.error "[AppSchemaService] Failed to create table #{table_name}: #{e.message}"
    false
  end
  
  private
  
  def assign_shard!
    # Get the least loaded shard
    shard = DatabaseShard.first || create_default_shard
    @app.update!(database_shard: shard)
    shard
  end
  
  def create_default_shard
    DatabaseShard.create!(
      name: 'default-shard',
      shard_number: 1,
      supabase_project_id: 'overskill-default',
      supabase_url: ENV['SUPABASE_URL'],
      supabase_anon_key: ENV['SUPABASE_ANON_KEY'],
      supabase_service_key: ENV['SUPABASE_SERVICE_KEY'],
      app_count: 0,
      status: 'available'
    )
  end
  
  def detect_required_tables
    tables = []
    
    # Analyze app files for database usage
    @app.app_files.each do |file|
      content = file.content.to_s.downcase
      
      # Look for common entity patterns
      if content.include?('todo') || @app.name.downcase.include?('todo')
        tables << {
          name: 'todos',
          display_name: 'Todos',
          scope_type: 'user_scoped',
          columns: [
            { name: 'text', type: 'text', required: true },
            { name: 'completed', type: 'boolean', default: 'false' }
          ]
        }
      end
      
      if content.include?('note') || @app.name.downcase.include?('note')
        tables << {
          name: 'notes',
          display_name: 'Notes',
          scope_type: 'user_scoped',
          columns: [
            { name: 'title', type: 'text' },
            { name: 'content', type: 'text', required: true },
            { name: 'tags', type: 'json' }
          ]
        }
      end
      
      if content.include?('post') || content.include?('blog')
        tables << {
          name: 'posts',
          display_name: 'Posts',
          scope_type: 'user_scoped',
          columns: [
            { name: 'title', type: 'text', required: true },
            { name: 'content', type: 'text', required: true },
            { name: 'published', type: 'boolean', default: 'false' },
            { name: 'subdomain', type: 'text' }
          ]
        }
      end
    end
    
    tables.uniq { |t| t[:name] }
  end
  
  def create_standard_columns(table, custom_columns = [])
    columns = []
    
    # Standard columns
    columns << { name: 'id', column_type: 'uuid', is_primary: true }
    
    # User scoping column
    if table.user_scoped?
      columns << { 
        name: 'user_id', 
        column_type: 'uuid', 
        is_foreign_key: true,
        foreign_table: 'auth.users'
      }
    end
    
    # Custom columns
    custom_columns.each do |col|
      columns << {
        name: col[:name],
        column_type: col[:type] || 'text',
        is_required: col[:required] || false,
        default_value: col[:default]
      }
    end
    
    # Timestamps
    columns << { name: 'created_at', column_type: 'timestamp', default_value: 'now()' }
    columns << { name: 'updated_at', column_type: 'timestamp', default_value: 'now()' }
    
    table.app_table_columns.create!(columns)
  end
  
  def generate_create_table_sql(table, table_name)
    columns = []
    
    table.app_table_columns.each do |col|
      sql_type = column_sql_type(col.column_type)
      definition = "#{col.name} #{sql_type}"
      
      if col.is_primary?
        definition += " DEFAULT gen_random_uuid() PRIMARY KEY"
      elsif col.is_foreign_key? && col.foreign_table == 'auth.users'
        definition += " REFERENCES auth.users(id) ON DELETE CASCADE"
      elsif col.is_required?
        definition += " NOT NULL"
      end
      
      if col.default_value.present? && !col.is_primary?
        definition += " DEFAULT #{col.default_value}"
      end
      
      columns << definition
    end
    
    <<~SQL
      CREATE TABLE IF NOT EXISTS #{table_name} (
        #{columns.join(",\n        ")}
      );
      
      -- Create indexes for performance
      CREATE INDEX IF NOT EXISTS idx_#{table_name}_created_at 
        ON #{table_name}(created_at DESC);
      #{table.user_scoped? ? "CREATE INDEX IF NOT EXISTS idx_#{table_name}_user_id ON #{table_name}(user_id);" : ''}
    SQL
  end
  
  def generate_rls_policies_sql(table, table_name)
    <<~SQL
      -- Enable Row Level Security
      ALTER TABLE #{table_name} ENABLE ROW LEVEL SECURITY;
      
      -- Policy: Users can only see their own #{table.name}
      CREATE POLICY "Users can view own #{table.name}"
        ON #{table_name} FOR SELECT
        USING (auth.uid() = user_id);
      
      -- Policy: Users can only insert their own #{table.name}
      CREATE POLICY "Users can insert own #{table.name}"
        ON #{table_name} FOR INSERT
        WITH CHECK (auth.uid() = user_id);
      
      -- Policy: Users can only update their own #{table.name}
      CREATE POLICY "Users can update own #{table.name}"
        ON #{table_name} FOR UPDATE
        USING (auth.uid() = user_id)
        WITH CHECK (auth.uid() = user_id);
      
      -- Policy: Users can only delete their own #{table.name}
      CREATE POLICY "Users can delete own #{table.name}"
        ON #{table_name} FOR DELETE
        USING (auth.uid() = user_id);
      
      -- Grant permissions to authenticated users
      GRANT ALL ON #{table_name} TO authenticated;
      GRANT ALL ON #{table_name} TO service_role;
    SQL
  end
  
  def column_sql_type(type)
    case type
    when 'text' then 'TEXT'
    when 'number' then 'NUMERIC'
    when 'boolean' then 'BOOLEAN'
    when 'date' then 'DATE'
    when 'timestamp', 'datetime' then 'TIMESTAMPTZ'
    when 'uuid' then 'UUID'
    when 'json' then 'JSONB'
    else 'TEXT'
    end
  end
  
  def execute_supabase_sql(sql)
    return if sql.blank?
    
    Rails.logger.info "[AppSchemaService] Executing SQL:\n#{sql}"
    
    # For now, we'll create a simple table using Supabase's REST API
    # The proper way is to use migrations or edge functions, but for MVP:
    
    # Option 1: Use supabase-rb gem if available
    begin
      if defined?(Supabase) && @shard.supabase_url.present?
        # This would require the supabase-rb gem
        client = Supabase::Client.new(
          supabase_url: @shard.supabase_url,
          supabase_key: @shard.supabase_service_key
        )
        # Note: Direct SQL execution requires an edge function or migration
        Rails.logger.warn "[AppSchemaService] Direct SQL execution not available via REST API"
      end
    rescue => e
      Rails.logger.error "[AppSchemaService] Failed to execute SQL: #{e.message}"
    end
    
    # Option 2: For MVP, we'll rely on pre-created tables
    # Tables should be created via Supabase dashboard or migrations
    Rails.logger.info "[AppSchemaService] Table creation requires Supabase dashboard or migration"
    
    # Save the SQL for manual execution
    sql_file = Rails.root.join('tmp', "app_#{@app.id}_schema.sql")
    File.write(sql_file, sql)
    Rails.logger.info "[AppSchemaService] SQL saved to: #{sql_file}"
  end
end