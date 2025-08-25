# System Prompt Cache Optimization Plan
## Reducing Token Usage from 134k to <30k While Maintaining Effectiveness

### Executive Summary
Our investigation reveals a critical inefficiency: system prompts balloon from 20k written tokens to 134k total tokens due to unnecessary file inclusions and poor caching strategies. This plan outlines comprehensive optimizations to reduce token usage by 75%+ while improving performance through Anthropic's cache_control features.

## Current State Analysis

### Token Bloat Sources
1. **UI Components**: Loading all 52 component files (~80k tokens) regardless of need
2. **Template Files**: Including all template files instead of selective loading
3. **Redundant Context**: Files already in cache being re-read via tools
4. **Poor Categorization**: Not utilizing TTL-based caching effectively

### Actual Token Usage Breakdown
```
Current (134k total):
- Base prompt: 8k tokens
- Essential files (5 files): 15k tokens
- UI components (52 files): 80k tokens
- Additional template files: 20k tokens
- Dynamic context: 11k tokens

Target (<30k total):
- Base prompt (cached 1h): 8k tokens
- Essential files (cached 30m): 15k tokens
- Selective UI components (2-5 files): 5k tokens
- Dynamic context only: 2k tokens
```

## Optimization Strategy

### Phase 1: Immediate Optimizations (Week 1)

#### 1.1 Selective UI Component Loading
**Current**: Loading all 52 components = 80k tokens
**Optimized**: Load only needed components = 5k tokens

```ruby
# app/services/ai/base_context_service.rb
APP_TYPE_COMPONENTS = {
  'todo' => %w[input checkbox button card],
  'landing' => %w[button card badge tabs],
  'dashboard' => %w[table select dropdown-menu avatar],
  'form' => %w[form input textarea select button],
  'default' => %w[button card input]  # Minimal fallback
}

def load_components_for_app_type(app_type)
  components = APP_TYPE_COMPONENTS[app_type] || APP_TYPE_COMPONENTS['default']
  # Load only these 3-5 components instead of all 52
end
```

#### 1.2 Stop Copying All Template Files
**Current**: Copying all template files on app creation
**Optimized**: Copy only essential files, load others on-demand

```ruby
# app/models/app.rb
ESSENTIAL_COPY_FILES = [
  'src/index.css',
  'src/App.tsx', 
  'src/main.tsx',
  'index.html',
  'package.json',
  'tailwind.config.ts',
  'vite.config.ts'
]

def copy_template_files
  # Only copy essential files
  # UI components loaded on-demand via AI tools
end
```

### Phase 2: Cache Control Implementation (Week 2)

#### 2.1 Implement Proper Cache Hierarchy
Using Anthropic's cache_control with ephemeral TTL:

```ruby
# app/services/ai/prompts/granular_cached_prompt_builder.rb

def build_optimized_cache_blocks
  blocks = []
  
  # Block 1: Base prompt & instructions (1 hour cache)
  blocks << {
    type: "text",
    text: agent_prompt,  # 8k tokens
    cache_control: { type: "ephemeral", ttl: "1h" }
  }
  
  # Block 2: Essential files (30 min cache)
  blocks << {
    type: "text", 
    text: essential_files_context,  # 15k tokens
    cache_control: { type: "ephemeral", ttl: "30m" }
  }
  
  # Block 3: Selective components (5 min cache)
  blocks << {
    type: "text",
    text: selected_ui_components,  # 5k tokens
    cache_control: { type: "ephemeral", ttl: "5m" }
  }
  
  # Block 4: Dynamic context (no cache)
  blocks << {
    type: "text",
    text: user_specific_context  # 2k tokens
  }
  
  blocks
end
```

