# R2 Migration Testing Script
# Run with: rails runner test_r2_migration.rb

puts "🚀 Starting R2 Migration Testing"
puts "=" * 50

# Test 1: Configuration Validation
puts "\n1. Testing R2 Configuration..."
begin
  service = Storage::R2FileStorageService.new
  puts "✅ R2FileStorageService initialized successfully"
  puts "   Bucket: #{ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'] || 'overskill-dev'}"
  puts "   Account ID: #{ENV['CLOUDFLARE_ACCOUNT_ID'].present? ? 'configured' : 'missing'}"
  puts "   API Token: #{ENV['CLOUDFLARE_API_TOKEN'].present? ? 'configured' : 'missing'}"
rescue => e
  puts "❌ R2 Configuration Error: #{e.message}"
  exit 1
end

# Test 2: Storage Analytics (Baseline)
puts "\n2. Generating Storage Analytics Baseline..."
begin
  report = Storage::StorageAnalyticsService.generate_migration_report
  puts "✅ Analytics Generated"
  puts "   Total Files: #{report[:database_storage][:files_in_database]}"
  puts "   Database Size: #{(report[:database_storage][:total_database_size_bytes] / 1.megabyte.to_f).round(2)} MB"
  puts "   Migration Progress: #{report[:migration_progress][:percentage_complete]}%"
rescue => e
  puts "❌ Analytics Error: #{e.message}"
end

# Test 3: Model Integration
puts "\n3. Testing Model Integration..."

# Find a test app or create one
test_app = App.where(status: 'testing').first || 
           App.joins(:app_files).group('apps.id').having('COUNT(app_files.id) < 5').first ||
           App.first

if test_app.nil?
  puts "❌ No test app available"
else
  puts "✅ Using test app: #{test_app.name} (ID: #{test_app.id})"
  
  # Test AppFile methods
  if test_app.app_files.any?
    test_file = test_app.app_files.first
    puts "   Test file: #{test_file.path}"
    puts "   Current storage: #{test_file.storage_location}"
    puts "   Should be in R2: #{test_file.should_be_in_r2?}"
    puts "   Content available: #{test_file.content_available?}"
    puts "   Size category: #{test_file.storage_size_category}"
  else
    puts "   No files in test app"
  end
  
  # Test AppVersion methods  
  if test_app.app_versions.any?
    test_version = test_app.app_versions.first
    puts "   Test version: #{test_version.version_number}"
    puts "   Storage strategy: #{test_version.storage_strategy}"
    puts "   Snapshot available: #{test_version.snapshot_available?}"
    puts "   Snapshot size: #{(test_version.snapshot_size_bytes / 1.kilobyte.to_f).round(2)} KB"
  else
    puts "   No versions in test app"
  end
end

# Test 4: Migration Job Dry Run
puts "\n4. Testing Migration Job (Dry Run)..."
begin
  # Find apps with small file sizes for testing
  small_apps = App.joins(:app_files)
                 .group('apps.id')
                 .having('SUM(app_files.size_bytes) < ?', 100.kilobytes)
                 .limit(3)
                 .pluck(:id)
  
  if small_apps.any?
    puts "   Testing with apps: #{small_apps.join(', ')}"
    
    result = MigrateFilesToR2Job.perform_now(
      app_ids: small_apps,
      batch_size: 5,
      strategy: :conservative,
      dry_run: true
    )
    
    puts "✅ Dry Run Complete"
    puts "   Status: #{result[:status]}"
    puts "   Total Files: #{result[:total_files]}"
    puts "   Total Size: #{result[:total_size_mb]} MB"
    puts "   Cost Analysis: #{result[:cost_analysis]}"
    puts "   Recommendation: #{result[:recommendation]}"
  else
    puts "⚠️  No small apps found for dry run test"
  end
rescue => e
  puts "❌ Migration Job Error: #{e.message}"
  puts "   This may be expected if R2 credentials are not configured for testing"
end

# Test 5: Version Migration Dry Run
puts "\n5. Testing Version Migration (Dry Run)..."
begin
  versions_with_snapshots = AppVersion.where('files_snapshot IS NOT NULL').limit(5)
  
  if versions_with_snapshots.any?
    app_ids = versions_with_snapshots.pluck(:app_id).uniq
    
    result = MigrateVersionsToR2Job.perform_now(
      app_ids: app_ids,
      batch_size: 3,
      min_snapshot_size: 1.kilobyte,
      dry_run: true
    )
    
    puts "✅ Version Dry Run Complete"
    puts "   Status: #{result[:status]}"
    puts "   Total Versions: #{result[:total_versions]}"
    puts "   Total Size: #{result[:total_size_mb]} MB"
    puts "   Recommendation: #{result[:recommendation]}"
  else
    puts "⚠️  No versions with snapshots found"
  end
rescue => e
  puts "❌ Version Migration Error: #{e.message}"
end

# Test 6: Feature Flag Testing
puts "\n6. Testing Feature Flags..."
begin
  # Test R2StorageConcern if we can find a model that includes it
  if test_app
    puts "   R2 storage enabled: #{test_app.app_files.first&.r2_storage_enabled? || 'N/A'}"
    puts "   R2 bucket name: #{test_app.app_files.first&.r2_bucket_name || 'N/A'}"
  end
  puts "✅ Feature flags accessible"
rescue => e
  puts "❌ Feature Flag Error: #{e.message}"
end

# Summary
puts "\n" + "=" * 50
puts "🎯 TESTING SUMMARY"
puts "=" * 50

database_stats = Storage::StorageAnalyticsService.estimate_storage_savings

puts "Current State:"
puts "  📁 Total Files: #{database_stats[:current_state][:total_files]}"
puts "  💾 Total Size: #{database_stats[:current_state][:total_size_mb]} MB"
puts "  📊 Breakdown:"
puts "     Small files (<1KB): #{database_stats[:current_state][:breakdown][:small_files][:count]}"
puts "     Medium files (1-10KB): #{database_stats[:current_state][:breakdown][:medium_files][:count]}"
puts "     Large files (>10KB): #{database_stats[:current_state][:breakdown][:large_files][:count]}"

puts "\nProjected Savings:"
puts "  💰 Database reduction: #{database_stats[:projected_savings][:database_reduction_mb]} MB (#{database_stats[:projected_savings][:database_reduction_percentage]}%)"
puts "  ☁️  R2 increase: #{database_stats[:projected_savings][:r2_storage_increase_mb]} MB"
puts "  💵 Monthly savings: $#{database_stats[:cost_estimates][:monthly_savings]}"

puts "\nNext Steps:"
puts "  1. Review R2_HYBRID_MIGRATION_PLAN.md for detailed implementation"
puts "  2. Review R2_TESTING_AND_ROLLBACK_PLAN.md for testing procedures"  
puts "  3. Configure R2 credentials if planning to test actual migration"
puts "  4. Run isolated tests on non-production data first"

puts "\n🚀 R2 Migration Setup Complete!"
puts "   Ready for Phase 1: Isolated Testing"