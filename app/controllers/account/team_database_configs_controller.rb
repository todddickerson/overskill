class Account::TeamDatabaseConfigsController < Account::ApplicationController
  before_action :set_team
  before_action :set_config
  before_action :authorize_admin
  
  def show
    # Show current database configuration
  end
  
  def edit
    # Edit database configuration
  end
  
  def update
    if @config.update(config_params)
      # Test connection if switching to custom
      if @config.uses_custom_supabase?
        test_result = @config.test_connection
        
        if test_result[:success]
          @config.update!(validated: true, last_validated_at: Time.current)
          redirect_to account_team_database_config_path(@team), 
            notice: "Database configuration updated successfully. Connection validated."
        else
          @config.errors.add(:base, "Connection test failed: #{test_result[:message]}")
          render :edit, status: :unprocessable_entity
        end
      else
        redirect_to account_team_database_config_path(@team), 
          notice: "Database configuration updated to use managed database."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end
  
  def test_connection
    test_result = @config.test_connection
    
    respond_to do |format|
      format.json { render json: test_result }
    end
  end
  
  def export_instructions
    # Show instructions for exporting data
    @apps = @team.apps.includes(:app_tables)
  end
  
  def export_app
    @app = @team.apps.find(params[:app_id])
    exporter = DataExport::AppExporterService.new(@app)
    
    respond_to do |format|
      format.sql do
        send_data exporter.export_to_sql,
                  filename: "#{@app.slug}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.sql",
                  type: 'text/plain'
      end
      
      format.json do
        send_data exporter.export_to_json.to_json,
                  filename: "#{@app.slug}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json",
                  type: 'application/json'
      end
      
      format.zip do
        zip_file = exporter.export_to_zip
        send_file zip_file.path,
                  filename: "#{@app.slug}_export_#{Time.current.strftime('%Y%m%d_%H%M%S')}.zip",
                  type: 'application/zip',
                  disposition: 'attachment'
        # Clean up temp file after sending
        zip_file.close
        zip_file.unlink
      end
    end
  end
  
  def export_all_apps
    # Export all apps for the team
    # This could be a background job for large exports
    ExportAllAppsJob.perform_later(@team, current_user)
    
    redirect_to export_instructions_account_team_database_config_path(@team),
                notice: "Export started. You'll receive an email when it's ready."
  end
  
  def import_data
    unless params[:import_file].present?
      redirect_to account_team_database_config_path(@team), 
                  alert: "Please select a file to import."
      return
    end
    
    uploaded_file = params[:import_file]
    importer = DataImport::AppImporterService.new(@team, current_user)
    
    result = case File.extname(uploaded_file.original_filename).downcase
    when '.json'
      importer.import_from_json(uploaded_file.read)
    when '.zip'
      importer.import_from_zip(uploaded_file.tempfile)
    else
      { success: false, errors: ["Unsupported file format. Please use JSON or ZIP."] }
    end
    
    if result[:success]
      redirect_to account_team_database_config_path(@team),
                  notice: result[:message]
    else
      redirect_to account_team_database_config_path(@team),
                  alert: "Import failed: #{result[:errors].join(', ')}"
    end
  end
  
  def migration_status
    # Show migration status for hybrid mode
    @apps_migration_status = @team.apps.map do |app|
      {
        app: app,
        tables_count: app.app_tables.count,
        uses_custom: app.use_custom_database?,
        can_migrate: @config.uses_custom_supabase? && !app.use_custom_database?
      }
    end
  end
  
  private
  
  def set_team
    @team = current_team
  end
  
  def set_config
    @config = @team.database_config
  end
  
  def authorize_admin
    # Only team admins can manage database configuration
    unless can?(:manage, @team)
      redirect_to account_team_path(@team), 
        alert: "You don't have permission to manage database configuration."
    end
  end
  
  def config_params
    params.require(:team_database_config).permit(
      :database_mode,
      :supabase_url,
      :supabase_service_key,
      :supabase_anon_key,
      :notes,
      export_format_preferences: {}
    )
  end
end