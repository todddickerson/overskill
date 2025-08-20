# frozen_string_literal: true

module Storage
  class StorageAnalyticsService
    
    def self.generate_migration_report
      new.generate_migration_report
    end

    def self.estimate_storage_savings
      new.estimate_storage_savings
    end

    def generate_migration_report
      database_stats = calculate_database_storage
      r2_stats = calculate_r2_storage
      migration_progress = calculate_migration_percentage
      cost_analysis = estimate_cost_savings

      {
        timestamp: Time.current,
        database_storage: database_stats,
        r2_storage: r2_stats,
        migration_progress: migration_progress,
        cost_analysis: cost_analysis,
        recommendations: generate_recommendations(database_stats, r2_stats)
      }
    end

    def estimate_storage_savings
      total_files = AppFile.count
      total_size = AppFile.sum(:size_bytes) || 0
      
      # Categorize files by size for migration strategy
      small_files = AppFile.where('size_bytes < ?', 1.kilobyte)
      medium_files = AppFile.where('size_bytes >= ? AND size_bytes < ?', 1.kilobyte, 10.kilobytes)
      large_files = AppFile.where('size_bytes >= ?', 10.kilobytes)
      
      small_size = small_files.sum(:size_bytes) || 0
      medium_size = medium_files.sum(:size_bytes) || 0  
      large_size = large_files.sum(:size_bytes) || 0
      
      # Calculate potential savings (assume 80% of medium+ files move to R2)
      database_reduction = (medium_size + large_size) * 0.8
      r2_increase = database_reduction
      
      {
        current_state: {
          total_files: total_files,
          total_size_bytes: total_size,
          total_size_mb: (total_size / 1.megabyte.to_f).round(2),
          breakdown: {
            small_files: { count: small_files.count, size_bytes: small_size, size_mb: (small_size / 1.megabyte.to_f).round(2) },
            medium_files: { count: medium_files.count, size_bytes: medium_size, size_mb: (medium_size / 1.megabyte.to_f).round(2) },
            large_files: { count: large_files.count, size_bytes: large_size, size_mb: (large_size / 1.megabyte.to_f).round(2) }
          }
        },
        projected_savings: {
          database_reduction_bytes: database_reduction,
          database_reduction_mb: (database_reduction / 1.megabyte.to_f).round(2),
          database_reduction_percentage: ((database_reduction / total_size.to_f) * 100).round(1),
          r2_storage_increase_bytes: r2_increase,
          r2_storage_increase_mb: (r2_increase / 1.megabyte.to_f).round(2)
        },
        cost_estimates: estimate_monthly_costs(total_size, database_reduction, r2_increase)
      }
    end

    private

    def calculate_database_storage
      {
        files_in_database: AppFile.where(storage_location: ['database', 'hybrid']).count,
        database_only_files: AppFile.where(storage_location: 'database').count,
        hybrid_files: AppFile.where(storage_location: 'hybrid').count,
        total_database_size_bytes: AppFile.where(storage_location: ['database', 'hybrid']).sum(:size_bytes) || 0,
        average_file_size_bytes: calculate_average_file_size('database'),
        versions_with_snapshots: AppVersion.where("files_snapshot IS NOT NULL").count,
        version_files_in_db: AppVersionFile.where("content IS NOT NULL").count
      }
    end

    def calculate_r2_storage
      {
        files_in_r2: AppFile.where(storage_location: ['r2', 'hybrid']).count,
        r2_only_files: AppFile.where(storage_location: 'r2').count,
        hybrid_files: AppFile.where(storage_location: 'hybrid').count,
        total_r2_size_bytes: AppFile.where(storage_location: ['r2', 'hybrid']).sum(:size_bytes) || 0,
        average_file_size_bytes: calculate_average_file_size('r2'),
        versions_with_r2_snapshots: AppVersion.where("r2_snapshot_key IS NOT NULL").count,
        version_files_in_r2: AppVersionFile.where("r2_content_key IS NOT NULL").count,
        unique_r2_objects: count_unique_r2_objects
      }
    end

    def calculate_migration_percentage
      total_files = AppFile.count
      return 0 if total_files == 0
      
      migrated_files = AppFile.where(storage_location: ['r2', 'hybrid']).count
      percentage = (migrated_files.to_f / total_files * 100).round(1)
      
      {
        total_files: total_files,
        migrated_files: migrated_files,
        percentage_complete: percentage,
        remaining_files: total_files - migrated_files
      }
    end

    def estimate_cost_savings
      total_size = AppFile.sum(:size_bytes) || 0
      database_size = AppFile.where(storage_location: ['database', 'hybrid']).sum(:size_bytes) || 0
      r2_size = AppFile.where(storage_location: ['r2', 'hybrid']).sum(:size_bytes) || 0
      
      estimate_monthly_costs(total_size, total_size - database_size, r2_size)
    end

    def estimate_monthly_costs(total_size, database_reduction, r2_increase)
      # Database cost estimates (vary by provider)
      # Rough estimates: PostgreSQL on cloud providers
      database_cost_per_gb_month = 2.0 # $2/GB/month rough average
      
      # R2 costs
      r2_storage_cost_per_gb_month = 0.015 # $0.015/GB/month
      r2_operations_cost_per_million = 0.36 # $0.36/million write operations
      
      current_database_cost = (total_size / 1.gigabyte.to_f) * database_cost_per_gb_month
      
      projected_database_cost = ((total_size - database_reduction) / 1.gigabyte.to_f) * database_cost_per_gb_month
      projected_r2_cost = (r2_increase / 1.gigabyte.to_f) * r2_storage_cost_per_gb_month
      
      # Add small operations cost (minimal due to caching)
      estimated_monthly_operations = 1000 # Conservative estimate
      operations_cost = (estimated_monthly_operations / 1_000_000.0) * r2_operations_cost_per_million
      
      total_projected_cost = projected_database_cost + projected_r2_cost + operations_cost
      monthly_savings = current_database_cost - total_projected_cost
      
      {
        current_monthly_cost: {
          database: current_database_cost.round(2),
          r2: 0.0,
          total: current_database_cost.round(2)
        },
        projected_monthly_cost: {
          database: projected_database_cost.round(2),
          r2: projected_r2_cost.round(2),
          operations: operations_cost.round(4),
          total: total_projected_cost.round(2)
        },
        monthly_savings: monthly_savings.round(2),
        annual_savings: (monthly_savings * 12).round(2),
        savings_percentage: current_database_cost > 0 ? ((monthly_savings / current_database_cost) * 100).round(1) : 0
      }
    end

    def calculate_average_file_size(storage_type)
      scope = case storage_type
      when 'database'
        AppFile.where(storage_location: ['database', 'hybrid'])
      when 'r2'
        AppFile.where(storage_location: ['r2', 'hybrid'])
      else
        AppFile.all
      end
      
      count = scope.count
      return 0 if count == 0
      
      total_size = scope.sum(:size_bytes) || 0
      (total_size / count.to_f).round(0)
    end

    def count_unique_r2_objects
      # Count unique R2 object keys across all tables
      file_objects = AppFile.where("r2_object_key IS NOT NULL").distinct.count(:r2_object_key)
      version_objects = AppVersion.where("r2_snapshot_key IS NOT NULL").distinct.count(:r2_snapshot_key)
      version_file_objects = AppVersionFile.where("r2_content_key IS NOT NULL").distinct.count(:r2_content_key)
      
      file_objects + version_objects + version_file_objects
    end

    def generate_recommendations(database_stats, r2_stats)
      recommendations = []
      
      total_files = database_stats[:files_in_database] + r2_stats[:files_in_r2]
      
      if database_stats[:database_only_files] > 0
        large_db_files = AppFile.where(storage_location: 'database')
                                .where('size_bytes > ?', 10.kilobytes)
                                .count
        
        if large_db_files > 0
          recommendations << {
            priority: 'high',
            category: 'migration',
            title: "Migrate #{large_db_files} large files to R2",
            description: "Files larger than 10KB should be moved to R2 for optimal performance and cost savings",
            estimated_savings_mb: (AppFile.where(storage_location: 'database')
                                          .where('size_bytes > ?', 10.kilobytes)
                                          .sum(:size_bytes) / 1.megabyte.to_f).round(2)
          }
        end
      end
      
      if r2_stats[:hybrid_files] > 100
        recommendations << {
          priority: 'medium',
          category: 'optimization', 
          title: "Clean up hybrid storage files",
          description: "#{r2_stats[:hybrid_files]} files are stored in both database and R2. Consider moving to R2-only after verification",
          action: "Run cleanup job to remove database content for verified R2 files"
        }
      end
      
      if database_stats[:versions_with_snapshots] > 1000
        recommendations << {
          priority: 'medium',
          category: 'migration',
          title: "Migrate version snapshots to R2",
          description: "#{database_stats[:versions_with_snapshots]} version snapshots could be moved to R2 for better performance",
          estimated_impact: "Significant database size reduction"
        }
      end
      
      recommendations
    end
  end
end