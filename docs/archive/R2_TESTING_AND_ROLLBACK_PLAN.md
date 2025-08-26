# R2 Hybrid Storage - Testing & Rollback Plan

## Pre-Migration Testing Checklist

### 1. Environment Setup Verification
- [ ] **R2 Configuration**: Verify all required environment variables are set
  ```bash
  # Required variables:
  CLOUDFLARE_ACCOUNT_ID=your_account_id
  CLOUDFLARE_API_TOKEN=your_api_token  
  CLOUDFLARE_R2_BUCKET_DB_FILES=overskill-dev
  
  # Optional (recommended):
  CLOUDFLARE_R2_CDN_DOMAIN=your_cdn_domain
  ```

- [ ] **Database Migrations**: Ensure all schema changes are applied
  ```bash
  rails db:migrate
  # Should show version: 2025_08_20_151400
  ```

- [ ] **R2 Bucket Access**: Test bucket connectivity
  ```ruby
  # Rails console test:
  service = Storage::R2FileStorageService.new
  service.store_file_content(999, 'test.txt', 'Hello R2!')
  ```

### 2. Service Layer Testing
- [ ] **R2FileStorageService**: Test basic CRUD operations
- [ ] **StorageAnalyticsService**: Generate initial baseline report
- [ ] **MigrateFilesToR2Job**: Run dry-run on sample data
- [ ] **MigrateVersionsToR2Job**: Run dry-run on sample data

### 3. Model Integration Testing  
- [ ] **AppFile**: Test hybrid storage functionality
- [ ] **AppVersion**: Test snapshot R2 integration
- [ ] **AppVersionFile**: Test version file R2 integration

## Testing Phases

### Phase 1: Isolated Testing (Safe)

**Duration**: 1-2 days  
**Scope**: Single app or test data only

```ruby
# 1. Create test app for isolated testing
test_app = App.find_or_create_by(name: 'R2 Test App') do |app|
  app.team = Team.first
  app.creator = Membership.first
  app.prompt = 'Test app for R2 migration'
  app.status = 'testing'
end

# 2. Run dry-run analysis
Storage::R2MigrationService.perform_full_migration(
  app_ids: [test_app.id], 
  dry_run: true
)

# 3. Run actual migration on test app
Storage::R2MigrationService.perform_full_migration(
  app_ids: [test_app.id], 
  dry_run: false
)

# 4. Verify all operations work correctly
test_app.app_files.each { |f| puts "#{f.path}: #{f.content_available?}" }
```

**Success Criteria**:
- All files successfully migrated to R2
- Content retrieval works correctly
- Version management functions properly
- No performance degradation

### Phase 2: Limited Production Testing (Controlled)

**Duration**: 3-5 days  
**Scope**: 10-20% of apps, starting with smallest

```ruby
# 1. Select small apps for migration
small_apps = App.joins(:app_files)
               .group('apps.id')
               .having('SUM(app_files.size_bytes) < ?', 1.megabyte)
               .limit(10)

# 2. Backup critical data before migration
small_apps.each do |app|
  # Create backup of files_snapshot data
  app.app_versions.each do |version|
    if version.files_snapshot.present?
      backup_key = "backup_#{app.id}_#{version.id}_#{Time.current.to_i}"
      Rails.cache.write(backup_key, version.files_snapshot, expires_in: 30.days)
    end
  end
end

# 3. Run migration
Storage::R2MigrationService.perform_full_migration(
  app_ids: small_apps.pluck(:id),
  dry_run: false
)
```

**Success Criteria**:
- Zero production issues
- All API endpoints function normally
- Version restoration works correctly
- Build/deploy processes unaffected

### Phase 3: Gradual Rollout (Production)

**Duration**: 1-2 weeks  
**Scope**: Remaining apps in batches

```ruby
# 1. Batch migration by app size
large_apps = App.joins(:app_files)
               .group('apps.id')
               .having('SUM(app_files.size_bytes) >= ?', 10.megabytes)
               .order('SUM(app_files.size_bytes) DESC')

# Migrate in batches of 20
large_apps.in_batches(of: 20) do |batch|
  Storage::R2MigrationService.perform_full_migration(
    app_ids: batch.pluck(:id),
    dry_run: false
  )
  
  # Wait 24 hours between batches
  sleep(24.hours) unless Rails.env.test?
end
```

**Success Criteria**:
- Database size reduction visible
- No increase in error rates
- Performance maintained or improved
- Cost savings realized

## Rollback Procedures

### Emergency Rollback (< 1 hour)

**Scenario**: Critical production issues detected

```ruby
# 1. Immediate feature flag disable
ENV['DISABLE_R2_STORAGE'] = 'true'

# 2. Force application restart to pick up new ENV
# (deployment-specific commands)

# 3. Verify all apps reading from database
AppFile.r2_only.count # Should be 0 after restart
```

### Selective Rollback (Specific Apps)

**Scenario**: Issues with specific apps

```ruby
# 1. Rollback specific apps
problem_app_ids = [123, 456, 789]

Storage::R2MigrationService.rollback_to_database(
  app_ids: problem_app_ids,
  dry_run: false
)

# 2. Verify rollback success
AppFile.where(app_id: problem_app_ids, storage_location: 'database').count
```

