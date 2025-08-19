# V5 Cost Optimization Analysis & Implementation Plan

**Current Issue**: 5-10% cost-to-revenue ratio with 300k+ character uncached contexts  
**Target**: Reduce to <1% cost-to-revenue ratio while maintaining quality

## Root Cause Analysis

### 1. **Massive Context Bloat** - Primary Cost Driver 🚨

**BaseContextService** loads ALL template files into every API call:

```ruby
# Currently loaded in EVERY call:
ESSENTIAL_FILES = [
  "src/index.css",           # ~5,000 chars
  "tailwind.config.ts",      # ~2,000 chars  
  "index.html",              # ~1,000 chars
  "src/App.tsx",             # ~8,000 chars
  "src/pages/Index.tsx",     # ~3,000 chars
  # ... 8 more essential files
]

COMMON_UI_COMPONENTS = [
  "src/components/ui/form.tsx",        # ~12,000 chars
  "src/components/ui/input.tsx",       # ~3,000 chars
  "src/components/ui/textarea.tsx",    # ~2,500 chars
  # ... 20+ more UI components
]
```

**Estimated Total**: 300,000+ characters per API call  
**Cost Impact**: $0.53 per generation (your dashboard shows this exact figure)

### 2. **Single Tool Call Limitation** - Efficiency Issue

Current prompt doesn't encourage tool batching:
- Multiple `os-line-replace` calls require separate API roundtrips
- Each roundtrip includes full 300k context again
- 3-5 tool cycles per generation = 3-5x cost multiplier

### 3. **No Context Selectivity** - Waste Issue

Loading components never used:
- Avatar components for non-user apps
- Form components for display-only apps  
- Chart components for simple tools
- 70% of template files unused per generation

## Optimization Strategy

### Phase 1: Context Reduction (90% cost savings) 🎯

#### A. Implement Just-In-Time Context Loading

```ruby
class OptimizedContextService
  def build_minimal_context(user_request, app_type)
    # Analyze request to determine ONLY needed files
    required_files = ComponentRequirementsAnalyzer.analyze(user_request)
    
    # Load only essential core + needed components
    context = load_core_files(3) # Only 3 essential files
    context += load_components_by_need(required_files[:required_shadcn])
    
    # ~30k chars instead of 300k
  end
  
  private
  
  def load_core_files(limit = 3)
    # Only absolute essentials:
    # 1. src/index.css (design system)
    # 2. src/App.tsx (routing structure)  
    # 3. package.json (dependencies)
  end
end
```

#### B. Smart Component Loading

```ruby
APP_TYPE_COMPONENTS = {
  'todo' => %w[input checkbox button card],
  'landing' => %w[button card badge],
  'dashboard' => %w[table select dropdown-menu avatar],
  'form' => %w[form input textarea select button]
}

def get_components_for_app_type(type)
  APP_TYPE_COMPONENTS[type] || APP_TYPE_COMPONENTS['landing']
end
```

### Phase 2: Tool Call Batching (50% fewer API calls) 🚀

#### A. Enhanced Agent Prompt for Batching

```markdown
## CRITICAL: Tool Call Batching for Efficiency

**ALWAYS batch multiple file operations in a single response:**

✅ GOOD - Multiple tools in one response:
```
I'll implement the todo app by creating these files:

<tool_use>
<name>os-create-file</name>
<parameters>{"path": "src/components/TodoList.tsx", "content": "..."}</parameters>
</tool_use>

<tool_use>
<name>os-create-file</name>
<parameters>{"path": "src/components/TodoItem.tsx", "content": "..."}</parameters>
</tool_use>

<tool_use>
<name>os-line-replace</name>
<parameters>{"path": "src/App.tsx", "old_string": "...", "new_string": "..."}</parameters>
</tool_use>
```

❌ BAD - Single tool per response:
```
I'll start by creating the TodoList component:

<tool_use>
<name>os-create-file</name>
<parameters>{"path": "src/components/TodoList.tsx", "content": "..."}</parameters>
</tool_use>
```

**BATCH UP TO 5-8 FILE OPERATIONS** in every response for maximum efficiency.
```

#### B. Tool Batching Validation

```ruby
def validate_tool_batching_in_prompt
  if response[:tool_calls].size == 1 && @iteration_count == 1
    Rails.logger.warn "[V5_EFFICIENCY] Single tool call detected - consider prompt optimization"
  end
end
```

### Phase 3: Context Caching Optimization (80% cache hit rate) 📈

#### A. Granular Component Caching

```ruby
class GranularComponentCache
  def cache_component(component_name, content)
    # Cache individual UI components for reuse
    cache_key = "ui_component:#{component_name}:#{content_hash(content)}"
    Rails.cache.write(cache_key, content, expires_in: 24.hours)
  end
  
  def build_selective_context(required_components)
    # Use cached components when available
    context = required_components.map do |comp|
      cache_key = "ui_component:#{comp}:latest"
      Rails.cache.fetch(cache_key) { load_component(comp) }
    end.join("\n")
  end
end
```

#### B. App-Type Context Templates