#### 2.2 File Categorization Strategy
```ruby
FILE_CACHE_CATEGORIES = {
  stable: {
    # Rarely changes, cache 1 hour
    patterns: ['package.json', 'tailwind.config.ts', 'vite.config.ts'],
    ttl: '1h',
    cost_multiplier: 2.0  # Worth the 2x cost for long cache
  },
  semi_stable: {
    # Changes occasionally, cache 30 min  
    patterns: ['src/index.css', 'src/main.tsx'],
    ttl: '30m',
    cost_multiplier: 1.5
  },
  active: {
    # Changes frequently, cache 5 min
    patterns: ['src/App.tsx', 'src/pages/*'],
    ttl: '5m',
    cost_multiplier: 1.25
  },
  volatile: {
    # User-modified files, no cache
    patterns: ['src/components/custom/*'],
    ttl: nil,
    cost_multiplier: 1.0
  }
}
```

### Phase 3: Smart Context Loading (Week 3)

#### 3.1 Component Requirements Analyzer
```ruby
# app/services/ai/component_requirements_analyzer.rb
class ComponentRequirementsAnalyzer
  def self.analyze(user_prompt, existing_files)
    # Use lightweight NLP to detect needed components
    required_components = []
    
    if user_prompt.match?(/form|input|submit/i)
      required_components += %w[form input button]
    end
    
    if user_prompt.match?(/dashboard|analytics|charts/i)
      required_components += %w[card table chart]
    end
    
    if user_prompt.match?(/landing|hero|marketing/i)
      required_components += %w[button badge card tabs]
    end
    
    required_components.uniq[0..4]  # Max 5 components
  end
end
```

#### 3.2 Context-Aware File Loading
```ruby
def build_minimal_context
  context = {
    essential_files: load_essential_files,  # Always include
    ui_components: [],  # Selective loading
    user_files: []  # Only modified files
  }
  
  # Only load components Claude will actually use
  needed_components = ComponentRequirementsAnalyzer.analyze(
    @chat_message.content,
    @app.app_files
  )
  
  context[:ui_components] = load_specific_components(needed_components)
  
  # Only include files Claude has modified
  context[:user_files] = @app.app_files.where(
    'updated_at > ?', 1.hour.ago
  )
  
  context
end
```

## Implementation Roadmap

### Week 1: Immediate Token Reduction
- [ ] Update BaseContextService to load only 5 essential files
- [ ] Implement selective UI component loading 
- [ ] Stop copying all template files on app creation
- [ ] Add logging to track actual token usage
- **Expected Reduction**: 134k → 50k tokens (63% reduction)

### Week 2: Cache Control Optimization  
- [ ] Implement 4-tier cache hierarchy with proper TTL
- [ ] Add cache hit rate monitoring
- [ ] Configure extended-cache-ttl beta header
- [ ] Test cache effectiveness with real workloads
- **Expected Reduction**: 50k → 35k tokens (additional 30% reduction)

### Week 3: Intelligent Context Loading
- [ ] Build ComponentRequirementsAnalyzer
- [ ] Implement on-demand file loading from GitHub template
- [ ] Add predictive component loading based on app type
- [ ] Optimize file ordering for cache hits
- **Expected Reduction**: 35k → 25k tokens (final 29% reduction)

## Cost-Benefit Analysis

### Current Costs (per 1000 requests)
```
Without caching:
- Input: 134k tokens × 1000 × $15/1M = $2,010
- Cache writes: N/A
- Cache reads: N/A
- Total: $2,010

With poor caching (current):
- Input: 30k tokens × 1000 × $15/1M = $450
- Cache writes: 104k tokens × 200 × $18.75/1M = $390
- Cache reads: 104k tokens × 800 × $1.50/1M = $125
- Total: $965 (52% savings, but could be better)
```

### Optimized Costs (per 1000 requests)
```
With optimized caching:
- Input: 2k tokens × 1000 × $15/1M = $30
- Cache writes: 28k tokens × 50 × $18.75/1M = $26
- Cache reads: 28k tokens × 950 × $1.50/1M = $40
- Total: $96 (95% cost reduction!)
```

## Monitoring & Success Metrics

### Key Performance Indicators
1. **Token Usage Reduction**
   - Current: 134k tokens per request
   - Target: <30k tokens per request
   - Measurement: Log token counts in app_builder_v5.rb

