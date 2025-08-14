# File-Level Granular Caching Strategy for OverSkill AI

## Overview

This document outlines the implementation strategy for file-level granular caching in OverSkill's AI app generation system. The goal is to optimize Anthropic API costs by caching individual files rather than monolithic file lists, allowing selective cache invalidation when files change.

## Current State

### Problems with Current Implementation
1. **Monolithic Caching**: All files are bundled in a single `<useful-context>` block
2. **All-or-Nothing Invalidation**: Changing one file invalidates the entire cache
3. **Suboptimal Cost**: Frequent full cache recreation for minor changes
4. **Limited Granularity**: Can't track which files actually changed

### Current Architecture
```ruby
# Current: Single cached block
system_prompt = [
  {
    type: "text",
    text: "<useful-context>#{all_files_content}</useful-context>",
    cache_control: { type: "ephemeral" }
  }
]
```

## Proposed Architecture

### File-Level Caching with 4 Breakpoints

Anthropic allows up to 4 cache breakpoints. We'll organize files by:
1. **Core Template Files** (rarely change) - 1 hour cache
2. **Library/Dependencies** (change occasionally) - 30 min cache  
3. **Application Logic** (change frequently) - 5 min cache
4. **Active Development Files** (currently being modified) - no cache

### Implementation Strategy

#### 1. File Change Tracking System

```ruby
class FileChangeTracker
  def initialize(app_id)
    @app_id = app_id
    @redis = Redis.new
  end
  
  def track_file_change(file_path, content)
    new_hash = Digest::SHA256.hexdigest(content)
    cache_key = "file_hash:#{@app_id}:#{file_path}"
    
    old_hash = @redis.get(cache_key)
    changed = (old_hash != new_hash)
    
    @redis.setex(cache_key, 1.hour, new_hash)
    
    if changed
      invalidate_file_cache(file_path)
      log_change(file_path)
    end
    
    changed
  end
  
  def get_changed_files_since(timestamp)
    # Return list of files changed since timestamp
  end
  
  private
  
  def invalidate_file_cache(file_path)
    # Mark this file's cache as invalid
    @redis.del("file_cache:#{@app_id}:#{file_path}")
  end
end
```

#### 2. Granular System Prompt Builder

```ruby
class GranularCachedPromptBuilder < Ai::Prompts::CachedPromptBuilder
  MAX_BREAKPOINTS = 4
  
  def build_granular_system_prompt
    system_blocks = []
    
    # Group files by stability/change frequency
    file_groups = categorize_files_by_stability(@template_files)
    
    # Block 1: Core template files (stable, 1hr cache)
    if file_groups[:core].any?
      system_blocks << build_cached_block(
        file_groups[:core], 
        "core_templates",
        ttl: "1h"
      )
    end
    
    # Block 2: Library files (semi-stable, 30min cache)
    if file_groups[:libraries].any?
      system_blocks << build_cached_block(
        file_groups[:libraries],
        "library_files", 
        ttl: "30m"
      )
    end
    
    # Block 3: App logic (changes frequently, 5min cache)
    if file_groups[:app_logic].any?
      system_blocks << build_cached_block(
        file_groups[:app_logic],
        "app_logic",
        ttl: "5m"
      )
    end
    
    # Block 4: Active development (no cache)
    if file_groups[:active].any?
      system_blocks << build_uncached_block(
        file_groups[:active],
        "active_development"
      )
    end
    
    system_blocks
  end
  
  private
  
  def categorize_files_by_stability(files)
    tracker = FileChangeTracker.new(@app.id)
    
    {
      core: files.select { |f| is_core_template?(f.path) },
      libraries: files.select { |f| is_library_file?(f.path) },
      app_logic: files.select { |f| is_app_logic?(f.path) && !recently_changed?(f, tracker) },
      active: files.select { |f| recently_changed?(f, tracker) }
    }
  end
  
  def build_cached_block(files, label, ttl:)
    content = wrap_files_in_context(files, label)
    
    {
      type: "text",
      text: content,
      cache_control: { 
        type: "ephemeral",
        ttl: ttl
      },
      metadata: {
        label: label,
        file_count: files.count,
        file_hashes: files.map { |f| Digest::SHA256.hexdigest(f.content) }
      }
    }
  end
  
  def build_uncached_block(files, label)
    {
      type: "text",
      text: wrap_files_in_context(files, label),
      metadata: {
        label: label,
        file_count: files.count
      }
    }
  end
  
  def wrap_files_in_context(files, label)
    <<~CONTEXT
    <useful-context label="#{label}">
    #{files.map { |f| format_file_content(f) }.join("\n")}
    </useful-context>
    CONTEXT
  end
  
  def is_core_template?(path)
    path.match?(/^(config|lib|templates|shared)\//)
  end
  
  def is_library_file?(path)
    path.match?(/^(node_modules|vendor|packages)\//) ||
    path.match?(/\.(lock|json)$/)
  end
  
  def is_app_logic?(path)
    path.match?(/^(app|src|components)\//) &&
    !path.match?(/\.(test|spec)/)
  end
  
  def recently_changed?(file, tracker)
    # Check if file changed in last 5 minutes
    recent_changes = tracker.get_changed_files_since(5.minutes.ago)
    recent_changes.include?(file.path)
  end
end
```

