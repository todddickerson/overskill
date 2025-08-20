# frozen_string_literal: true

class MigrateVersionsToR2Job < ApplicationJob
  queue_as :default
  
  # Prevent duplicate jobs from running simultaneously
  # include Lockable  # Uncomment if Lockable concern exists
  
  class MigrationError < StandardError; end
  
  def perform(app_ids: nil, batch_size: 20, min_snapshot_size: 10.kilobytes, dry_run: false)
    Rails.logger.info "[MigrateVersionsToR2Job] Starting version snapshot migration - dry_run: #{dry_run}"
    
    # Safety check - ensure R2 is configured
    validate_r2_configuration!
    
    # Build the base scope for versions with snapshots
    scope = build_migration_scope(app_ids, min_snapshot_size)
    
    if scope.empty?
      Rails.logger.info "[MigrateVersionsToR2Job] No version snapshots to migrate"
      return { status: :no_snapshots, message: "No version snapshots found matching migration criteria" }
    end
    
    Rails.logger.info "[MigrateVersionsToR2Job] Found #{scope.count} version snapshots to migrate"
    
    if dry_run
      return perform_dry_run(scope)
    end
    
    # Perform actual migration
    perform_migration(scope, batch_size)
  end
  
  private
  
  def validate_r2_configuration!
    missing = []
    missing << 'CLOUDFLARE_ACCOUNT_ID' if ENV['CLOUDFLARE_ACCOUNT_ID'].blank?
    missing << 'CLOUDFLARE_API_TOKEN' if ENV['CLOUDFLARE_API_TOKEN'].blank?
    missing << 'CLOUDFLARE_R2_BUCKET_DB_FILES' if ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'].blank?
    
    if missing.any?
      error_msg = "Missing R2 configuration: #{missing.join(', ')}"
      Rails.logger.error "[MigrateVersionsToR2Job] #{error_msg}"
      raise MigrationError, error_msg
    end
  end
  
  def build_migration_scope(app_ids, min_snapshot_size)
    base_scope = AppVersion.where(storage_strategy: 'database')
                          .where('files_snapshot IS NOT NULL')
    
    # Filter by app_ids if specified
    if app_ids.present?
      base_scope = base_scope.where(app_id: app_ids)
    end
    
    # Filter by minimum snapshot size if specified
    if min_snapshot_size > 0
      base_scope = base_scope.where("LENGTH(files_snapshot) > ?", min_snapshot_size)
    end
    
    # Order by snapshot size descending (approximate via LENGTH)
    base_scope.order("LENGTH(files_snapshot) DESC")
  end
  
  def perform_dry_run(scope)
    Rails.logger.info "[MigrateVersionsToR2Job] Performing dry run analysis"
    
    total_versions = scope.count
    
    # Calculate approximate sizes
    snapshot_sizes = scope.pluck(:files_snapshot)
                          .compact
                          .map(&:bytesize)
    
    total_size = snapshot_sizes.sum
    
    breakdown_by_size = {
      small: snapshot_sizes.count { |size| size < 10.kilobytes },
      medium: snapshot_sizes.count { |size| size >= 10.kilobytes && size < 100.kilobytes },
      large: snapshot_sizes.count { |size| size >= 100.kilobytes }
    }
    
    breakdown_by_app = scope.joins(:app)
                            .group('apps.name')
                            .group('apps.id')
                            .count
                            .transform_keys { |name, id| "#{name} (ID: #{id})" }
    
    estimated_r2_cost = (total_size / 1.gigabyte.to_f) * 0.015 # $0.015/GB/month
    estimated_db_savings = (total_size / 1.gigabyte.to_f) * 2.0 # ~$2/GB/month database cost
    
    result = {
      status: :dry_run_complete,
      total_versions: total_versions,
      total_size_bytes: total_size,
      total_size_mb: (total_size / 1.megabyte.to_f).round(2),
      breakdown_by_size: breakdown_by_size,
      breakdown_by_app: breakdown_by_app,
      average_snapshot_size_kb: snapshot_sizes.empty? ? 0 : (total_size / snapshot_sizes.size / 1.kilobyte.to_f).round(2),
      cost_analysis: {
        estimated_monthly_r2_cost: estimated_r2_cost.round(4),
        estimated_monthly_db_savings: estimated_db_savings.round(2),
        net_monthly_savings: (estimated_db_savings - estimated_r2_cost).round(2)
      },
      recommendation: generate_recommendation(total_versions, total_size, breakdown_by_size)
    }
    
    Rails.logger.info "[MigrateVersionsToR2Job] Dry run complete: #{result}"
    result
  end
  
  def perform_migration(scope, batch_size)
    Rails.logger.info "[MigrateVersionsToR2Job] Starting actual migration"
    
    migration_stats = {
      total_versions: scope.count,
      processed: 0,
      successful: 0,
      failed: 0,
      total_size_migrated: 0,
      errors: [],
      started_at: Time.current
    }
    
    scope.find_in_batches(batch_size: batch_size) do |batch|
      migrate_batch(batch, migration_stats)
      
      # Rate limiting - brief pause between batches
      sleep(1) if batch_size > 10
    end
    
    migration_stats[:completed_at] = Time.current
    migration_stats[:duration_seconds] = migration_stats[:completed_at] - migration_stats[:started_at]
    
    Rails.logger.info "[MigrateVersionsToR2Job] Migration complete: #{migration_stats}"
    migration_stats.merge(status: :migration_complete)
  end
  
  def migrate_batch(versions, stats)
    Rails.logger.debug "[MigrateVersionsToR2Job] Processing batch of #{versions.size} versions"
    
    versions.each do |version|
      begin
        snapshot_size = version.files_snapshot&.bytesize || 0
        
        if version.migrate_snapshot_to_r2!
          stats[:successful] += 1
          stats[:total_size_migrated] += snapshot_size
        else
          stats[:failed] += 1
          stats[:errors] << "Failed to migrate version #{version.id} snapshot: unknown error"
        end
      rescue => e
        stats[:failed] += 1
        error_msg = "Failed to migrate version #{version.id} snapshot: #{e.message}"
        stats[:errors] << error_msg
        Rails.logger.error "[MigrateVersionsToR2Job] #{error_msg}"
      ensure
        stats[:processed] += 1
      end
    end
    
    Rails.logger.info "[MigrateVersionsToR2Job] Batch progress: #{stats[:processed]}/#{stats[:total_versions]} versions"
  end
  
  def generate_recommendation(total_versions, total_size, breakdown)
    if total_size < 5.megabytes
      "Small dataset - version snapshot migration may not provide significant benefits"
    elsif breakdown[:large] > breakdown[:small] + breakdown[:medium]
      "Excellent candidate for migration - many large snapshots will benefit from R2 storage"
    elsif total_versions > 500
      "High version count - migration will reduce database bloat significantly"
    else
      "Standard migration candidate - proceed with version snapshot migration"
    end
  end
end