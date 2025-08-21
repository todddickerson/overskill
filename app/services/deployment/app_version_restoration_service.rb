# App Version Restoration Service
# Restores an app to a previous version state using GitHub tags or AppVersion snapshots
# Supports both GitHub tag-based and database snapshot-based restoration

class Deployment::AppVersionRestorationService
  def initialize(app)
    @app = app
    @logger = Rails.logger
  end
  
  # Restore app to a specific version
  def restore_to_version(app_version, options = {})
    @logger.info "[AppVersionRestoration] Starting restoration to version #{app_version.version_number}"
    
    # Determine restoration method based on available data
    if app_version.github_tag.present? && options[:prefer_github] != false
      restore_from_github_tag(app_version, options)
    elsif app_version.files_snapshot.present?
      restore_from_snapshot(app_version, options)
    elsif app_version.app_version_files.exists?
      restore_from_version_files(app_version, options)
    else
      { 
        success: false, 
        error: "No restoration data available for version #{app_version.version_number}" 
      }
    end
  end
  
  # List all restorable versions for the app
  def list_restorable_versions
    versions = @app.app_versions.order(created_at: :desc)
    
    restorable = versions.map do |version|
      {
        id: version.id,
        version_number: version.version_number,
        created_at: version.created_at,
        display_name: version.formatted_display_name,
        changelog: version.changelog,
        restorable: can_restore?(version),
        restoration_methods: available_restoration_methods(version),
        github_tag: version.github_tag,
        files_count: version.app_version_files.count
      }
    end
    
    { success: true, versions: restorable }
  end
  
  private
  
  # Restore from GitHub tag (most reliable)
  def restore_from_github_tag(app_version, options)
    @logger.info "[AppVersionRestoration] Restoring from GitHub tag: #{app_version.github_tag}"
    
    begin
      tagging_service = Deployment::GithubVersionTaggingService.new(app_version)
      result = tagging_service.restore_from_tag
      
      if result[:success]
        # Deploy the restored version if requested
        if options[:auto_deploy]
          deploy_restored_version(result[:version], options[:environment] || 'preview')
        end
        
        @logger.info "[AppVersionRestoration] ✅ Successfully restored from GitHub tag"
        result
      else
        @logger.error "[AppVersionRestoration] GitHub restoration failed: #{result[:error]}"
        # Fallback to snapshot if available
        if app_version.files_snapshot.present?
          @logger.info "[AppVersionRestoration] Falling back to snapshot restoration"
          restore_from_snapshot(app_version, options)
        else
          result
        end
      end
    rescue => e
      @logger.error "[AppVersionRestoration] GitHub restoration error: #{e.message}"
      # Fallback to snapshot
      if app_version.files_snapshot.present?
        restore_from_snapshot(app_version, options)
      else
        { success: false, error: e.message }
      end
    end
  end
  
  # Restore from database/R2 snapshot
  def restore_from_snapshot(app_version, options)
    @logger.info "[AppVersionRestoration] Restoring from snapshot"
    
    begin
      snapshot = JSON.parse(app_version.files_snapshot)
      
      # Create new version for restoration
      restored_version = @app.app_versions.create!(
        version_number: generate_restoration_version_number(app_version),
        team: @app.team,
        user: app_version.user,
        changelog: "Restored from version #{app_version.version_number}",
        deployed: false,
        external_commit: false,
        environment: 'preview'
      )
      
      restored_count = 0
      failed_files = []
      
      snapshot.each do |file_data|
        begin
          # Find or create AppFile
          app_file = @app.app_files.find_or_initialize_by(path: file_data['path'])
          app_file.content = file_data['content']
          app_file.team = @app.team
          app_file.file_type = file_data['file_type'] || determine_file_type(file_data['path'])
          
          if app_file.save
            # Track change
            restored_version.app_version_files.create!(
              app_file: app_file,
              action: app_file.previously_new_record? ? 'created' : 'updated'
            )
            restored_count += 1
          else
            failed_files << file_data['path']
          end
        rescue => e
          @logger.error "[AppVersionRestoration] Failed to restore file #{file_data['path']}: #{e.message}"
          failed_files << file_data['path']
        end
      end
      
      # Update restored version with new snapshot
      restored_version.update!(
        files_snapshot: @app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json
      )
      
      # Generate display name
      restored_version.generate_display_name!
      
      # Sync to GitHub if repository exists
      if @app.repository_name.present? && options[:sync_to_github] != false
        sync_to_github(restored_version)
      end
      
      # Deploy if requested
      if options[:auto_deploy]
        deploy_restored_version(restored_version, options[:environment] || 'preview')
      end
      
      if failed_files.empty?
        @logger.info "[AppVersionRestoration] ✅ Successfully restored #{restored_count} files from snapshot"
        { 
          success: true, 
          restored_count: restored_count,
          version: restored_version,
          message: "Successfully restored #{restored_count} files from version #{app_version.version_number}"
        }
      else
        @logger.warn "[AppVersionRestoration] ⚠️ Partially restored. Failed files: #{failed_files.join(', ')}"
        { 
          success: false, 
          restored_count: restored_count,
          failed_files: failed_files,
          version: restored_version,
          error: "Partially restored. #{failed_files.size} files failed."
        }
      end
    rescue => e
      @logger.error "[AppVersionRestoration] Snapshot restoration failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Restore from AppVersionFile records
  def restore_from_version_files(app_version, options)
    @logger.info "[AppVersionRestoration] Restoring from version file records"
    
    begin
      # Create new version for restoration
      restored_version = @app.app_versions.create!(
        version_number: generate_restoration_version_number(app_version),
        team: @app.team,
        user: app_version.user,
        changelog: "Restored from version #{app_version.version_number}",
        deployed: false,
        external_commit: false,
        environment: 'preview'
      )
      
      restored_count = 0
      
      # Apply version files
      app_version.app_version_files.includes(:app_file).each do |version_file|
        case version_file.action
        when 'created', 'updated', 'unchanged'
          if version_file.app_file.present?
            # Update the app file content
            version_file.app_file.update!(content: version_file.content)
            restored_count += 1
          end
        when 'deleted'
          # For deleted files, we need to remove them
          if version_file.app_file.present?
            version_file.app_file.destroy
          end
        end
      end
      
      # Create snapshot for the restored version
      restored_version.update!(
        files_snapshot: @app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json
      )
      
      # Generate display name
      restored_version.generate_display_name!
      
      # Sync to GitHub if repository exists
      if @app.repository_name.present? && options[:sync_to_github] != false
        sync_to_github(restored_version)
      end
      
      # Deploy if requested
      if options[:auto_deploy]
        deploy_restored_version(restored_version, options[:environment] || 'preview')
      end
      
      @logger.info "[AppVersionRestoration] ✅ Successfully restored #{restored_count} files from version files"
      { 
        success: true, 
        restored_count: restored_count,
        version: restored_version,
        message: "Successfully restored from version #{app_version.version_number}"
      }
    rescue => e
      @logger.error "[AppVersionRestoration] Version files restoration failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
  
  # Sync restored version to GitHub
  def sync_to_github(restored_version)
    @logger.info "[AppVersionRestoration] Syncing restored version to GitHub"
    
    begin
      github_service = Deployment::GithubRepositoryService.new(@app)
      file_structure = @app.app_files.to_h { |file| [file.path, file.content] }
      
      sync_result = github_service.push_file_structure(file_structure)
      
      if sync_result[:success]
        @logger.info "[AppVersionRestoration] ✅ Synced to GitHub successfully"
        
        # Create GitHub tag for the restored version
        tagging_service = Deployment::GithubVersionTaggingService.new(restored_version)
        tag_result = tagging_service.create_version_tag
        
        if tag_result[:success]
          @logger.info "[AppVersionRestoration] Created GitHub tag: #{tag_result[:tag_name]}"
        end
      else
        @logger.warn "[AppVersionRestoration] GitHub sync failed: #{sync_result[:error]}"
      end
    rescue => e
      @logger.error "[AppVersionRestoration] GitHub sync error: #{e.message}"
    end
  end
  
  # Deploy the restored version
  def deploy_restored_version(version, environment)
    @logger.info "[AppVersionRestoration] Deploying restored version to #{environment}"
    
    begin
      DeployAppJob.perform_later(@app.id, environment)
      @logger.info "[AppVersionRestoration] Deployment job queued"
    rescue => e
      @logger.error "[AppVersionRestoration] Failed to queue deployment: #{e.message}"
    end
  end
  
  # Check if a version can be restored
  def can_restore?(app_version)
    app_version.github_tag.present? || 
    app_version.files_snapshot.present? || 
    app_version.app_version_files.exists?
  end
  
  # List available restoration methods for a version
  def available_restoration_methods(app_version)
    methods = []
    methods << 'github' if app_version.github_tag.present?
    methods << 'snapshot' if app_version.files_snapshot.present?
    methods << 'version_files' if app_version.app_version_files.exists?
    methods
  end
  
  # Generate version number for restored version
  def generate_restoration_version_number(original_version)
    base = original_version.version_number.gsub('v', '').gsub('-restored', '')
    timestamp = Time.current.strftime('%Y%m%d%H%M')
    "#{base}-restored-#{timestamp}"
  end
  
  # Determine file type from extension
  def determine_file_type(path)
    case ::File.extname(path).downcase
    when '.tsx', '.ts' then 'typescript'
    when '.jsx', '.js' then 'javascript'
    when '.css', '.scss', '.sass' then 'css'
    when '.html' then 'html'
    when '.json' then 'json'
    when '.md' then 'markdown'
    when '.yml', '.yaml' then 'yaml'
    else 'text'
    end
  end
end