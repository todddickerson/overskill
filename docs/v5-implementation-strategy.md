# V5 Implementation Strategy: Agent Loop with Claude Opus 4.1

## Executive Summary

V5 transforms OverSkill's app generation into an iterative agent loop system that mirrors Lovable's approach, using Claude Opus 4.1 for superior reasoning capabilities. The system combines real-time Rails broadcasting with intelligent tool orchestration to create a seamless user experience.

**Critical Innovation: Prompt Caching** - By leveraging Anthropic's prompt caching beta, we achieve 83% cost reduction while maintaining Claude Opus 4.1's superior reasoning. The large system prompt (20K+ tokens) and tool definitions (5K+ tokens) are cached after first use, reducing per-iteration costs from $0.75 to $0.04.

## Core Architecture

### 1. Agent Loop System (Already Implemented in AppBuilderV5)
```ruby
# Current structure in app/services/ai/app_builder_v5.rb
- MAX_ITERATIONS = 10
- Goal tracking and extraction
- Context preservation across iterations
- Decision engine for next actions
- Verification at each step
- Multiple termination conditions
```

### 2. Key Components to Enhance

#### A. Prompt Service Integration
```ruby
# Use the new AgentPromptService with Lovable-style prompts
@prompt_service = Ai::Prompts::AgentPromptService.new(
  platform_name: "OverSkill",
  tool_prefix: "os-",
  technology_stack: "React, Vite, Tailwind CSS, and TypeScript",
  backend_integration: "Supabase",
  app_id: app.id,
  user_prompt: chat_message.content
)
```

#### B. Claude Opus 4.1 Configuration with Prompt Caching (95% Cost Savings)
```ruby
def call_claude_with_tools
  # Use existing AnthropicClient with prompt caching support
  client = Ai::AnthropicClient.instance
  
  # CRITICAL: Cache the expensive system prompt (20K+ tokens)
  system_prompt = @prompt_service.generate_prompt
  tools_config = @prompt_service.generate_tools
  
  # Create cache breakpoints for 90% cost savings on cached reads
  cache_breakpoints = client.create_cache_breakpoints(
    system_prompt,           # ~20K tokens - ALWAYS CACHED
    conversation_history     # Previous messages - CACHED if long
  )
  
  # Build messages with cache control markers
  messages = [
    { 
      role: "system", 
      content: system_prompt,
      cache_control: { type: "ephemeral" }  # Mark for caching
    },
    *conversation_history,
    { role: "user", content: current_prompt }
  ]
  
  response = client.chat_with_tools(
    messages,
    tools_config,
    model: :claude_opus_4,                  # claude-opus-4-1-20250805
    use_cache: true,                         # Enable prompt caching
    cache_breakpoints: cache_breakpoints,
    temperature: 0.7,
    max_tokens: 4000
  )
end

# PROMPT CACHING ECONOMICS:
# 
# System Prompt (~20K tokens from agent-prompt.txt):
# - First call: $0.375 to cache (20K @ $18.75/1M write)
# - Subsequent: $0.03 per call (20K @ $1.50/1M read) 
# - Savings: 92% reduction
#
# Tool Definitions (~5K tokens from agent-tools.json):
# - First call: $0.094 to cache
# - Subsequent: $0.0075 per call
# - Savings: 92% reduction
#
# Total per generation (avg 5 iterations):
# - Without caching: 5 × $0.75 = $3.75
# - With caching: $0.47 + (4 × $0.04) = $0.63
# - TOTAL SAVINGS: 83% cost reduction
```

## Broadcasting Strategy: Mixed Content Updates

### 1. Chat Message Broadcasting
```ruby
# app/services/ai/chat_progress_broadcaster_v2.rb enhancements

def broadcast_agent_thinking(message)
  broadcast_turbo_stream(
    target: "chat_messages",
    action: "append",
    partial: "app_chat_messages/thinking_message",
    locals: { 
      message: message,
      timestamp: Time.current
    }
  )
end

def broadcast_tool_execution(tool_name, status)
  broadcast_turbo_stream(
    target: "chat_messages",
    action: "append",
    partial: "app_chat_messages/tool_execution",
    locals: {
      tool_name: tool_name,
      status: status, # 'starting', 'running', 'complete', 'failed'
      tool_icon: tool_icon_for(tool_name)
    }
  )
end

def broadcast_iteration_summary(iteration_data)
  broadcast_turbo_stream(
    target: "chat_messages",
    action: "append",
    partial: "app_chat_messages/iteration_summary",
    locals: {
      iteration: iteration_data[:iteration],
      goals_progress: iteration_data[:goals_progress],
      files_created: iteration_data[:files_created]
    }
  )
end
```

