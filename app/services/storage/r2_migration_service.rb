# frozen_string_literal: true

module Storage
  class R2MigrationService
    
    class MigrationError < StandardError; end
    
    def self.perform_full_migration(app_ids: nil, dry_run: true)
      new.perform_full_migration(app_ids: app_ids, dry_run: dry_run)
    end
    
    def self.rollback_to_database(app_ids: nil, dry_run: true)
      new.rollback_to_database(app_ids: app_ids, dry_run: dry_run)
    end
    
    def self.cleanup_hybrid_files
      new.cleanup_hybrid_files
    end

    def initialize
      @results = {
        files: {},
        versions: {},
        version_files: {},
        started_at: Time.current
      }
    end

    def perform_full_migration(app_ids: nil, dry_run: true)
      Rails.logger.info "[R2MigrationService] Starting full migration - apps: #{app_ids || 'all'}, dry_run: #{dry_run}"
      
      validate_r2_configuration!
      
      # Phase 1: Migrate AppFiles (most impact)
      @results[:files] = migrate_app_files(app_ids: app_ids, dry_run: dry_run)
      
      # Phase 2: Migrate AppVersion snapshots
      @results[:versions] = migrate_version_snapshots(app_ids: app_ids, dry_run: dry_run)
      
      # Phase 3: Migrate AppVersionFile content (if enabled)
      if ENV['MIGRATE_VERSION_FILES'] == 'true'
        @results[:version_files] = migrate_version_files(app_ids: app_ids, dry_run: dry_run)
      end
      
      @results[:completed_at] = Time.current
      @results[:duration_seconds] = @results[:completed_at] - @results[:started_at]
      @results[:status] = determine_overall_status
      
      generate_migration_report
    end
    
    def rollback_to_database(app_ids: nil, dry_run: true)
      Rails.logger.info "[R2MigrationService] Starting rollback to database - apps: #{app_ids || 'all'}, dry_run: #{dry_run}"
      
      rollback_results = {
        started_at: Time.current,
        files_rollback: {},
        versions_rollback: {},
        version_files_rollback: {}
      }
      
      unless dry_run
        # Rollback AppFiles
        rollback_results[:files_rollback] = rollback_app_files(app_ids)
        
        # Rollback AppVersion snapshots  
        rollback_results[:versions_rollback] = rollback_version_snapshots(app_ids)
        
        # Rollback AppVersionFiles
        rollback_results[:version_files_rollback] = rollback_version_files(app_ids)
      else
        rollback_results = analyze_rollback_impact(app_ids)
      end
      
      rollback_results[:completed_at] = Time.current
      rollback_results[:duration_seconds] = rollback_results[:completed_at] - rollback_results[:started_at]
      rollback_results[:status] = :rollback_complete
      
      Rails.logger.info "[R2MigrationService] Rollback complete: #{rollback_results}"
      rollback_results
    end
    
    def cleanup_hybrid_files
      Rails.logger.info "[R2MigrationService] Starting hybrid file cleanup"
      
      cleanup_stats = {
        started_at: Time.current,
        files_cleaned: 0,
        versions_cleaned: 0,
        version_files_cleaned: 0,
        space_freed_bytes: 0,
        errors: []
      }
      
      # Clean up AppFiles in hybrid mode (move to R2-only)
      AppFile.where(storage_location: 'hybrid').find_each do |file|
        begin
          if file.verify_r2_content && file.migrate_to_r2_only!
            cleanup_stats[:files_cleaned] += 1
            cleanup_stats[:space_freed_bytes] += file.size_bytes || 0
          end
        rescue => e
          cleanup_stats[:errors] << "Failed to clean AppFile #{file.id}: #{e.message}"
        end
      end
      
      # Clean up AppVersions in hybrid mode
      AppVersion.where(storage_strategy: 'hybrid').find_each do |version|
        begin
          if version.verify_r2_snapshot && version.migrate_snapshot_to_r2_only!
            cleanup_stats[:versions_cleaned] += 1
            cleanup_stats[:space_freed_bytes] += version.snapshot_size_bytes
          end
        rescue => e
          cleanup_stats[:errors] << "Failed to clean AppVersion #{version.id}: #{e.message}"
        end
      end
      
      # Clean up AppVersionFiles with both database and R2 content
      AppVersionFile.hybrid.find_each do |version_file|
        begin
          if version_file.verify_r2_content && version_file.migrate_to_r2_only!
            cleanup_stats[:version_files_cleaned] += 1
            cleanup_stats[:space_freed_bytes] += version_file.content_size_bytes
          end
        rescue => e
          cleanup_stats[:errors] << "Failed to clean AppVersionFile #{version_file.id}: #{e.message}"
        end
      end
      
      cleanup_stats[:completed_at] = Time.current
      cleanup_stats[:space_freed_mb] = (cleanup_stats[:space_freed_bytes] / 1.megabyte.to_f).round(2)
      
      Rails.logger.info "[R2MigrationService] Cleanup complete: #{cleanup_stats}"
      cleanup_stats
    end

    private

    def validate_r2_configuration!
      missing = []
      missing << 'CLOUDFLARE_ACCOUNT_ID' if ENV['CLOUDFLARE_ACCOUNT_ID'].blank?
      missing << 'CLOUDFLARE_API_TOKEN' if ENV['CLOUDFLARE_API_TOKEN'].blank?
      missing << 'CLOUDFLARE_R2_BUCKET_DB_FILES' if ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'].blank?
      
      if missing.any?
        error_msg = "Missing R2 configuration: #{missing.join(', ')}"
        Rails.logger.error "[R2MigrationService] #{error_msg}"
        raise MigrationError, error_msg
      end
    end

    def migrate_app_files(app_ids: nil, dry_run: true)
      Rails.logger.info "[R2MigrationService] Migrating AppFiles"
      
      # Use conservative strategy by default
      MigrateFilesToR2Job.perform_now(
        app_ids: app_ids,
        batch_size: 25,
        strategy: :conservative,
        dry_run: dry_run
      )
    end

    def migrate_version_snapshots(app_ids: nil, dry_run: true)
      Rails.logger.info "[R2MigrationService] Migrating Version Snapshots"
      
      MigrateVersionsToR2Job.perform_now(
        app_ids: app_ids,
        batch_size: 20,
        min_snapshot_size: 10.kilobytes,
        dry_run: dry_run
      )
    end

    def migrate_version_files(app_ids: nil, dry_run: true)
      Rails.logger.info "[R2MigrationService] Migrating Version Files"
      
      # This is a more intensive operation, so smaller batches
      scope = AppVersionFile.migrable_to_r2
      scope = scope.joins(:app_version).where(app_versions: { app_id: app_ids }) if app_ids.present?
      
      if dry_run
        {
          status: :dry_run_complete,
          total_version_files: scope.count,
          estimated_size_bytes: scope.joins(:app_file).sum('LENGTH(COALESCE(app_version_files.content, app_files.content))'),
          message: "Version file migration available but not run by default"
        }
      else
        stats = { processed: 0, successful: 0, failed: 0, errors: [] }
        
        scope.find_in_batches(batch_size: 15) do |batch|
          batch.each do |version_file|
            begin
              if version_file.migrate_to_r2!
                stats[:successful] += 1
              else
                stats[:failed] += 1
              end
            rescue => e
              stats[:failed] += 1
              stats[:errors] << "AppVersionFile #{version_file.id}: #{e.message}"
            ensure
              stats[:processed] += 1
            end
          end
          
          sleep(1) # Rate limiting
        end
        
        stats.merge(status: :migration_complete)
      end
    end

    def rollback_app_files(app_ids)
      Rails.logger.info "[R2MigrationService] Rolling back AppFiles"
      
      scope = AppFile.where(storage_location: ['r2', 'hybrid'])
      scope = scope.where(app_id: app_ids) if app_ids.present?
      
      stats = { processed: 0, successful: 0, failed: 0, errors: [] }
      
      scope.find_each do |file|
        begin
          if file.rollback_to_database!
            stats[:successful] += 1
          else
            stats[:failed] += 1
          end
        rescue => e
          stats[:failed] += 1
          stats[:errors] << "AppFile #{file.id}: #{e.message}"
        ensure
          stats[:processed] += 1
        end
      end
      
      stats
    end

    def rollback_version_snapshots(app_ids)
      Rails.logger.info "[R2MigrationService] Rolling back Version Snapshots"
      
      scope = AppVersion.where(storage_strategy: ['r2', 'hybrid'])
      scope = scope.where(app_id: app_ids) if app_ids.present?
      
      stats = { processed: 0, successful: 0, failed: 0, errors: [] }
      
      scope.find_each do |version|
        begin
          if version.rollback_snapshot_to_database!
            stats[:successful] += 1
          else
            stats[:failed] += 1
          end
        rescue => e
          stats[:failed] += 1
          stats[:errors] << "AppVersion #{version.id}: #{e.message}"
        ensure
          stats[:processed] += 1
        end
      end
      
      stats
    end

    def rollback_version_files(app_ids)
      Rails.logger.info "[R2MigrationService] Rolling back Version Files"
      
      scope = AppVersionFile.where('r2_content_key IS NOT NULL')
      scope = scope.joins(:app_version).where(app_versions: { app_id: app_ids }) if app_ids.present?
      
      stats = { processed: 0, successful: 0, failed: 0, errors: [] }
      
      scope.find_each do |version_file|
        begin
          if version_file.rollback_to_database!
            stats[:successful] += 1
          else
            stats[:failed] += 1
          end
        rescue => e
          stats[:failed] += 1
          stats[:errors] << "AppVersionFile #{version_file.id}: #{e.message}"
        ensure
          stats[:processed] += 1
        end
      end
      
      stats
    end

    def analyze_rollback_impact(app_ids)
      scope_files = AppFile.in_r2
      scope_versions = AppVersion.with_r2_snapshots
      scope_version_files = AppVersionFile.in_r2
      
      if app_ids.present?
        scope_files = scope_files.where(app_id: app_ids)
        scope_versions = scope_versions.where(app_id: app_ids)
        scope_version_files = scope_version_files.joins(:app_version).where(app_versions: { app_id: app_ids })
      end
      
      {
        files_to_rollback: scope_files.count,
        versions_to_rollback: scope_versions.count,
        version_files_to_rollback: scope_version_files.count,
        estimated_db_size_increase_bytes: calculate_rollback_size(scope_files, scope_versions, scope_version_files)
      }
    end

    def calculate_rollback_size(files_scope, versions_scope, version_files_scope)
      files_size = files_scope.sum(:size_bytes) || 0
      versions_size = versions_scope.sum do |version|
        version.snapshot_size_bytes
      end
      version_files_size = version_files_scope.sum do |vf|
        vf.content_size_bytes
      end
      
      files_size + versions_size + version_files_size
    end

    def determine_overall_status
      statuses = [@results[:files][:status], @results[:versions][:status], @results[:version_files][:status]].compact
      
      if statuses.all? { |s| s.to_s.include?('complete') }
        :migration_successful
      elsif statuses.any? { |s| s.to_s.include?('error') }
        :migration_with_errors
      else
        :migration_partial
      end
    end

    def generate_migration_report
      Rails.logger.info "[R2MigrationService] Generating migration report"
      
      report = {
        summary: @results,
        recommendations: generate_recommendations,
        next_steps: generate_next_steps,
        cost_impact: calculate_cost_impact
      }
      
      Rails.logger.info "[R2MigrationService] Migration report: #{report}"
      report
    end

    def generate_recommendations
      recommendations = []
      
      if @results[:files][:successful] > 0
        recommendations << "Successfully migrated #{@results[:files][:successful]} files to R2. Consider running cleanup to remove database duplicates."
      end
      
      if @results[:files][:failed] > 0
        recommendations << "#{@results[:files][:failed]} file migrations failed. Review error logs and retry with smaller batch sizes."
      end
      
      if @results[:versions][:successful] > 0
        recommendations << "Version snapshots migrated successfully. Monitor R2 access patterns to optimize caching."
      end
      
      recommendations << "Run Storage::StorageAnalyticsService.generate_migration_report to see detailed analytics."
      
      recommendations
    end

    def generate_next_steps
      steps = []
      
      steps << "Monitor application performance for any R2 access issues"
      steps << "Run hybrid cleanup job after confirming migration stability"
      steps << "Update backup procedures to include R2 content"
      steps << "Consider enabling version file migration if needed"
      
      steps
    end

    def calculate_cost_impact
      # This would integrate with the StorageAnalyticsService
      {
        estimated_monthly_savings: "See StorageAnalyticsService for detailed cost analysis",
        database_reduction_percentage: "Varies by migration scope"
      }
    end
  end
end