```ruby
CACHED_CONTEXTS = {
  'todo' => proc { build_todo_context },      # Cache for 1 hour
  'landing' => proc { build_landing_context }, # Cache for 1 hour  
  'dashboard' => proc { build_dashboard_context }
}

def get_cached_context_for_app_type(type)
  Rails.cache.fetch("app_context:#{type}", expires_in: 1.hour) do
    CACHED_CONTEXTS[type]&.call || build_default_context
  end
end
```

### Phase 4: Agent Prompt Optimization 🎯

#### A. Cost-Conscious Instructions

```markdown
## Cost Optimization Guidelines

1. **Batch Operations**: Always use multiple tools in single responses
2. **Reference Files**: Use provided context instead of os-view when possible  
3. **Efficient Imports**: Use import templates from context instead of asking for components
4. **Focused Changes**: Make targeted edits instead of rewriting entire files
```

#### B. Template Reference System

```markdown
## Available Components (Use Without os-view)

Based on your request type, these components are available in context:

**For Todo Apps**: Button, Input, Checkbox, Card
**For Landing Pages**: Button, Card, Badge, Tabs
**For Dashboards**: Table, Select, Avatar, DropdownMenu

Reference these directly from the context above instead of using os-view.
```

## Implementation Plan

### Week 1: Context Reduction
- [ ] Implement `OptimizedContextService`
- [ ] Add app-type detection to context loading
- [ ] Deploy selective component loading
- [ ] **Expected Savings**: 70-80% cost reduction

### Week 2: Tool Batching  
- [ ] Update agent prompt for tool batching
- [ ] Add batching validation and metrics
- [ ] Test tool batching effectiveness
- [ ] **Expected Savings**: Additional 40-50% API call reduction

### Week 3: Caching Enhancement
- [ ] Implement granular component caching
- [ ] Add app-type context templates
- [ ] Monitor cache hit rates
- [ ] **Expected Savings**: Additional 60-70% cache efficiency

### Week 4: Optimization & Monitoring
- [ ] Add cost tracking per generation
- [ ] Implement cost alerts and budgets
- [ ] A/B test optimized vs current system
- [ ] **Target**: <1% cost-to-revenue ratio

## Immediate Quick Wins (Can implement today)

### 1. Reduce Essential Files (30 minutes)
```ruby
# In BaseContextService, reduce ESSENTIAL_FILES to only:
ESSENTIAL_FILES = [
  "src/index.css",     # Design system
  "src/App.tsx",       # Routing structure  
  "package.json"       # Dependencies
].freeze

# Comment out COMMON_UI_COMPONENTS temporarily
# Load components only when ComponentRequirementsAnalyzer determines need
```

### 2. Add Tool Batching Reminder (15 minutes)
```ruby
# In agent-prompt.txt, add prominent section:
"## EFFICIENCY: ALWAYS batch 3-5 file operations per response for cost optimization"
```

### 3. Context Size Monitoring (20 minutes)
```ruby
def log_context_metrics(context)
  context_size = context.to_s.length
  Rails.logger.warn "[V5_COST] Context size: #{context_size} chars" if context_size > 50_000
  
  # Alert if over threshold
  if context_size > 100_000
    Rails.logger.error "[V5_COST] CONTEXT BLOAT: #{context_size} chars - urgent optimization needed"
  end
end
```

## Expected Results

### Current State:
- **Cost per generation**: $0.53 (your dashboard data)
- **Context size**: 300k+ characters
- **Tool calls per generation**: 3-5 separate API calls
- **Cost-to-revenue ratio**: 5-10%

### Optimized State:
- **Cost per generation**: $0.05-0.08 (90% reduction)
- **Context size**: 30k-50k characters (85% reduction)  
- **Tool calls per generation**: 1-2 batched API calls (60% reduction)
- **Cost-to-revenue ratio**: <1% (target achieved)

## Risk Mitigation

### Quality Concerns:
- **A/B testing**: Run optimized system alongside current for comparison
- **Quality metrics**: Track app generation success rates
- **Rollback plan**: Keep current system as fallback

### Caching Issues:
- **Cache invalidation**: Expire caches when templates update
- **Cache warming**: Pre-populate popular component combinations
- **Cache monitoring**: Track hit rates and performance

### Tool Batching Failures:
- **Fallback logic**: Revert to single tool calls if batching fails
- **Prompt tuning**: Iteratively improve batching instructions
- **Success tracking**: Monitor tool batch success rates

## Success Metrics

### Primary KPIs:
1. **Cost per generation**: <$0.10 (90% reduction)
2. **Cost-to-revenue ratio**: <1% (10x improvement)
3. **Context size**: <50k characters (85% reduction)

### Secondary KPIs:
1. **Cache hit rate**: >80%
2. **Tool batch size**: 3-5 tools per response
3. **Generation quality**: Maintain 95%+ success rate

### Monitoring Dashboard:
- Real-time cost tracking per generation
- Context size alerts (>50k chars)
- Tool batching effectiveness
- Cache performance metrics

This optimization plan addresses the root causes identified in your cost analysis and provides a clear path to <1% cost-to-revenue ratio while maintaining generation quality.