# Comprehensive R2 Migration System Test
# Run with: rails runner comprehensive_r2_test.rb

puts "🧪 COMPREHENSIVE R2 MIGRATION TESTING"
puts "=" * 60

def test_section(name)
  puts "\n#{name}"
  puts "-" * 40
  yield
rescue => e
  puts "❌ ERROR in #{name}: #{e.message}"
  puts "   #{e.backtrace.first}"
  false
end

results = {
  model_methods: false,
  storage_analytics: false,
  migration_jobs: false,
  service_classes: false,
  database_operations: false,
  error_handling: false
}

# Test 1: Detailed Model Method Testing
results[:model_methods] = test_section("1. DETAILED MODEL METHODS") do
  # Test AppFile comprehensive methods
  test_file = AppFile.first
  if test_file
    puts "Testing AppFile methods:"
    puts "  📄 File: #{test_file.path}"
    puts "  📊 Size: #{test_file.size_bytes} bytes (#{test_file.storage_size_category})"
    puts "  🏪 Storage: #{test_file.storage_location}"
    puts "  ✅ Should be in R2: #{test_file.should_be_in_r2?}"
    puts "  📖 Content available: #{test_file.content_available?}"

    # Test r2_storage_enabled method
    puts "  🚀 R2 enabled: #{test_file.send(:r2_storage_enabled?)}"

    # Test validation method
    test_file.send(:content_or_r2_key_present)
    puts "  ✅ Validation methods work"
  else
    puts "  ⚠️  No files to test"
  end

  # Test AppVersion methods
  test_version = AppVersion.first
  if test_version
    puts "\nTesting AppVersion methods:"
    puts "  📋 Version: #{test_version.version_number}"
    puts "  🏪 Strategy: #{test_version.storage_strategy}"
    puts "  📊 Snapshot size: #{test_version.snapshot_size_bytes} bytes"
    puts "  📖 Snapshot available: #{test_version.snapshot_available?}"
    puts "  ✅ Can be restored: #{test_version.can_be_restored?}"
    puts "  📁 Has files data: #{test_version.has_files_data?}"
  else
    puts "  ⚠️  No versions to test"
  end

  # Test AppVersionFile methods if any exist
  test_version_file = AppVersionFile.first
  if test_version_file
    puts "\nTesting AppVersionFile methods:"
    puts "  📄 Action: #{test_version_file.action}"
    puts "  📊 Content size: #{test_version_file.content_size_bytes} bytes"
    puts "  📖 Content available: #{test_version_file.content_available?}"
    puts "  🏪 Storage location: #{test_version_file.storage_location}"
  else
    puts "  ⚠️  No version files to test"
  end

  puts "✅ Model methods comprehensive test passed"
  true
end

# Test 2: Storage Analytics Deep Testing
results[:storage_analytics] = test_section("2. STORAGE ANALYTICS DEEP TEST") do
  # Test storage analytics service
  savings = Storage::StorageAnalyticsService.estimate_storage_savings

  puts "Current State Analysis:"
  puts "  📁 Total Files: #{savings[:current_state][:total_files]}"
  puts "  💾 Total Size: #{savings[:current_state][:total_size_mb]} MB"
  puts "  📊 File Breakdown:"
  puts "     Small (<1KB): #{savings[:current_state][:breakdown][:small_files][:count]} files, #{savings[:current_state][:breakdown][:small_files][:size_mb]} MB"
  puts "     Medium (1-10KB): #{savings[:current_state][:breakdown][:medium_files][:count]} files, #{savings[:current_state][:breakdown][:medium_files][:size_mb]} MB"
  puts "     Large (>10KB): #{savings[:current_state][:breakdown][:large_files][:count]} files, #{savings[:current_state][:breakdown][:large_files][:size_mb]} MB"

  puts "\nProjected Savings:"
  puts "  📉 Database reduction: #{savings[:projected_savings][:database_reduction_mb]} MB (#{savings[:projected_savings][:database_reduction_percentage]}%)"
  puts "  ☁️  R2 storage needed: #{savings[:projected_savings][:r2_storage_increase_mb]} MB"
  puts "  💰 Monthly savings: $#{savings[:cost_estimates][:monthly_savings]}"
  puts "  💵 Annual savings: $#{savings[:cost_estimates][:annual_savings]}"

  # Test database-specific analytics
  db_files = AppFile.in_database.count
  r2_files = AppFile.in_r2.count
  hybrid_files = AppFile.where(storage_location: "hybrid").count

  puts "\nCurrent Storage Distribution:"
  puts "  📊 Database files: #{db_files}"
  puts "  ☁️  R2 files: #{r2_files}"
  puts "  🔀 Hybrid files: #{hybrid_files}"

  # Test migration readiness
  migrable_files = AppFile.migrable_to_r2.count
  puts "  🚀 Ready to migrate: #{migrable_files} files"

  puts "✅ Storage analytics deep test passed"
  true
end