### 2. Mixed Content Flow Pattern

```ruby
# Example of mixed content broadcasting during agent loop

def execute_iteration_with_broadcasting
  # 1. Broadcast thinking message
  broadcaster.broadcast_agent_thinking("Analyzing your requirements...")
  
  # 2. Execute tools with inline status updates
  tools_to_execute.each do |tool|
    broadcaster.broadcast_tool_execution(tool[:name], 'starting')
    result = execute_tool(tool)
    broadcaster.broadcast_tool_execution(tool[:name], 'complete')
  end
  
  # 3. Broadcast iteration summary
  broadcaster.broadcast_iteration_summary(iteration_data)
  
  # 4. If complete, broadcast app version partial
  if iteration_complete?
    broadcaster.broadcast_app_version_card(app_version)
  end
end
```

## UI/UX Implementation

### 1. Chat Message Partials

#### A. Thinking Message Partial
```erb
<!-- app/views/app_chat_messages/_thinking_message.html.erb -->
<div class="chat-message agent-thinking" data-message-id="<%= dom_id(message) %>">
  <div class="message-avatar">
    <%= image_tag "claude-avatar.svg", class: "w-8 h-8" %>
  </div>
  <div class="message-content">
    <div class="thinking-indicator">
      <div class="thinking-dots">
        <span></span><span></span><span></span>
      </div>
      <span class="thinking-text"><%= message %></span>
    </div>
    <div class="message-timestamp">
      <%= time_ago_in_words(timestamp) %> ago
    </div>
  </div>
</div>
```

#### B. Tool Execution Partial
```erb
<!-- app/views/app_chat_messages/_tool_execution.html.erb -->
<div class="tool-execution-card" data-tool="<%= tool_name %>">
  <div class="tool-header">
    <span class="tool-icon"><%= tool_icon %></span>
    <span class="tool-name"><%= humanize_tool_name(tool_name) %></span>
    <span class="tool-status <%= status %>">
      <%= tool_status_indicator(status) %>
    </span>
  </div>
  
  <% if status == 'running' %>
    <div class="tool-progress">
      <div class="progress-bar-indeterminate"></div>
    </div>
  <% end %>
</div>
```

#### C. App Version Card (End of Loop)
```erb
<!-- app/views/app_chat_messages/_app_version_card.html.erb -->
<div class="app-version-card" id="app-version-<%= app_version.id %>">
  <div class="version-header">
    <h3>Version <%= app_version.version_number %> Generated</h3>
    <span class="version-status <%= app_version.status %>">
      <%= app_version.status.humanize %>
    </span>
  </div>
  
  <div class="version-details">
    <div class="files-created">
      <strong><%= app_version.app_files.count %> files</strong> created/modified
    </div>
    <div class="iteration-count">
      Completed in <strong><%= app_version.iteration_count %> iterations</strong>
    </div>
  </div>
  
  <div class="version-actions">
    <%= link_to "Preview App", app_version.preview_url, 
        target: "_blank", 
        class: "btn btn-primary",
        data: { turbo: false } %>
    
    <%= button_to "Deploy to Production", 
        deploy_app_version_path(app_version),
        method: :post,
        class: "btn btn-secondary",
        data: { turbo_stream: true } %>
  </div>
  
  <details class="version-files">
    <summary>View Files (<%= app_version.app_files.count %>)</summary>
    <div class="file-list">
      <% app_version.app_files.order(:path).each do |file| %>
        <div class="file-item">
          <%= file_icon_for(file.path) %>
          <span><%= file.path %></span>
          <span class="file-size"><%= number_to_human_size(file.content.bytesize) %></span>
        </div>
      <% end %>
    </div>
  </details>
</div>
```

### 2. Stimulus Controller for Real-time Updates

