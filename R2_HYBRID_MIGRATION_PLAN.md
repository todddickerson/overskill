# R2 Hybrid Storage Migration Plan for OverSkill

## Executive Summary

This document outlines a comprehensive migration strategy from JSONB database storage to a hybrid Cloudflare R2 approach for app file storage. The goal is to reduce database bloat, improve performance, and leverage Rails 8 capabilities while maintaining full version management and deployment functionality.

## Current Architecture Analysis

### Existing Storage System
- **AppFile**: Stores `content` field as TEXT in database (JSONB-like usage)
- **AppVersion**: Has `files_snapshot` TEXT field for complete version snapshots  
- **AppVersionFile**: Stores `content` TEXT field for tracking version changes
- **Size Impact**: Large apps generate 85+ files, each storing complete content in DB

### Current Database Schema
```sql
-- Current problematic storage
app_files.content TEXT NOT NULL          -- File content stored directly
app_versions.files_snapshot TEXT         -- JSON snapshot of all files  
app_version_files.content TEXT           -- Version-specific content changes

-- Metadata we keep
app_files.path, file_type, size_bytes, checksum, is_entry_point
app_versions.version_number, changelog, environment
app_version_files.action (created/updated/deleted/restored)
```

### Existing R2 Integration
- ✅ Cloudflare R2 already integrated via `CloudflareApiClient`
- ✅ R2 uploads working for large assets (>50KB) during deployment
- ✅ Authentication and bucket management established
- ✅ CDN URLs generated for asset delivery

## Hybrid Strategy Design

### Core Principle: **Progressive Migration with Zero Downtime**

**Phase 1**: Dual-write system (database + R2)
**Phase 2**: Read-from-R2-first with database fallback  
**Phase 3**: Full R2 migration with database cleanup

### Storage Architecture

#### 1. Database (Metadata + Small Files)
```sql
-- Enhanced schema (migration needed)
app_files:
  path VARCHAR NOT NULL
  file_type VARCHAR
  size_bytes INTEGER  
  checksum VARCHAR
  is_entry_point BOOLEAN
  storage_location VARCHAR DEFAULT 'database' -- 'database', 'r2', 'hybrid'
  r2_object_key VARCHAR                        -- NULL if stored in database
  content TEXT                                 -- NULL if stored in R2
  content_hash VARCHAR                         -- For integrity checking

app_versions:
  version_number VARCHAR NOT NULL
  changelog TEXT
  storage_strategy VARCHAR DEFAULT 'database' -- 'database', 'r2', 'hybrid'
  r2_snapshot_key VARCHAR                      -- Object key for complete snapshot
  files_snapshot TEXT                          -- NULL if stored in R2

app_version_files:
  action VARCHAR NOT NULL
  r2_content_key VARCHAR                       -- Object key for this version's content
  content TEXT                                 -- NULL if stored in R2
```

#### 2. R2 Storage (File Content)
```
Bucket: overskill-dev
Structure:
  apps/{app_id}/files/{file_path}           # Current app file content
  apps/{app_id}/versions/{version_id}/{file_path}  # Version-specific content
  apps/{app_id}/snapshots/v{version}/snapshot.json # Complete version snapshot
  apps/{app_id}/metadata/{checksum}.txt    # Content-addressed storage
```

### File Size Strategy

| File Size | Storage Location | Reason |
|-----------|------------------|--------|
| < 1KB | Database | Fast queries, minimal space impact |
| 1KB - 10KB | Hybrid (both) | Transition safety, fast fallback |  
| > 10KB | R2 Primary | Significant space savings |
| > 50KB | R2 Only | Existing pattern, CDN benefits |

## Migration Implementation Plan

### Phase 1: Foundation Setup (Week 1)

