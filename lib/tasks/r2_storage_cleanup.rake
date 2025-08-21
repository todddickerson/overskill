# Rake tasks for R2 storage cleanup and migration
# Usage:
#   bin/rails r2:migrate_files               # Migrate eligible files to R2
#   bin/rails r2:cleanup_database_content    # Clear database content for R2-stored files
#   bin/rails r2:verify_and_cleanup          # Verify R2 content then cleanup database
#   bin/rails r2:stats                       # Show storage statistics

namespace :r2 do
  desc "Migrate eligible files from database to R2 storage"
  task migrate_files: :environment do
    puts "Starting R2 migration for eligible files..."
    
    # Find files that should be in R2 but aren't yet
    eligible_files = AppFile
      .where(storage_location: 'database')
      .where('size_bytes >= ?', 1.kilobyte)
      .where(r2_object_key: nil)
    
    total_count = eligible_files.count
    success_count = 0
    failed_count = 0
    
    puts "Found #{total_count} eligible files for R2 migration"
    
    eligible_files.find_each.with_index do |file, index|
      print "\rProcessing file #{index + 1}/#{total_count} (#{file.path})..."
      
      if file.migrate_to_r2!
        success_count += 1
      else
        failed_count += 1
        puts "\n  Failed: #{file.path} (App: #{file.app_id})"
      end
    end
    
    puts "\n\nMigration complete:"
    puts "  Successful: #{success_count}"
    puts "  Failed: #{failed_count}"
    puts "  Total processed: #{total_count}"
  end
  
  desc "Clear database content for files already stored in R2"
  task cleanup_database_content: :environment do
    puts "Starting database content cleanup for R2-stored files..."
    
    # Find files that are in R2 but still have database content
    files_to_clean = AppFile
      .where(storage_location: ['r2', 'hybrid'])
      .where.not(r2_object_key: nil)
      .where.not(content: nil)
    
    total_count = files_to_clean.count
    total_size = files_to_clean.sum(:size_bytes)
    
    puts "Found #{total_count} files with redundant database content"
    puts "Total database space to reclaim: #{(total_size / 1.megabyte.to_f).round(2)} MB"
    
    print "\nDo you want to proceed with cleanup? (y/N): "
    response = STDIN.gets.chomp.downcase
    
    unless response == 'y'
      puts "Cleanup cancelled"
      exit
    end
    
    cleaned_count = 0
    failed_count = 0
    
    files_to_clean.find_each.with_index do |file, index|
      print "\rCleaning file #{index + 1}/#{total_count}..."
      
      begin
        # For R2-only files, clear database content
        if file.storage_location == 'r2'
          file.update_columns(content: nil)
          cleaned_count += 1
        elsif file.storage_location == 'hybrid'
          # For hybrid, optionally convert to R2-only after verification
          if file.verify_r2_content
            file.update_columns(
              content: nil,
              storage_location: 'r2'
            )
            cleaned_count += 1
          else
            puts "\n  Verification failed for hybrid file: #{file.path}"
            failed_count += 1
          end
        end
      rescue => e
        puts "\n  Error cleaning file #{file.id}: #{e.message}"
        failed_count += 1
      end
    end
    
    puts "\n\nCleanup complete:"
    puts "  Cleaned: #{cleaned_count}"
    puts "  Failed: #{failed_count}"
    puts "  Space reclaimed: ~#{(total_size / 1.megabyte.to_f).round(2)} MB"
  end
  
  desc "Verify R2 content matches database then cleanup"
  task verify_and_cleanup: :environment do
    puts "Starting R2 content verification and cleanup..."
    
    files_to_verify = AppFile
      .where(storage_location: ['r2', 'hybrid'])
      .where.not(r2_object_key: nil)
      .where.not(content: nil)
    
    total_count = files_to_verify.count
    verified_count = 0
    cleaned_count = 0
    failed_count = 0
    
    puts "Verifying #{total_count} files..."
    
    files_to_verify.find_each.with_index do |file, index|
      print "\rVerifying file #{index + 1}/#{total_count}..."
      
      begin
        if file.verify_r2_content
          verified_count += 1
          
          # Clear database content after successful verification
          if file.storage_location == 'r2' || ENV['FORCE_R2_ONLY'] == 'true'
            file.update_columns(
              content: nil,
              storage_location: 'r2'
            )
            cleaned_count += 1
          end
        else
          failed_count += 1
          puts "\n  Verification failed: #{file.path} (App: #{file.app_id})"
          
          # Optionally re-sync to R2
          if ENV['RESYNC_FAILED'] == 'true'
            puts "    Attempting re-sync..."
            if file.migrate_to_r2!
              puts "    Re-sync successful"
            else
              puts "    Re-sync failed"
            end
          end
        end
      rescue => e
        puts "\n  Error verifying file #{file.id}: #{e.message}"
        failed_count += 1
      end
    end
    
    puts "\n\nVerification complete:"
    puts "  Verified: #{verified_count}"
    puts "  Cleaned: #{cleaned_count}"
    puts "  Failed: #{failed_count}"
  end
  
  desc "Show R2 storage statistics"
  task stats: :environment do
    puts "\n=== R2 Storage Statistics ==="
    puts
    
    # Overall stats
    total_files = AppFile.count
    total_size = AppFile.sum(:size_bytes)
    
    # By storage location
    db_only = AppFile.where(storage_location: 'database')
    r2_only = AppFile.where(storage_location: 'r2')
    hybrid = AppFile.where(storage_location: 'hybrid')
    
    puts "Total Files: #{total_files}"
    puts "Total Size: #{(total_size / 1.megabyte.to_f).round(2)} MB"
    puts
    
    puts "Storage Distribution:"
    puts "  Database only: #{db_only.count} files (#{(db_only.sum(:size_bytes) / 1.megabyte.to_f).round(2)} MB)"
    puts "  R2 only: #{r2_only.count} files (#{(r2_only.sum(:size_bytes) / 1.megabyte.to_f).round(2)} MB)"
    puts "  Hybrid: #{hybrid.count} files (#{(hybrid.sum(:size_bytes) / 1.megabyte.to_f).round(2)} MB)"
    puts
    
    # Files eligible for migration
    eligible = AppFile
      .where(storage_location: 'database')
      .where('size_bytes >= ?', 1.kilobyte)
      .where(r2_object_key: nil)
    
    puts "Eligible for R2 migration: #{eligible.count} files"
    puts "Potential space savings: #{(eligible.sum(:size_bytes) / 1.megabyte.to_f).round(2)} MB"
    puts
    
    # Files with redundant storage
    redundant = AppFile
      .where(storage_location: ['r2', 'hybrid'])
      .where.not(r2_object_key: nil)
      .where.not(content: nil)
    
    puts "Files with redundant database content: #{redundant.count}"
    puts "Database space that can be reclaimed: #{(redundant.sum(:size_bytes) / 1.megabyte.to_f).round(2)} MB"
    puts
    
    # Recent sync status
    recent_syncs = AppFile
      .where.not(r2_sync_status: nil)
      .group(:r2_sync_status)
      .count
    
    if recent_syncs.any?
      puts "Recent R2 Sync Status:"
      recent_syncs.each do |status, count|
        puts "  #{status}: #{count}"
      end
      puts
    end
    
    # App-level stats
    apps_with_r2 = App.joins(:app_files)
      .where(app_files: { storage_location: ['r2', 'hybrid'] })
      .distinct
      .count
    
    puts "Apps using R2 storage: #{apps_with_r2}/#{App.count}"
    
    # Show top apps by storage
    puts "\nTop 5 Apps by Storage:"
    App.joins(:app_files)
      .group('apps.id', 'apps.name')
      .sum('app_files.size_bytes')
      .sort_by { |_, size| -size }
      .first(5)
      .each do |app_info, size|
        app_id, app_name = app_info
        puts "  #{app_name} (ID: #{app_id}): #{(size / 1.megabyte.to_f).round(2)} MB"
      end
  end
  
  desc "Queue R2 sync for recent apps"
  task queue_recent_syncs: :environment do
    since = ENV['SINCE'] ? Time.parse(ENV['SINCE']) : 1.hour.ago
    
    puts "Queueing R2 sync for apps created since #{since}..."
    
    apps_to_sync = App.where('created_at > ?', since)
    count = apps_to_sync.count
    
    puts "Found #{count} apps to sync"
    
    apps_to_sync.find_each do |app|
      AppFilesInitializationJob.perform_later(app.id)
      print "."
    end
    
    puts "\nQueued #{count} sync jobs"
  end
end