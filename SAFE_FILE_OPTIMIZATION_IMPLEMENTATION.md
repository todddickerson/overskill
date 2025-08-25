# Safe File Optimization Implementation Plan

## ⚠️ Critical Requirements

Based on verification of the deployment pipeline:
1. **DeployAppJob** syncs ALL `app.app_files` to GitHub repository
2. GitHub repository is the source of truth for deployment
3. Helicone is already integrated for metrics tracking
4. Anthropic supports only **5 minute** and **1 hour** TTL (confirmed)

## ✅ Safe Implementation Strategy

### Phase 1: Selective Initial Copying (Safe Approach)

**Current Problem:** Copying all 84 template files on app creation
**Safe Solution:** Copy essential files + load components on-demand BUT ensure they're saved

```ruby
# app/models/app.rb

# Essential files that MUST be copied initially for app to function
ESSENTIAL_TEMPLATE_FILES = [
  'package.json',           # Required for dependencies
  'index.html',            # Entry point
  'src/main.tsx',          # React bootstrap
  'src/App.tsx',           # Main app component
  'src/index.css',         # Core styles
  'tailwind.config.ts',    # Tailwind config
  'vite.config.ts',        # Build config
  'tsconfig.json',         # TypeScript config
  '.gitignore',            # Git ignore
  'worker-build.js',       # Worker build script
  'wrangler.toml'          # Cloudflare config
].freeze

# Components to copy based on app type (to ensure common ones are available)
BASE_COMPONENTS = %w[
  button
  card
  input
].freeze

def copy_optimized_template_files
  template_dir = current_template_path
  
  unless Dir.exist?(template_dir)
    Rails.logger.error "[App] Template directory not found: #{template_dir}"
    return false
  end
  
  files_copied = 0
  
  # 1. Copy essential files
  ESSENTIAL_TEMPLATE_FILES.each do |relative_path|
    file_path = ::File.join(template_dir, relative_path)
    next unless ::File.file?(file_path)
    
    content = ::File.read(file_path)
    app_file = app_files.find_or_initialize_by(path: relative_path)
    app_file.content = content
    app_file.file_type = detect_file_type(relative_path)
    
    if app_file.save
      files_copied += 1
      Rails.logger.info "[App] Copied essential: #{relative_path}"
    end
  end
  
  # 2. Copy base UI components (always needed)
  BASE_COMPONENTS.each do |component|
    component_path = "src/components/ui/#{component}.tsx"
    file_path = ::File.join(template_dir, component_path)
    next unless ::File.file?(file_path)
    
    content = ::File.read(file_path)
    app_file = app_files.find_or_initialize_by(path: component_path)
    app_file.content = content
    app_file.file_type = 'component'
    
    if app_file.save
      files_copied += 1
      Rails.logger.info "[App] Copied base component: #{component}"
    end
  end
  
  # 3. Copy lib and hooks (commonly needed)
  %w[src/lib/utils.ts src/hooks/use-toast.ts].each do |lib_path|
    file_path = ::File.join(template_dir, lib_path)
    next unless ::File.file?(file_path)
    
    content = ::File.read(file_path)
    app_file = app_files.find_or_initialize_by(path: lib_path)
    app_file.content = content
    app_file.file_type = 'script'
    app_file.save
    files_copied += 1
  end
  
  Rails.logger.info "[App] Optimized copy: #{files_copied} files (was 84)"
  broadcast_optimization_metric(files_copied)
  
  true
end
```

### Phase 2: On-Demand Component Loading (CRITICAL)

**MUST ensure loaded files are saved to app_files for deployment!**

```ruby
# app/services/ai/ai_tool_service.rb

# Add to os-view tool implementation
def handle_os_view(path)
  # Check if file exists in app_files
  app_file = @app.app_files.find_by(path: path)
  
  if app_file
    # File already loaded, return it
    return app_file.content
  end
  
  # Check if it's a template file we haven't loaded yet
  template_path = Rails.root.join('app/services/ai/templates/overskill_20250728', path)
  
  if File.exist?(template_path)
    # Load from template and SAVE TO APP_FILES (critical for deployment!)
    content = File.read(template_path)
    
    # Save to app_files so it gets deployed
    new_file = @app.app_files.create!(
      path: path,
      content: content,
      file_type: detect_file_type(path)
    )
    
    Rails.logger.info "[AI Tool] Loaded on-demand and saved: #{path}"
    track_on_demand_load(path)
    
    return content
  end
  
  # File doesn't exist
  raise "File not found: #{path}"
end

private

def track_on_demand_load(path)
  # Track which files are loaded on-demand for optimization insights
  Redis.current.hincrby("app:#{@app.id}:on_demand", path, 1)
  
  # Track globally for pattern analysis
  Redis.current.zincrby("global:on_demand_files", 1, path)
end
```