#### 1.1 Database Schema Updates
```ruby
# db/migrate/add_r2_storage_to_app_files.rb
class AddR2StorageToAppFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :app_files, :storage_location, :string, default: 'database'
    add_column :app_files, :r2_object_key, :string
    add_column :app_files, :content_hash, :string
    
    add_index :app_files, :storage_location
    add_index :app_files, :r2_object_key, unique: true
    add_index :app_files, :content_hash
  end
end

# db/migrate/add_r2_storage_to_app_versions.rb  
class AddR2StorageToAppVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_versions, :storage_strategy, :string, default: 'database'
    add_column :app_versions, :r2_snapshot_key, :string
    
    add_index :app_versions, :storage_strategy
    add_index :app_versions, :r2_snapshot_key, unique: true
  end
end

# db/migrate/add_r2_storage_to_app_version_files.rb
class AddR2StorageToAppVersionFiles < ActiveRecord::Migration[8.0] 
  def change
    add_column :app_version_files, :r2_content_key, :string
    
    add_index :app_version_files, :r2_content_key, unique: true
  end
end
```

#### 1.2 R2 Service Classes
```ruby
# app/services/storage/r2_file_storage_service.rb
class Storage::R2FileStorageService
  def initialize(bucket_name = ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'])
    @bucket_name = bucket_name
    @client = Deployment::CloudflareApiClient.new(nil) # Utility instance
  end
  
  def store_file_content(app_id, file_path, content)
    object_key = generate_file_key(app_id, file_path)
    result = upload_to_r2(object_key, content)
    
    {
      success: true,
      object_key: object_key,
      size: content.bytesize,
      checksum: Digest::SHA256.hexdigest(content),
      cdn_url: result[:cdn_url]
    }
  end
  
  def retrieve_file_content(object_key)
    # Implement R2 GET request
    download_from_r2(object_key)
  end
  
  def store_version_snapshot(app_id, version_id, files_hash)
    object_key = "apps/#{app_id}/snapshots/#{version_id}/snapshot.json"
    content = JSON.pretty_generate(files_hash)
    upload_to_r2(object_key, content)
  end
  
  private
  
  def generate_file_key(app_id, file_path)
    "apps/#{app_id}/files/#{file_path.gsub(/^\//, '')}"
  end
end
```

#### 1.3 Enhanced AppFile Model
```ruby
# app/models/app_file.rb (enhanced)
class AppFile < ApplicationRecord
  # Storage location tracking
  enum storage_location: { database: 'database', r2: 'r2', hybrid: 'hybrid' }
  
  # Content management with R2 fallback
  def content
    case storage_location
    when 'database', 'hybrid'
      super # Use database content
    when 'r2'
      fetch_from_r2
    else
      super || fetch_from_r2 # Fallback strategy
    end
  end
  
  def content=(new_content)
    strategy = determine_storage_strategy(new_content)
    
    case strategy
    when :database_only
      super(new_content)
      self.storage_location = 'database'
    when :r2_only  
      store_in_r2(new_content)
      super(nil) # Clear database content
      self.storage_location = 'r2'
    when :hybrid
      super(new_content) # Store in database
      store_in_r2(new_content) # Also store in R2
      self.storage_location = 'hybrid'
    end
    
    self.content_hash = Digest::SHA256.hexdigest(new_content)
    self.size_bytes = new_content.bytesize
  end
  
  private
  
  def determine_storage_strategy(content)
    size = content.bytesize
    
    case size
    when 0..1.kilobyte
      :database_only
    when 1.kilobyte..10.kilobytes  
      :hybrid # Safety during migration
    else
      :r2_only
    end
  end
  
  def fetch_from_r2
    return nil if r2_object_key.blank?
    
    Rails.cache.fetch("r2_content_#{r2_object_key}", expires_in: 5.minutes) do
      Storage::R2FileStorageService.new.retrieve_file_content(r2_object_key)
    end
  rescue => e
    Rails.logger.error "Failed to fetch R2 content for #{r2_object_key}: #{e.message}"
    nil
  end
  
  def store_in_r2(content)
    service = Storage::R2FileStorageService.new
    result = service.store_file_content(app.id, path, content)
    self.r2_object_key = result[:object_key]
    result
  end
end
```

### Phase 2: Migration Strategy (Week 2-3)