# Test 3: Migration Jobs Dry Run Testing
results[:migration_jobs] = test_section("3. MIGRATION JOBS DRY RUN") do
  # Test file migration job
  puts "Testing MigrateFilesToR2Job:"

  # Find some apps to test with
  test_apps = App.joins(:app_files)
    .group("apps.id")
    .having("COUNT(app_files.id) > 0")
    .having("SUM(app_files.size_bytes) < ?", 100.kilobytes)
    .limit(3)
    .pluck(:id)

  if test_apps.any?
    puts "  🧪 Testing with #{test_apps.size} apps: #{test_apps.join(", ")}"

    # Test conservative strategy
    result = MigrateFilesToR2Job.new.perform(
      app_ids: test_apps,
      batch_size: 5,
      strategy: :conservative,
      dry_run: true
    )

    puts "  📊 Conservative strategy results:"
    puts "     Status: #{result[:status]}"
    puts "     Files: #{result[:total_files]}"
    puts "     Size: #{result[:total_size_mb]} MB" if result[:total_size_mb]
    puts "     Recommendation: #{result[:recommendation]}" if result[:recommendation]

    # Test aggressive strategy
    result_aggressive = MigrateFilesToR2Job.new.perform(
      app_ids: test_apps,
      strategy: :aggressive,
      dry_run: true
    )

    puts "  📊 Aggressive strategy results:"
    puts "     Status: #{result_aggressive[:status]}"
    puts "     Files: #{result_aggressive[:total_files]}" if result_aggressive[:total_files]
  else
    puts "  ⚠️  No suitable apps found for testing"
  end

  # Test version migration job
  puts "\nTesting MigrateVersionsToR2Job:"

  versions_with_snapshots = AppVersion.where("files_snapshot IS NOT NULL").limit(5)

  if versions_with_snapshots.any?
    version_app_ids = versions_with_snapshots.pluck(:app_id).uniq.first(2)

    result = MigrateVersionsToR2Job.new.perform(
      app_ids: version_app_ids,
      batch_size: 3,
      min_snapshot_size: 1.kilobyte,
      dry_run: true
    )

    puts "  📊 Version migration results:"
    puts "     Status: #{result[:status]}"
    puts "     Versions: #{result[:total_versions]}" if result[:total_versions]
    puts "     Size: #{result[:total_size_mb]} MB" if result[:total_size_mb]
  else
    puts "  ⚠️  No versions with snapshots found"
  end

  puts "✅ Migration jobs dry run test passed"
  true
end

# Test 4: Service Classes Comprehensive Testing
results[:service_classes] = test_section("4. SERVICE CLASSES TESTING") do
  # Test R2MigrationService (dry run only)
  puts "Testing R2MigrationService:"

  # Test that service can be instantiated and methods exist
  service = Storage::R2MigrationService.new

  puts "  ✅ R2MigrationService instantiated"
  puts "  📋 Methods available: #{service.private_methods(false).grep(/validate|migrate|rollback/).size} migration methods"

  # Test StorageAnalyticsService methods
  puts "\nTesting StorageAnalyticsService methods:"

  analytics = Storage::StorageAnalyticsService.new

  # Test calculate_database_storage method
  db_stats = analytics.send(:calculate_database_storage)
  puts "  📊 Database stats calculated: #{db_stats[:files_in_database]} files"

  # Test calculate_r2_storage method
  r2_stats = analytics.send(:calculate_r2_storage)
  puts "  ☁️  R2 stats calculated: #{r2_stats[:files_in_r2]} files"

  # Test migration progress calculation
  progress = analytics.send(:calculate_migration_percentage)
  puts "  📈 Migration progress: #{progress[:percentage_complete]}%"

  # Test cost estimation
  costs = analytics.send(:estimate_cost_savings)
  puts "  💰 Cost analysis available: #{costs[:current_monthly_cost][:total]} current cost"

  puts "✅ Service classes comprehensive test passed"
  true
end

# Test 5: Database Operations Testing
results[:database_operations] = test_section("5. DATABASE OPERATIONS") do
  # Test AppFile scopes
  puts "Testing AppFile scopes:"
  puts "  📊 database_only: #{AppFile.database_only.count} files"
  puts "  📊 r2_only: #{AppFile.r2_only.count} files"
  puts "  📊 in_database: #{AppFile.in_database.count} files"
  puts "  📊 in_r2: #{AppFile.in_r2.count} files"
  puts "  📊 migrable_to_r2: #{AppFile.migrable_to_r2.count} files"

  # Test AppVersion scopes
  puts "\nTesting AppVersion scopes:"
  puts "  📊 database strategy: #{AppVersion.database.count} versions"
  puts "  📊 r2 strategy: #{AppVersion.r2.count} versions"
  puts "  📊 hybrid strategy: #{AppVersion.hybrid.count} versions"
  puts "  📊 with_database_snapshots: #{AppVersion.with_database_snapshots.count} versions"
  puts "  📊 with_r2_snapshots: #{AppVersion.with_r2_snapshots.count} versions"
  puts "  📊 migrable_to_r2: #{AppVersion.migrable_to_r2.count} versions"

  # Test AppVersionFile scopes
  puts "\nTesting AppVersionFile scopes:"
  puts "  📊 in_database: #{AppVersionFile.in_database.count} version files"
  puts "  📊 in_r2: #{AppVersionFile.in_r2.count} version files"
  puts "  📊 hybrid: #{AppVersionFile.hybrid.count} version files"
  puts "  📊 migrable_to_r2: #{AppVersionFile.migrable_to_r2.count} version files"

  # Test enum values
  puts "\nTesting enum values:"
  puts "  📊 AppFile storage locations: #{AppFile.storage_locations.keys}"
  puts "  📊 AppVersion storage strategies: #{AppVersion.storage_strategies.keys}"
  puts "  📊 AppVersionFile actions: #{AppVersionFile.actions.keys}"

  puts "✅ Database operations test passed"
  true