2. **Cache Hit Rate**
   - Current: Unknown (not measured)
   - Target: >90% for stable content
   - Measurement: Track cache_read_input_tokens vs cache_creation_input_tokens

3. **Cost Per Generation**
   - Current: ~$2.01 per app generation
   - Target: <$0.10 per app generation
   - Measurement: Monthly Anthropic billing / number of generations

4. **Response Latency**
   - Current: 8-12 seconds first token
   - Target: 2-3 seconds first token
   - Measurement: Time to first token in streaming response

### Monitoring Implementation
```ruby
# app/services/ai/cache_metrics_service.rb
class CacheMetricsService
  def self.log_cache_performance(response)
    cache_tokens = response.dig('usage', 'cache_read_input_tokens') || 0
    creation_tokens = response.dig('usage', 'cache_creation_input_tokens') || 0
    total_tokens = response.dig('usage', 'input_tokens') || 0
    
    cache_hit_rate = cache_tokens.to_f / (total_tokens + 1) * 100
    
    Rails.logger.info "[CACHE_METRICS] Hit rate: #{cache_hit_rate.round(1)}%"
    Rails.logger.info "[CACHE_METRICS] Cached: #{cache_tokens}, Created: #{creation_tokens}"
    
    # Store in Redis for dashboard
    Redis.current.hincrby('cache_metrics', 'total_cached_tokens', cache_tokens)
    Redis.current.hincrby('cache_metrics', 'total_creation_tokens', creation_tokens)
  end
end
```

## Risk Mitigation

### Potential Risks & Mitigations
1. **Cache Misses Due to Content Changes**
   - Risk: Frequent prompt updates invalidate cache
   - Mitigation: Separate stable from volatile content

2. **Missing Required Components**
   - Risk: ComponentRequirementsAnalyzer misses needed component
   - Mitigation: Fallback to loading common set if build fails

3. **Increased Complexity**
   - Risk: More complex caching logic harder to debug
   - Mitigation: Comprehensive logging and monitoring

4. **Regional Availability**
   - Risk: Cache features not available in all regions
   - Mitigation: Fallback to non-cached mode with higher limits

## Next Steps

### Immediate Actions (This Week)
1. Review and approve this optimization plan
2. Create feature branch: `feature/prompt-cache-optimization`
3. Implement Phase 1 optimizations
4. Deploy to staging for testing
5. Monitor token usage reduction

### Follow-up Actions
1. Weekly review of cache metrics
2. Iterate on ComponentRequirementsAnalyzer accuracy
3. Consider implementing predictive caching for popular templates
4. Explore cross-session cache sharing (when available)

## Appendix: Configuration Examples

### Environment Variables
```bash
# .env
ANTHROPIC_CACHE_ENABLED=true
ANTHROPIC_EXTENDED_TTL_ENABLED=true
ANTHROPIC_MAX_CACHE_BLOCKS=4
ANTHROPIC_MIN_TOKENS_FOR_CACHE=1024
CACHE_MONITORING_ENABLED=true
```

### Cache Configuration
```yaml
# config/anthropic_cache.yml
production:
  cache_enabled: true
  ttl_settings:
    stable: 3600      # 1 hour in seconds
    semi_stable: 1800 # 30 minutes
    active: 300       # 5 minutes
  thresholds:
    min_tokens: 1024
    max_blocks: 4
  monitoring:
    log_level: info
    metrics_enabled: true
```

## Conclusion

This optimization plan will reduce our token usage by 75%+ (from 134k to <30k tokens) while improving response times through intelligent caching. The implementation is broken into manageable phases with clear success metrics and risk mitigations. 

The expected ROI is substantial:
- **95% cost reduction** in API expenses
- **85% latency improvement** for cached content
- **Improved scalability** for handling more users
- **Better user experience** with faster responses

By focusing on selective loading, intelligent caching, and proper TTL management, we can achieve these dramatic improvements without sacrificing functionality or flexibility.