#### 2.1 Progressive Migration Job
```ruby
# app/jobs/migrate_files_to_r2_job.rb
class MigrateFilesToR2Job < ApplicationJob
  def perform(batch_size: 50, app_ids: nil)
    scope = app_ids ? AppFile.where(app_id: app_ids) : AppFile
    
    # Migrate large files first (biggest impact)
    scope.where('size_bytes > ?', 10.kilobytes)
         .where(storage_location: 'database')
         .find_in_batches(batch_size: batch_size) do |batch|
      
      migrate_batch(batch)
      sleep(1) # Rate limiting
    end
  end
  
  private
  
  def migrate_batch(files)
    files.each do |file|
      next if file.content.blank?
      
      begin
        # Store in R2
        result = file.store_in_r2(file.content)
        
        # Update storage location but keep database content initially
        file.update!(
          storage_location: 'hybrid',
          r2_object_key: result[:object_key],
          content_hash: result[:checksum]
        )
        
        Rails.logger.info "Migrated file #{file.id} (#{file.path}) to R2"
        
      rescue => e
        Rails.logger.error "Failed to migrate file #{file.id}: #{e.message}"
      end
    end
  end
end
```

#### 2.2 Version Management Updates
```ruby
# app/models/app_version.rb (enhanced)
class AppVersion < ApplicationRecord
  enum storage_strategy: { database: 'database', r2: 'r2', hybrid: 'hybrid' }
  
  def files_snapshot
    case storage_strategy
    when 'database', 'hybrid'
      super
    when 'r2'
      fetch_snapshot_from_r2
    else
      super || fetch_snapshot_from_r2
    end
  end
  
  def migrate_to_r2!
    return if storage_strategy == 'r2'
    
    if files_snapshot.present?
      service = Storage::R2FileStorageService.new
      result = service.store_version_snapshot(app.id, id, files_snapshot)
      
      update!(
        storage_strategy: 'hybrid',
        r2_snapshot_key: result[:object_key]
      )
    end
  end
  
  private
  
  def fetch_snapshot_from_r2
    return nil if r2_snapshot_key.blank?
    
    Rails.cache.fetch("r2_snapshot_#{r2_snapshot_key}", expires_in: 10.minutes) do
      Storage::R2FileStorageService.new.retrieve_file_content(r2_snapshot_key)
    end
  rescue => e
    Rails.logger.error "Failed to fetch R2 snapshot #{r2_snapshot_key}: #{e.message}"
    nil
  end
end
```

### Phase 3: Rails 8 Integration (Week 3-4)

#### 3.1 Solid Cache Integration
```ruby
# config/environments/production.rb
config.cache_store = :solid_cache_store

# Use Solid Cache for R2 content caching
class Storage::R2FileStorageService
  def retrieve_file_content(object_key)
    Rails.cache.fetch("r2_file_#{object_key}", expires_in: 30.minutes, race_condition_ttl: 30.seconds) do
      download_from_r2(object_key)
    end
  end
end
```

#### 3.2 Solid Queue Background Processing
```ruby
# app/jobs/r2_cleanup_job.rb
class R2CleanupJob < ApplicationJob
  def perform
    # Clean up orphaned R2 objects
    # Verify database consistency
    # Generate storage analytics
  end
end

# config/schedule.rb (whenever gem)
every 1.day, at: '2:00 am' do
  runner "R2CleanupJob.perform_later"
end
```

#### 3.3 Performance Monitoring
```ruby
# app/services/storage/storage_analytics_service.rb
class Storage::StorageAnalyticsService
  def generate_migration_report
    {
      database_files: AppFile.where(storage_location: 'database').sum(:size_bytes),
      r2_files: AppFile.where(storage_location: 'r2').sum(:size_bytes),
      hybrid_files: AppFile.where(storage_location: 'hybrid').sum(:size_bytes),
      migration_progress: calculate_migration_percentage,
      cost_savings: estimate_cost_savings
    }
  end
end
```

### Phase 4: Deployment Pipeline Updates (Week 4)