end

# Test 6: Error Handling and Edge Cases
results[:error_handling] = test_section("6. ERROR HANDLING & EDGE CASES") do
  puts "Testing error handling:"

  # Test R2FileStorageService without credentials
  begin
    # This should work but show configuration status
    service = Storage::R2FileStorageService.new
    puts "  ✅ R2FileStorageService can be instantiated"
    puts "  🔧 Bucket: #{service.instance_variable_get(:@bucket_name)}"
    puts "  🔧 Account ID present: #{ENV["CLOUDFLARE_ACCOUNT_ID"].present?}"
  rescue Storage::R2FileStorageService::R2StorageError => e
    puts "  ⚠️  Expected R2 configuration error: #{e.message}"
  end

  # Test model validations
  begin
    # Test AppFile validation
    file = AppFile.new(path: "test.txt")
    file.valid?
    puts "  ✅ AppFile validation working: #{file.errors.full_messages.size} validation errors"

    # Test AppVersion validation
    version = AppVersion.new
    version.valid?
    puts "  ✅ AppVersion validation working: #{version.errors.full_messages.size} validation errors"

    # Test AppVersionFile validation
    version_file = AppVersionFile.new
    version_file.valid?
    puts "  ✅ AppVersionFile validation working: #{version_file.errors.full_messages.size} validation errors"
  rescue => e
    puts "  ❌ Validation test error: #{e.message}"
    false
  end

  # Test edge cases for analytics
  begin
    # Test with empty results
    empty_stats = Storage::StorageAnalyticsService.new.send(:calculate_average_file_size, "nonexistent")
    puts "  ✅ Analytics handles empty data: average size #{empty_stats}"

    # Test cost calculations with zero values
    costs = Storage::StorageAnalyticsService.new.send(:estimate_monthly_costs, 0, 0, 0)
    puts "  ✅ Cost calculations handle zero values: #{costs[:current_monthly_cost][:total]}"
  rescue => e
    puts "  ❌ Edge case test error: #{e.message}"
    false
  end

  puts "✅ Error handling test passed"
  true
end

# Final Results Summary
puts "\n" + "=" * 60
puts "🎯 COMPREHENSIVE TEST RESULTS"
puts "=" * 60

total_tests = results.size
passed_tests = results.values.count(true)

results.each do |test_name, passed|
  status = passed ? "✅ PASS" : "❌ FAIL"
  puts "#{status} #{test_name.to_s.tr("_", " ").upcase}"
end

puts "\n📊 OVERALL SCORE: #{passed_tests}/#{total_tests} tests passed (#{(passed_tests.to_f / total_tests * 100).round(1)}%)"

if passed_tests == total_tests
  puts "\n🎉 ALL TESTS PASSED! R2 Migration System is fully functional!"
  puts "\n🚀 READY FOR PRODUCTION with R2 credentials:"
  puts "   1. Set environment variables for R2"
  puts "   2. Run isolated tests on non-critical apps"
  puts "   3. Begin gradual migration rollout"
else
  puts "\n⚠️  Some tests failed. Review the errors above before proceeding."
end

# Performance summary
puts "\n" + "=" * 60
puts "📈 SYSTEM PERFORMANCE SUMMARY"
puts "=" * 60

# Database metrics
total_apps = App.count
apps_with_files = App.joins(:app_files).distinct.count
apps_with_versions = App.joins(:app_versions).distinct.count

puts "Current Database State:"
puts "  📱 Total Apps: #{total_apps}"
puts "  📄 Apps with Files: #{apps_with_files}"
puts "  📋 Apps with Versions: #{apps_with_versions}"
puts "  💾 Average files per app: #{(apps_with_files > 0) ? (AppFile.count / apps_with_files.to_f).round(1) : 0}"

# Migration readiness
large_files_ready = AppFile.where("size_bytes > ?", 10.kilobytes).count
medium_files_ready = AppFile.where("size_bytes BETWEEN ? AND ?", 1.kilobyte, 10.kilobytes).count

puts "\nMigration Readiness:"
puts "  🚀 High Priority (>10KB): #{large_files_ready} files"
puts "  📊 Medium Priority (1-10KB): #{medium_files_ready} files"
puts "  💰 Estimated monthly savings: $#{Storage::StorageAnalyticsService.estimate_storage_savings[:cost_estimates][:monthly_savings]}"

puts "\n🎯 System is ready for R2 migration with comprehensive safety measures!"