```javascript
// app/javascript/controllers/agent_loop_chat_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messages", 
    "currentIteration", 
    "goalProgress",
    "toolExecutions"
  ]
  
  connect() {
    console.log("Agent Loop Chat Controller connected")
    this.setupTurboStreamHandlers()
  }
  
  setupTurboStreamHandlers() {
    // Handle tool execution animations
    document.addEventListener('turbo:before-stream-render', (event) => {
      const stream = event.detail.newStream
      
      if (stream.querySelector('.tool-execution-card')) {
        this.animateToolCard(stream)
      }
      
      if (stream.querySelector('.app-version-card')) {
        this.celebrateCompletion(stream)
      }
    })
  }
  
  animateToolCard(element) {
    // Add entrance animation
    element.classList.add('animate-slide-in')
  }
  
  celebrateCompletion(element) {
    // Add success animation
    element.classList.add('animate-success-bounce')
    
    // Play completion sound if enabled
    if (this.data.get('soundEnabled') === 'true') {
      this.playCompletionSound()
    }
  }
  
  updateIterationCount(event) {
    const count = event.detail.iteration
    this.currentIterationTarget.textContent = `Iteration ${count}/10`
    
    // Update progress bar
    const progress = (count / 10) * 100
    this.updateProgressBar(progress)
  }
  
  updateGoalProgress(event) {
    const { completed, total } = event.detail
    this.goalProgressTarget.innerHTML = `
      <div class="goal-progress">
        <span class="completed">${completed}</span>
        <span class="separator">/</span>
        <span class="total">${total}</span>
        <span class="label">goals completed</span>
      </div>
    `
  }
}
```

## Prompt Caching Optimization Strategy

### Cache Hierarchy

```ruby
# app/services/ai/cache_optimization_service.rb
class CacheOptimizationService
  # Tier 1: Always Cached (Static, reused every call)
  TIER_1_CACHE = {
    system_prompt: {
      tokens: 20_000,
      ttl: 5.minutes,  # Anthropic's ephemeral cache TTL
      cost_per_write: 0.375,  # $18.75/1M tokens
      cost_per_read: 0.03     # $1.50/1M tokens  
    },
    tool_definitions: {
      tokens: 5_000,
      ttl: 5.minutes,
      cost_per_write: 0.094,
      cost_per_read: 0.0075
    }
  }
  
  # Tier 2: Conditionally Cached (Dynamic, cached after threshold)
  TIER_2_CACHE = {
    template_files: {
      tokens: 10_000,
      threshold: 2,  # Cache after 2nd use
      ttl: 5.minutes
    },
    conversation_history: {
      tokens: :variable,
      threshold: 1024,  # Min tokens to cache
      ttl: 5.minutes
    }
  }
  
  def optimize_for_iteration(iteration_num, messages)
    if iteration_num == 1
      # First iteration: Write to cache
      mark_for_caching(TIER_1_CACHE.keys)
    else
      # Subsequent iterations: Read from cache
      apply_cache_control(messages)
    end
  end
end
```

### Implementation Details

1. **System Prompt Caching**
   - The 20K token agent-prompt.txt is cached on first use
   - Saves $0.72 per iteration after the first
   - Must include `cache_control: { type: "ephemeral" }` in message

2. **Tool Definition Caching**
   - The 5K token agent-tools.json is cached with system prompt
   - Combined with system prompt for single cache write

3. **Conversation History Caching**
   - Cached after 3+ iterations or 1024+ tokens
   - Reduces cost for long conversations

4. **Cache Invalidation Strategy**
   - Ephemeral cache expires after 5 minutes of inactivity
   - Perfect for agent loop iterations (typically < 2 minutes total)
   - No manual invalidation needed

## Tool Orchestration Strategy

### 1. Tool Mapping from Lovable to Rails

