# frozen_string_literal: true

class MigrateFilesToR2Job < ApplicationJob
  queue_as :default

  # Prevent duplicate jobs from running simultaneously
  # include Lockable  # Uncomment if Lockable concern exists

  class MigrationError < StandardError; end

  def perform(app_ids: nil, batch_size: 25, strategy: :conservative, dry_run: false)
    Rails.logger.info "[MigrateFilesToR2Job] Starting migration - strategy: #{strategy}, dry_run: #{dry_run}"

    # Safety check - ensure R2 is configured
    validate_r2_configuration!

    # Build the base scope
    scope = build_migration_scope(app_ids, strategy)

    if scope.empty?
      Rails.logger.info "[MigrateFilesToR2Job] No files to migrate"
      return {status: :no_files, message: "No files found matching migration criteria"}
    end

    Rails.logger.info "[MigrateFilesToR2Job] Found #{scope.count} files to migrate"

    if dry_run
      return perform_dry_run(scope)
    end

    # Perform actual migration
    perform_migration(scope, batch_size)
  end

  private

  def validate_r2_configuration!
    missing = []
    missing << "CLOUDFLARE_ACCOUNT_ID" if ENV["CLOUDFLARE_ACCOUNT_ID"].blank?
    missing << "CLOUDFLARE_API_TOKEN" if ENV["CLOUDFLARE_API_TOKEN"].blank?
    missing << "CLOUDFLARE_R2_BUCKET_DB_FILES" if ENV["CLOUDFLARE_R2_BUCKET_DB_FILES"].blank?

    if missing.any?
      error_msg = "Missing R2 configuration: #{missing.join(", ")}"
      Rails.logger.error "[MigrateFilesToR2Job] #{error_msg}"
      raise MigrationError, error_msg
    end
  end

  def build_migration_scope(app_ids, strategy)
    base_scope = AppFile.where(storage_location: "database")

    # Filter by app_ids if specified
    if app_ids.present?
      base_scope = base_scope.where(app_id: app_ids)
    end

    # Apply strategy-specific filters
    case strategy
    when :conservative
      # Only migrate files larger than 1KB
      base_scope = base_scope.where("size_bytes > ?", 1.kilobyte)
    when :aggressive
      # Migrate files larger than 500 bytes
      base_scope = base_scope.where("size_bytes > ?", 500)
    when :large_only
      # Only migrate files larger than 10KB
      base_scope = base_scope.where("size_bytes > ?", 10.kilobytes)
    when :all
      # Migrate all files
      # No additional filter
    else
      raise MigrationError, "Unknown migration strategy: #{strategy}"
    end

    # Order by size descending to get biggest impact first
    base_scope.order(size_bytes: :desc)
  end

  def perform_dry_run(scope)
    Rails.logger.info "[MigrateFilesToR2Job] Performing dry run analysis"

    total_files = scope.count
    total_size = scope.sum(:size_bytes) || 0

    breakdown_by_size = {
      small: scope.where("size_bytes < ?", 1.kilobyte).count,
      medium: scope.where("size_bytes >= ? AND size_bytes < ?", 1.kilobyte, 10.kilobytes).count,
      large: scope.where("size_bytes >= ?", 10.kilobytes).count
    }

    breakdown_by_app = scope.joins(:app)
      .group("apps.name")
      .group("apps.id")
      .count
      .transform_keys { |name, id| "#{name} (ID: #{id})" }

    estimated_r2_cost = (total_size / 1.gigabyte.to_f) * 0.015 # $0.015/GB/month
    estimated_db_savings = (total_size / 1.gigabyte.to_f) * 2.0 # ~$2/GB/month database cost

    result = {
      status: :dry_run_complete,
      total_files: total_files,
      total_size_bytes: total_size,
      total_size_mb: (total_size / 1.megabyte.to_f).round(2),
      breakdown_by_size: breakdown_by_size,
      breakdown_by_app: breakdown_by_app,
      cost_analysis: {
        estimated_monthly_r2_cost: estimated_r2_cost.round(4),
        estimated_monthly_db_savings: estimated_db_savings.round(2),
        net_monthly_savings: (estimated_db_savings - estimated_r2_cost).round(2)
      },
      recommendation: generate_recommendation(total_files, total_size, breakdown_by_size)
    }

    Rails.logger.info "[MigrateFilesToR2Job] Dry run complete: #{result}"
    result
  end

  def perform_migration(scope, batch_size)
    Rails.logger.info "[MigrateFilesToR2Job] Starting actual migration"

    migration_stats = {
      total_files: scope.count,
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
      sleep(0.5) if batch_size > 10
    end

    migration_stats[:completed_at] = Time.current
    migration_stats[:duration_seconds] = migration_stats[:completed_at] - migration_stats[:started_at]

    Rails.logger.info "[MigrateFilesToR2Job] Migration complete: #{migration_stats}"
    migration_stats.merge(status: :migration_complete)
  end

  def migrate_batch(files, stats)
    Rails.logger.debug "[MigrateFilesToR2Job] Processing batch of #{files.size} files"

    files.each do |file|
      if file.migrate_to_r2!
        stats[:successful] += 1
        stats[:total_size_migrated] += file.size_bytes || 0
      else
        stats[:failed] += 1
        stats[:errors] << "Failed to migrate file #{file.id} (#{file.path}): unknown error"
      end
    rescue => e
      stats[:failed] += 1
      error_msg = "Failed to migrate file #{file.id} (#{file.path}): #{e.message}"
      stats[:errors] << error_msg
      Rails.logger.error "[MigrateFilesToR2Job] #{error_msg}"
    ensure
      stats[:processed] += 1
    end

    Rails.logger.info "[MigrateFilesToR2Job] Batch progress: #{stats[:processed]}/#{stats[:total_files]} files"
  end

  def generate_recommendation(total_files, total_size, breakdown)
    if total_size < 10.megabytes
      "Small dataset - migration may not provide significant benefits"
    elsif breakdown[:large] > breakdown[:small] + breakdown[:medium]
      "Good candidate for migration - many large files will benefit from R2 storage"
    elsif total_files > 1000
      "High file count - migration will reduce database query overhead"
    else
      "Standard migration candidate - proceed with conservative strategy"
    end
  end
end
