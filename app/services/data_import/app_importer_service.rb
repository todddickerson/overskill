module DataImport
  class AppImporterService
    def initialize(team, user)
      @team = team
      @user = user
      @errors = []
    end
    
    def import_from_json(json_data)
      begin
        data = JSON.parse(json_data, symbolize_names: true)
        
        # Validate JSON structure
        unless valid_json_structure?(data)
          @errors << "Invalid JSON structure. Please ensure it's an OverSkill export."
          return { success: false, errors: @errors }
        end
        
        # Create or find app
        app = create_or_find_app(data[:app])
        
        # Import tables and data
        data[:tables].each do |table_name, table_data|
          import_table(app, table_name.to_s, table_data)
        end
        
        { 
          success: true, 
          app: app,
          tables_imported: data[:tables].keys.count,
          message: "Successfully imported data for app: #{app.name}"
        }
        
      rescue JSON::ParserError => e
        @errors << "Invalid JSON format: #{e.message}"
        { success: false, errors: @errors }
      rescue => e
        @errors << "Import failed: #{e.message}"
        { success: false, errors: @errors }
      end
    end
    
    def import_from_sql(sql_content)
      # Parse SQL and extract schema/data
      # This is more complex and would require SQL parsing
      # For now, we'll focus on JSON imports
      
      { 
        success: false, 
        errors: ["SQL import not yet implemented. Please use JSON format."]
      }
    end
    
    def import_from_zip(zip_file)
      require 'zip'
      
      imported_apps = []
      
      begin
        Zip::File.open(zip_file) do |zip|
          # Look for JSON files
          json_entries = zip.glob('*.json')
          
          json_entries.each do |entry|
            json_content = entry.get_input_stream.read
            result = import_from_json(json_content)
            
            if result[:success]
              imported_apps << result[:app]
            else
              @errors.concat(result[:errors])
            end
          end
          
          # Import app files if present
          zip.glob('app_files/**/*').each do |entry|
            next if entry.directory?
            
            # Extract app slug from filename pattern
            if entry.name =~ /app_files\/(.+)/
              file_path = $1
              # Find the app and create/update the file
              # This would need the app context from JSON import
            end
          end
        end
        
        if imported_apps.any?
          {
            success: true,
            apps: imported_apps,
            message: "Successfully imported #{imported_apps.count} app(s)"
          }
        else
          {
            success: false,
            errors: @errors.any? ? @errors : ["No importable content found in ZIP file"]
          }
        end
        
      rescue => e
        @errors << "ZIP processing failed: #{e.message}"
        { success: false, errors: @errors }
      end
    end
    
    private
    
    def valid_json_structure?(data)
      # Check for required fields
      data[:app].is_a?(Hash) &&
      data[:app][:name].present? &&
      data[:tables].is_a?(Hash) &&
      data[:metadata].is_a?(Hash)
    end
    
    def create_or_find_app(app_data)
      # Try to find existing app by slug
      app = @team.apps.find_by(slug: app_data[:slug])
      
      if app
        # Update existing app
        app.update!(
          name: app_data[:name],
          updated_at: Time.current
        )
      else
        # Create new app
        app = @team.apps.create!(
          name: app_data[:name],
          slug: app_data[:slug] || app_data[:name].parameterize,
          creator: @team.memberships.find_by(user: @user),
          prompt: "Imported from data export",
          status: "imported",
          base_price: 0,
          visibility: "private"
        )
      end
      
      app
    end
    
    def import_table(app, table_name, table_data)
      # Create or update table
      app_table = app.app_tables.find_or_create_by(name: table_name) do |table|
        table.description = "Imported table"
      end
      
      # Import schema
      if table_data[:schema] && table_data[:schema][:columns]
        import_table_schema(app_table, table_data[:schema][:columns])
      end
      
      # Import data (would use Supabase service)
      if table_data[:records] && table_data[:records].any?
        import_table_records(app_table, table_data[:records])
      end
      
      app_table
    end
    
    def import_table_schema(app_table, columns)
      columns.each do |column_data|
        app_table.app_table_columns.find_or_create_by(name: column_data[:name]) do |column|
          column.column_type = column_data[:type]
          column.required = column_data[:required] || false
          column.default_value = column_data[:default]
          column.options = column_data[:options] || {}
        end
      end
    end
    
    def import_table_records(app_table, records)
      # This would use the Supabase service to insert records
      # For now, we'll just count them
      Rails.logger.info "Would import #{records.count} records into #{app_table.name}"
    end
  end
end