#### 4.1 ExternalViteBuilder Integration
```ruby
# app/services/deployment/external_vite_builder.rb (enhanced)
class Deployment::ExternalViteBuilder
  def build_for_preview_with_r2
    # Enhanced to support R2-based file retrieval
    app_files = load_app_files_optimized # Hybrid database/R2 loading
    
    # Rest of build logic remains same
    # Assets over 50KB still go to deployment R2 bucket
  end
  
  private
  
  def load_app_files_optimized
    files = {}
    
    @app.app_files.includes(:app).each do |file|
      content = file.content # Uses hybrid retrieval automatically
      files[file.path] = content if content.present?
    end
    
    files
  end
end
```

#### 4.2 Version Restoration Updates
```ruby
# app/controllers/account/app_versions_controller.rb (enhanced)
def restore_from_version
  version = @app.app_versions.find(params[:version_id])
  
  # Handle R2-based version restoration
  snapshot = case version.storage_strategy
  when 'r2', 'hybrid'
    version.files_snapshot # Automatically fetches from R2 if needed
  else
    version.files_snapshot || restore_from_files_data(version)
  end
  
  # Rest of restoration logic remains same
end
```

## Cost Analysis

### Database Storage Savings
```
Current: 100 apps × 85 files × 5KB average = 42.5 MB per app
Total: 4.25 GB for 100 apps

After Migration:
- Small files (<1KB): 20% remain in database = 850 MB
- Large files (>1KB): 80% moved to R2 = 3.4 GB savings

Monthly Database Cost Reduction: ~$15-30/month (varies by provider)
```

### R2 Storage Costs
```
R2 Storage: $0.015/GB/month
R2 Operations: $0.36/million writes, $0.18/million reads

Estimated Monthly R2 Costs:
- Storage: 3.4 GB × $0.015 = $0.051
- Operations: Minimal due to caching
- Total: ~$0.10/month

Net Savings: $15-30/month database - $0.10/month R2 = $14.90-29.90/month
```

## Risk Mitigation

### 1. Data Integrity
- **Checksums**: SHA256 hash verification for all content
- **Dual Storage**: Hybrid mode maintains database backup during transition
- **Validation Jobs**: Regular consistency checks between DB and R2

### 2. Performance
- **Caching**: Aggressive Rails cache for R2 content (Solid Cache)
- **CDN**: Cloudflare's global network for fast retrieval
- **Fallbacks**: Database content used if R2 fails

### 3. Migration Safety
- **Rollback Plan**: Database content preserved during migration
- **Feature Flags**: Toggle R2 usage per app or globally
- **Monitoring**: Detailed logging and error tracking

### 4. Cost Control
- **Lifecycle Policies**: Automatic cleanup of old versions
- **Compression**: Gzip content before R2 storage
- **Deduplication**: Content-addressed storage for identical files

## Timeline & Execution

### Week 1: Foundation
- [ ] Database migrations
- [ ] R2FileStorageService implementation
- [ ] Enhanced model methods
- [ ] Unit test coverage

### Week 2: Migration Logic  
- [ ] MigrateFilesToR2Job implementation
- [ ] Version management updates
- [ ] Integration tests
- [ ] Performance benchmarking

### Week 3: Rails 8 Integration
- [ ] Solid Cache configuration
- [ ] Background job setup
- [ ] Analytics and monitoring
- [ ] Load testing

### Week 4: Production Deployment
- [ ] Feature flag rollout (10% → 50% → 100%)
- [ ] Deployment pipeline updates  
- [ ] Documentation updates
- [ ] Team training

## Success Metrics

1. **Database Size Reduction**: Target 70-80% reduction in app_files table size
2. **Performance**: File retrieval time <100ms (with caching)
3. **Reliability**: 99.9% availability for R2 file access
4. **Cost**: Monthly storage costs reduced by >90%

## Rollback Strategy

If issues arise:
1. **Immediate**: Toggle feature flag to disable R2 reads
2. **Short-term**: Files in hybrid mode use database content
3. **Long-term**: Restore from database backups (content preserved)

---

## Next Steps

1. Review this plan with the team
2. Set up staging environment for testing
3. Begin Phase 1 implementation
4. Schedule weekly progress reviews

This hybrid approach leverages Rails 8's improvements while providing a safe, progressive migration path that maintains all existing functionality while significantly reducing costs and improving scalability.