#### 3. Cache Invalidation on Tool Calls

```ruby
module Ai
  class AppBuilderV5
    # Override tool methods to track file changes
    
    def write_file(file_path, content)
      result = super
      
      if result[:success]
        # Track the change for cache invalidation
        tracker = FileChangeTracker.new(@app.id)
        tracker.track_file_change(file_path, content)
        
        # Invalidate any cached system prompts containing this file
        invalidate_prompt_cache_for_file(file_path)
      end
      
      result
    end
    
    def replace_file_content(args)
      result = super
      
      if result[:success]
        file_path = args['file_path']
        file = @app.app_files.find_by(path: file_path)
        
        if file
          tracker = FileChangeTracker.new(@app.id)
          tracker.track_file_change(file_path, file.content)
          invalidate_prompt_cache_for_file(file_path)
        end
      end
      
      result
    end
    
    private
    
    def invalidate_prompt_cache_for_file(file_path)
      # Clear Redis cache for prompts containing this file
      cache_key_pattern = "prompt_cache:#{@app.id}:*#{file_path}*"
      
      redis = Redis.new
      keys = redis.keys(cache_key_pattern)
      redis.del(*keys) if keys.any?
      
      Rails.logger.info "[CACHE] Invalidated #{keys.count} cached prompts after change to #{file_path}"
    end
  end
end
```

#### 4. Smart Cache Rotation for >4 File Groups

```ruby
class AdaptiveCacheRotator
  def initialize(app_id)
    @app_id = app_id
    @metrics = CacheMetricsTracker.new(app_id)
  end
  
  def select_optimal_breakpoints(all_files)
    # Score each file based on:
    # 1. Size (larger = more benefit from caching)
    # 2. Stability (less changes = better for caching)
    # 3. Usage frequency (more reads = better for caching)
    
    scored_files = all_files.map do |file|
      {
        file: file,
        score: calculate_cache_score(file)
      }
    end
    
    # Group by stability tier
    groups = group_by_optimal_strategy(scored_files)
    
    # Select top 4 groups that maximize cache efficiency
    select_top_groups(groups, MAX_BREAKPOINTS)
  end
  
  private
  
  def calculate_cache_score(file)
    size_score = [file.content.length / 1000.0, 10].min
    stability_score = @metrics.get_stability_score(file.path)
    usage_score = @metrics.get_usage_frequency(file.path)
    
    (size_score * 0.3 + stability_score * 0.5 + usage_score * 0.2) * 10
  end
end
```

## Implementation Plan

### Phase 1: Foundation (Week 1)
1. ✅ Document strategy (this document)
2. [ ] Create FileChangeTracker service
3. [ ] Add Redis keys for file hashing
4. [ ] Create test suite for change tracking

### Phase 2: Granular Prompt Building (Week 1-2)
1. [ ] Extend CachedPromptBuilder to GranularCachedPromptBuilder
2. [ ] Implement file categorization logic
3. [ ] Add metadata tracking for cache blocks
4. [ ] Update AppBuilderV5 to use new builder

### Phase 3: Cache Invalidation (Week 2)
1. [ ] Hook into tool methods (os-write, os-line-replace, etc.)
2. [ ] Implement cache invalidation on file changes
3. [ ] Add logging for cache hit/miss rates
4. [ ] Create monitoring dashboard

### Phase 4: Optimization (Week 3)
1. [ ] Implement AdaptiveCacheRotator for >4 groups
2. [ ] Add metrics tracking for cache performance
3. [ ] Fine-tune TTL values based on metrics
4. [ ] A/B test with current implementation

## Monitoring & Metrics

### Key Metrics to Track
- **Cache Hit Rate**: % of API calls using cached content
- **Cost Savings**: $ saved from cache reads vs full reads
- **Invalidation Rate**: How often each file group is invalidated
- **Response Time**: API response time with/without caching

### Redis Keys Structure
```
file_hash:{app_id}:{file_path} -> SHA256 hash
file_change_log:{app_id} -> sorted set of changes
prompt_cache:{app_id}:{context_hash} -> cached prompt
cache_metrics:{app_id}:{metric_name} -> metric values
```

## Expected Benefits

1. **Cost Reduction**: 70-90% on cached file reads
2. **Selective Invalidation**: Only affected files lose cache
3. **Better Performance**: Reduced API latency from cache hits
4. **Granular Control**: Track exactly which files change

## Rollback Plan

If issues arise, we can instantly revert by:
1. Feature flag: `ENABLE_GRANULAR_CACHING=false`
2. Falls back to current CachedPromptBuilder
3. No data migration required

## Success Criteria

- [ ] 80%+ cache hit rate for stable files
- [ ] 50%+ overall cost reduction on API calls
- [ ] No increase in generation errors
- [ ] Measurable reduction in API response time

## Notes

- Maximum 4 cache breakpoints is a hard Anthropic limit
- Each breakpoint must be >1024 tokens to be cached
- Cache TTL options: 5m, 30m, 1h, 24h (Anthropic ephemeral cache)
- Files modified by AI should immediately invalidate their cache