### Phase 3: Proper TTL Caching (Anthropic Constraints)

```ruby
# app/services/ai/prompts/properly_cached_prompt_builder.rb

class ProperlyCachedPromptBuilder < CachedPromptBuilder
  # Anthropic only supports 5m and 1h TTL (confirmed)
  SUPPORTED_TTLS = {
    one_hour: { ttl: "1h", cost_multiplier: 2.0 },    # 2x write cost
    five_min: { ttl: "5m", cost_multiplier: 1.25 }    # 1.25x write cost
  }.freeze
  
  def build_system_prompt_array
    blocks = []
    
    # Block 1: System instructions (1 hour cache - rarely changes)
    # MUST come before 5m cache blocks per Anthropic requirements
    if @base_prompt.present? && @base_prompt.length > 2048  # Min for caching
      blocks << {
        type: "text",
        text: @base_prompt,
        cache_control: { 
          type: "ephemeral",
          ttl: "1h"  # Correct format for 1 hour
        }
      }
      track_cache_block('system_prompt', @base_prompt.length, '1h')
    end
    
    # Block 2: Essential files (5 minute cache - may change during session)
    if @template_files.any?
      essential_content = build_essential_files_content
      if essential_content.length > 2048
        blocks << {
          type: "text",
          text: essential_content,
          cache_control: {
            type: "ephemeral",
            ttl: "5m"  # Correct format for 5 minutes
          }
        }
        track_cache_block('essential_files', essential_content.length, '5m')
      end
    end
    
    # Block 3: Dynamic context (no cache - user-specific)
    if @context_data[:user_context].present?
      blocks << {
        type: "text",
        text: @context_data[:user_context]
        # No cache_control = not cached
      }
      track_cache_block('user_context', @context_data[:user_context].length, nil)
    end
    
    log_cache_efficiency(blocks)
    blocks
  end
  
  private
  
  def track_cache_block(name, size, ttl)
    # Send to Helicone via custom properties
    @cache_metrics ||= {}
    @cache_metrics[name] = {
      size: size,
      ttl: ttl,
      cost_multiplier: ttl == '1h' ? 2.0 : (ttl == '5m' ? 1.25 : 1.0)
    }
  end
  
  def log_cache_efficiency(blocks)
    total_chars = blocks.sum { |b| b[:text].length }
    cached_blocks = blocks.select { |b| b[:cache_control] }
    cached_chars = cached_blocks.sum { |b| b[:text].length }
    
    efficiency = {
      total_tokens: total_chars / 4,
      cached_tokens: cached_chars / 4,
      cache_ratio: (cached_chars.to_f / total_chars * 100).round(1),
      blocks: {
        total: blocks.count,
        cached_1h: cached_blocks.count { |b| b.dig(:cache_control, :ttl) == '1h' },
        cached_5m: cached_blocks.count { |b| b.dig(:cache_control, :ttl) == '5m' }
      }
    }
    
    # Log for local monitoring
    Rails.logger.info "[CACHE_EFFICIENCY] #{efficiency.to_json}"
    
    # Store in Redis for dashboard
    Redis.current.hset("cache:metrics:#{Time.current.to_i}", efficiency)
    
    efficiency
  end
end
```

### Phase 4: Helicone Metrics Dashboard

```ruby
# app/controllers/admin/metrics_controller.rb

class Admin::MetricsController < Admin::BaseController
  def index
    @metrics = {
      token_usage: fetch_token_metrics,
      cache_performance: fetch_cache_metrics,
      file_optimization: fetch_file_metrics,
      cost_analysis: fetch_cost_metrics
    }
  end
  
  private
  
  def fetch_token_metrics
    # From Helicone API
    if ENV['HELICONE_API_KEY'].present?
      response = HTTParty.get(
        "https://api.helicone.ai/v1/metrics/usage",
        headers: { 
          "Authorization" => "Bearer #{ENV['HELICONE_API_KEY']}"
        },
        query: {
          timeFilter: { 
            start: 24.hours.ago.iso8601,
            end: Time.current.iso8601
          }
        }
      )
      
      if response.success?
        {
          total_tokens: response['data']['totalTokens'],
          cached_tokens: response['data']['cachedTokens'],
          cache_hit_rate: response['data']['cacheHitRate'],
          avg_tokens_per_request: response['data']['avgTokensPerRequest']
        }
      end
    else
      # Fallback to local Redis metrics
      {
        total_tokens: Redis.current.get('metrics:total_tokens')&.to_i || 0,
        cached_tokens: Redis.current.get('metrics:cached_tokens')&.to_i || 0,
        cache_hit_rate: Redis.current.get('metrics:cache_hit_rate')&.to_f || 0
      }
    end
  end
  
  def fetch_cache_metrics
    # Get latest cache efficiency from Redis
    latest_key = Redis.current.keys("cache:metrics:*").max
    latest_key ? Redis.current.hgetall(latest_key) : {}
  end
  
  def fetch_file_metrics
    {
      avg_files_per_app: App.joins(:app_files).group(:app_id).count.values.sum / App.count.to_f,
      on_demand_loads: Redis.current.zrevrange("global:on_demand_files", 0, 9, with_scores: true),
      optimization_savings: calculate_file_savings
    }
  end
  
  def calculate_file_savings
    original_files = 84
    optimized_files = App.last&.app_files&.count || 15
    {
      files_reduced: original_files - optimized_files,
      percentage: ((1 - optimized_files.to_f / original_files) * 100).round,
      storage_saved_mb: ((original_files - optimized_files) * 0.01).round(2) # Avg 10KB per file
    }
  end
end
```