```ruby
# app/services/ai/tool_executor.rb
class ToolExecutor
  TOOL_MAPPING = {
    'os-write' => :create_file,
    'os-line-replace' => :update_file,
    'os-search-files' => :search_codebase,
    'os-view' => :read_file,
    'os-add-dependency' => :add_package,
    'os-delete' => :delete_file,
    'generate_image' => :generate_ai_image,
    'web_search' => :search_web,
    'os-fetch-website' => :fetch_url_content
  }
  
  def execute_tool_call(tool_call)
    tool_name = tool_call['name']
    tool_input = tool_call['input']
    
    # Broadcast tool start
    broadcaster.broadcast_tool_execution(tool_name, 'starting')
    
    # Execute the tool
    result = case TOOL_MAPPING[tool_name]
    when :create_file
      create_app_file(tool_input['file_path'], tool_input['content'])
    when :update_file
      update_app_file_with_line_replace(tool_input)
    when :search_codebase
      search_files_with_pattern(tool_input)
    # ... other tool implementations
    end
    
    # Broadcast tool completion
    broadcaster.broadcast_tool_execution(tool_name, 'complete')
    
    result
  end
  
  private
  
  def create_app_file(path, content)
    file = app.app_files.create!(
      path: path,
      content: content,
      language: detect_language(path)
    )
    
    # Track in current version
    current_version.app_version_files.create!(
      app_file: file,
      action: 'created'
    )
    
    { success: true, file_id: file.id, path: path }
  end
  
  def update_app_file_with_line_replace(params)
    file = app.app_files.find_by!(path: params['file_path'])
    
    # Apply line-based replacement
    updated_content = LineReplaceService.new(
      file.content,
      params['search'],
      params['replace'],
      params['first_replaced_line'],
      params['last_replaced_line']
    ).execute
    
    file.update!(content: updated_content)
    
    # Track change
    current_version.app_version_files.create!(
      app_file: file,
      action: 'updated'
    )
    
    { success: true, file_id: file.id, lines_changed: params['last_replaced_line'] - params['first_replaced_line'] + 1 }
  end
end
```

### 2. Parallel Tool Execution

```ruby
def execute_tools_in_parallel(tool_calls)
  # Group tools by dependency
  independent_tools, dependent_tools = partition_tools_by_dependency(tool_calls)
  
  # Execute independent tools in parallel
  results = Parallel.map(independent_tools, in_threads: 5) do |tool|
    execute_tool_call(tool)
  end
  
  # Then execute dependent tools sequentially
  dependent_tools.each do |tool|
    results << execute_tool_call(tool)
  end
  
  results
end
```

## Implementation Timeline

### Phase 1: Core Integration (Week 1)
- [ ] Integrate AgentPromptService with AppBuilderV5
- [ ] Configure Claude Opus 4.1 with streaming
- [ ] Implement tool executor with Lovable tool mapping
- [ ] Set up ChatProgressBroadcasterV2 enhancements

### Phase 2: Broadcasting & UI (Week 2)
- [ ] Create all chat message partials (thinking, tools, iterations)
- [ ] Implement Stimulus controller for real-time updates
- [ ] Add Turbo Stream broadcasting for mixed content
- [ ] Create app version card partial for completion

### Phase 3: Tool Implementation (Week 3)
- [ ] Implement all Lovable tools (os-* prefix)
- [ ] Add parallel tool execution
- [ ] Implement file operations with version tracking
- [ ] Add image generation and web search capabilities

### Phase 4: Testing & Optimization (Week 4)
- [ ] Test complete agent loop flow
- [ ] Optimize broadcasting performance
- [ ] Add error recovery mechanisms
- [ ] Implement usage tracking and analytics

## Key Differentiators

### 1. Rails-Native Broadcasting
Unlike Lovable's JavaScript-heavy approach, we use Rails' native broadcasting:
- Turbo Streams for instant updates
- Server-rendered partials for consistency
- ActionCable for WebSocket management
- Minimal client-side JavaScript

### 2. Version Control Integration
Every iteration creates tracked changes:
- AppVersion records for each generation
- AppVersionFile tracking for all changes
- Git-like diff viewing capabilities
- Rollback and comparison features

### 3. Team & Billing Integration
Bullet Train's team architecture provides:
- Per-team usage tracking
- Quota management
- Billing integration
- Role-based access control

## Success Metrics

1. **Generation Speed**: < 2 minutes for typical apps
2. **Iteration Efficiency**: Average 3-5 iterations to completion
3. **User Satisfaction**: Real-time feedback keeps users engaged
4. **Code Quality**: Clean, maintainable TypeScript/React output
5. **Success Rate**: > 90% successful generations on first attempt

## Next Steps

1. Review and approve this strategy
2. Begin Phase 1 implementation
3. Set up testing environment with Claude Opus 4.1
4. Create sample apps for testing each tool
5. Prepare demo for stakeholders

## Conclusion

V5 combines the best of Lovable's agent loop architecture with Rails' powerful broadcasting capabilities and Claude Opus 4.1's superior reasoning. This creates a uniquely powerful and user-friendly app generation experience that provides real-time feedback while maintaining code quality and system reliability.