### Full Rollback (< 4 hours)

**Scenario**: Major issues requiring complete rollback

```ruby
# 1. Disable R2 globally
ENV['DISABLE_R2_STORAGE'] = 'true'

# 2. Full migration rollback
Storage::R2MigrationService.rollback_to_database(dry_run: false)

# 3. Verify complete rollback
{
  files_in_db: AppFile.database_only.count,
  files_in_r2: AppFile.r2_only.count,
  versions_in_db: AppVersion.where(storage_strategy: 'database').count,
  versions_in_r2: AppVersion.where(storage_strategy: 'r2').count
}
```

### Data Recovery Procedures

**If R2 Data Lost**:
1. **Hybrid Files**: Restore from database content (automatic)
2. **R2-Only Files**: Restore from daily database backups
3. **Version Snapshots**: Restore from backup keys in Rails.cache

```ruby
# Recovery from backups
def recover_version_snapshots(app_id)
  backup_keys = Rails.cache.instance_variable_get(:@data).keys
                     .select { |k| k.start_with?("backup_#{app_id}_") }
  
  backup_keys.each do |key|
    parts = key.split('_')
    version_id = parts[2]
    
    version = AppVersion.find(version_id)
    snapshot_data = Rails.cache.read(key)
    
    version.update!(
      files_snapshot: snapshot_data,
      storage_strategy: 'database',
      r2_snapshot_key: nil
    )
  end
end
```

## Monitoring & Validation

### Automated Monitoring

```ruby
# Create monitoring job
class R2MigrationMonitorJob < ApplicationJob
  def perform
    report = Storage::StorageAnalyticsService.generate_migration_report
    
    # Alert conditions
    alerts = []
    
    if report[:r2_storage][:total_r2_size_bytes] == 0 && AppFile.r2_only.exists?
      alerts << "R2 storage shows 0 bytes but R2-only files exist"
    end
    
    if report[:migration_progress][:percentage_complete] < 50 && Time.current > migration_start_time + 7.days
      alerts << "Migration progress below 50% after 7 days"
    end
    
    # Send alerts if any
    if alerts.any?
      Rails.logger.error "R2 Migration Alerts: #{alerts.join('; ')}"
      # Send to monitoring service
    end
    
    report
  end
end
```

### Manual Validation Queries

```ruby
# Daily validation checks
def validate_r2_migration
  {
    # File integrity
    files_with_content: AppFile.joins('LEFT JOIN app_files af2 ON af2.content_hash = app_files.content_hash')
                               .where('app_files.content IS NOT NULL OR app_files.r2_object_key IS NOT NULL')
                               .count,
    
    # Version integrity  
    versions_with_snapshots: AppVersion.where('files_snapshot IS NOT NULL OR r2_snapshot_key IS NOT NULL').count,
    
    # No orphaned R2 keys
    orphaned_r2_keys: AppFile.where('r2_object_key IS NOT NULL')
                             .where(storage_location: ['r2', 'hybrid'])
                             .where('content IS NULL')
                             .where('storage_location = ?', 'r2')
                             .count,
    
    # Storage distribution
    storage_distribution: {
      database_only: AppFile.database_only.count,
      r2_only: AppFile.r2_only.count, 
      hybrid: AppFile.where(storage_location: 'hybrid').count
    }
  }
end
```

## Performance Impact Assessment

### Before Migration Baseline
```ruby
def capture_baseline_metrics
  {
    avg_file_read_time: benchmark_file_reads,
    avg_version_restore_time: benchmark_version_restores,
    database_size_mb: calculate_database_size,
    active_record_query_times: benchmark_ar_queries
  }
end
```

### During Migration Monitoring
```ruby 
def monitor_migration_performance
  {
    r2_api_response_times: measure_r2_latency,
    cache_hit_rates: Rails.cache.stats,
    error_rates: count_r2_errors,
    hybrid_fallback_rates: count_database_fallbacks
  }
end
```

## Success Criteria & KPIs

### Technical Metrics
- **Database Size Reduction**: Target 70-80% reduction in app_files table size
- **R2 API Latency**: < 200ms average response time
- **Cache Hit Rate**: > 90% for frequently accessed files
- **Error Rate**: < 0.1% for R2 operations
- **Fallback Rate**: < 1% fallback to database reads

### Business Metrics  
- **Cost Reduction**: Target 80-90% reduction in storage costs
- **Performance**: No degradation in app build/deploy times
- **Reliability**: 99.9% uptime for file access operations

### Rollback Triggers
- **Critical**: Any data loss or corruption
- **Major**: Error rates > 1% sustained for > 15 minutes
- **Minor**: Performance degradation > 50% for > 1 hour

---

## Quick Reference Commands

```ruby
# Status checks
Storage::StorageAnalyticsService.generate_migration_report

# Emergency rollback
ENV['DISABLE_R2_STORAGE'] = 'true'

# Selective migration
Storage::R2MigrationService.perform_full_migration(app_ids: [123], dry_run: false)

# Cleanup hybrid files
Storage::R2MigrationService.cleanup_hybrid_files

# Validation
validate_r2_migration

# Performance monitoring
monitor_migration_performance
```

This comprehensive testing and rollback plan ensures safe, gradual migration with multiple safety nets and clear recovery procedures.