### Phase 5: Monitoring & Alerts

```ruby
# lib/tasks/metrics.rake

namespace :metrics do
  desc "Monitor token usage and alert on anomalies"
  task monitor: :environment do
    # Check token usage
    recent_generations = AppChatMessage.where(created_at: 1.hour.ago..Time.current)
    
    recent_generations.each do |message|
      if message.metadata['total_tokens']&.to_i > 30_000
        Rails.logger.error "[TOKEN_ALERT] High token usage: #{message.metadata['total_tokens']} for message #{message.id}"
        
        # Send to Slack/Discord
        notify_high_token_usage(message)
      end
    end
    
    # Check cache hit rate
    cache_hit_rate = Redis.current.get('metrics:cache_hit_rate')&.to_f || 0
    if cache_hit_rate < 0.5 && recent_generations.count > 10
      Rails.logger.warn "[CACHE_ALERT] Low cache hit rate: #{(cache_hit_rate * 100).round}%"
    end
  end
  
  desc "Generate optimization report"
  task report: :environment do
    puts "\n=== OPTIMIZATION REPORT ==="
    puts "Generated: #{Time.current}"
    puts
    
    # File optimization
    apps_with_counts = App.joins(:app_files).group(:app_id).count
    puts "File Optimization:"
    puts "  Average files per app: #{(apps_with_counts.values.sum / apps_with_counts.count.to_f).round}"
    puts "  Original template files: 84"
    puts "  Reduction: #{((1 - apps_with_counts.values.sum / apps_with_counts.count.to_f / 84) * 100).round}%"
    puts
    
    # On-demand loading patterns
    puts "Top 10 On-Demand Loaded Files:"
    Redis.current.zrevrange("global:on_demand_files", 0, 9, with_scores: true).each do |file, count|
      puts "  #{file}: #{count.to_i} times"
    end
    puts
    
    # Cost analysis
    puts "Cost Analysis (last 24h):"
    if ENV['HELICONE_API_KEY'].present?
      # Get from Helicone
      puts "  See Helicone dashboard: https://app.helicone.ai/dashboard"
    else
      puts "  Configure HELICONE_API_KEY for detailed cost analysis"
    end
  end
end
```

## 🚨 Deployment Verification Checklist

Before deploying this optimization:

1. **Test file loading**
   ```bash
   rails console
   app = App.create(name: "Test")
   app.copy_optimized_template_files
   # Verify essential files are copied
   app.app_files.count # Should be ~15 not 84
   ```

2. **Test on-demand loading**
   ```ruby
   # Simulate AI loading a component
   service = Ai::AiToolService.new(app)
   content = service.handle_os_view("src/components/ui/dialog.tsx")
   # Verify file is saved to app_files
   app.app_files.where(path: "src/components/ui/dialog.tsx").exists? # Should be true
   ```

3. **Test deployment**
   ```ruby
   # Ensure all app_files get deployed
   DeployAppJob.perform_now(app)
   # Check GitHub repo has all files
   ```

4. **Monitor metrics**
   ```bash
   # Run monitoring task
   rake metrics:monitor
   rake metrics:report
   ```

## ✅ Safety Guarantees

1. **Files always saved**: On-demand loaded files are saved to `app_files`
2. **Deployment unchanged**: DeployAppJob still syncs all `app_files` to GitHub
3. **Fallback available**: If file loading fails, template is still accessible
4. **Metrics tracked**: Helicone + Redis tracking for monitoring
5. **TTL correct**: Using only 5m and 1h as supported by Anthropic

## 📊 Expected Results

- **Initial files**: 15 instead of 84 (82% reduction)
- **Final files**: ~25-30 after on-demand loading (still 64% reduction)
- **Token usage**: 8-10k instead of 76k (87% reduction)
- **Cache hit rate**: 80%+ with proper TTL settings
- **Cost**: 90% reduction with caching

This implementation ensures all files needed for deployment are included while optimizing initial load and token usage.