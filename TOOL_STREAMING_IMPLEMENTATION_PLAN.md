# Tool Streaming Implementation Plan - CONSOLIDATED
## Single Source of Truth for Phase 2 Development

**Status**: Phase 1 (WFP Previews) ✅ COMPLETE | Phase 2 (Tool Streaming) 🔄 50% COMPLETE

---

## 🎯 OBJECTIVE

Transform existing basic tool execution into **Netflix-grade real-time streaming** with granular progress indicators, user controls, and performance analytics.

## 🔍 CURRENT STATE ANALYSIS

### ✅ What's Already Implemented (from production logs):

1. **ActionCable Infrastructure**
   - `Broadcasting to app_1480_chat` - Real-time updates working
   - Turbo Streams integration functional
   - `agent_reply_v5.html.erb` rendering correctly

2. **Tool Status Tracking**
   - `tool_calls` metadata with status tracking
   - Database updates: `tool_calls=[{"name":"os-view","status":"complete"}]`
   - Real-time status broadcasting working

3. **Conversation Flow System**
   - `conversation_flow` array tracking tool execution history
   - Incremental UI updates via `update_tool_status_in_flow`
   - Message broadcasting via ActionCable

4. **WFP Preview Integration**
   - `WfpPreviewService` + `WfpPreviewBuildService` operational
   - 2.76-second preview provisioning achieved
   - Real-time file sync to preview environments

### ❌ What's Missing for Netflix-Grade UX:

1. **Granular Progress Indicators**
   - Current: Binary status (running → complete)
   - Needed: Stage-based progress (analyzing → writing → validating → complete)

2. **Parallel Tool Execution**
   - Current: Sequential tool execution
   - Needed: Background jobs with WebSocket coordination

3. **User Controls**
   - Current: No user interaction during execution
   - Needed: Pause/resume/cancel functionality

4. **Performance Analytics**
   - Current: Basic execution tracking
   - Needed: Real-time metrics, timing analysis, success rates

---

## 🚀 IMPLEMENTATION PLAN

### Phase 2A: Enhanced Progress Indicators (1-2 days)

#### 2A.1: Enhanced Tool Execution Service
```ruby
# app/services/ai/streaming_tool_executor_v2.rb
class StreamingToolExecutorV2
  def execute_with_streaming(tool_call, message_id)
    case tool_call['function']['name']
    when 'os-write'
      execute_write_with_streaming(tool_call, message_id)
    when 'os-line-replace'
      execute_replace_with_streaming(tool_call, message_id)
    when 'generate-new-app-logo'
      execute_image_with_streaming(tool_call, message_id)
    end
  end

  private

  def execute_write_with_streaming(tool_call, message_id)
    broadcast_progress(message_id, { stage: 'analyzing', progress: 10 })
    # File analysis logic
    
    broadcast_progress(message_id, { stage: 'writing', progress: 60 })
    # File writing with chunked progress updates
    
    broadcast_progress(message_id, { stage: 'complete', progress: 100 })
  end
end
```

#### 2A.2: Enhanced UI Components
```erb
<!-- Update app/views/account/app_editors/_agent_reply_v5.html.erb -->
<div class="tool-progress-container">
  <% message.tool_calls.each_with_index do |tool, index| %>
    <div class="tool-item" data-tool-index="<%= index %>">
      <div class="tool-progress-bar">
        <div class="progress-fill" style="width: <%= tool['progress'] || 0 %>%"></div>
      </div>
      <div class="tool-stage"><%= tool['stage'] || tool['status'] %></div>
    </div>
  <% end %>
</div>
```

### Phase 2B: User Controls (1-2 days)

#### 2B.1: Tool Execution Controller
```javascript
// app/javascript/controllers/tool_execution_controller.js
export default class extends Controller {
  pauseExecution() {
    this.subscription.send({ action: 'pause_execution' })
  }
  
  resumeExecution() {
    this.subscription.send({ action: 'resume_execution' })
  }
  
  cancelExecution() {
    this.subscription.send({ action: 'cancel_execution' })
  }
}
```

#### 2B.2: Tool Execution Channel Enhancement
```ruby
# app/channels/tool_execution_channel.rb  
class ToolExecutionChannel < ApplicationCable::Channel
  def pause_execution(data)
    Rails.cache.write("execution_paused_#{params[:message_id]}", true)
    broadcast_status_change('paused')
  end
  
  def resume_execution(data)
    Rails.cache.delete("execution_paused_#{params[:message_id]}")
    broadcast_status_change('resumed')
  end
end
```

### Phase 2C: Performance Dashboard (2-3 days)

#### 2C.1: Metrics Collection
```ruby
# app/services/ai/tool_execution_analytics.rb
class ToolExecutionAnalytics
  def track_execution(tool_name, execution_time, success)
    metrics = {
      tool_name: tool_name,
      execution_time: execution_time,
      success: success,
      timestamp: Time.current
    }
    
    # Store in Redis for real-time dashboard
    Redis.current.zadd("tool_metrics", Time.current.to_i, metrics.to_json)
  end
end
```

#### 2C.2: Real-time Dashboard
```erb
<!-- New dashboard partial -->
<div class="execution-dashboard" data-controller="tool-dashboard">
  <div class="metrics-grid">
    <div class="metric">
      <span class="value"><%= @execution_stats[:avg_time] %></span>
      <span class="label">Avg Execution Time</span>
    </div>
    <div class="metric">
      <span class="value"><%= @execution_stats[:success_rate] %>%</span>
      <span class="label">Success Rate</span>
    </div>
  </div>
</div>
```

---

## 🔧 INTEGRATION STRATEGY

### With Existing V5 System
1. **Extend AppBuilderV5**: Add streaming executor calls
2. **Enhance ActionCable**: Upgrade existing broadcasting
3. **Update UI Partials**: Enhance `agent_reply_v5.html.erb`
4. **Database Schema**: Add progress tracking fields

### With WFP Previews
1. **Coordinate Updates**: Tool progress triggers preview refresh
2. **Build Status Integration**: Show build progress in tool streaming
3. **Error Handling**: Tool failures trigger preview error states

---

## 📊 SUCCESS METRICS

### Performance Targets
- **Tool Progress Updates**: < 100ms latency
- **User Control Response**: < 200ms pause/resume
- **Dashboard Refresh**: Real-time (< 500ms)
- **Overall UX**: Netflix-grade smoothness

### User Experience Goals
- **Transparency**: Users see exactly what's happening
- **Control**: Users can pause/resume/cancel anytime  
- **Confidence**: Clear progress indicators build trust
- **Engagement**: Real-time updates keep users engaged

---

## 🎬 IMPLEMENTATION SEQUENCE

### Day 1: Enhanced Progress Indicators
1. Create `StreamingToolExecutorV2`
2. Update `AppBuilderV5` integration
3. Enhance UI components for progress display
4. Test with existing tool execution

### Day 2: User Controls
1. Add ActionCable channel enhancements
2. Implement JavaScript controllers
3. Add pause/resume/cancel UI elements
4. Test user interaction workflows

### Day 3: Performance Dashboard  
1. Implement metrics collection
2. Create dashboard components
3. Add real-time analytics display
4. Integration testing and optimization

### Day 4: Polish & Testing
1. Animation improvements
2. Error handling edge cases
3. Performance optimization
4. End-to-end testing

---

## 🔄 MIGRATION FROM EXISTING SYSTEM

### Low-Risk Incremental Approach
1. **Feature Flag**: `ENHANCED_TOOL_STREAMING=true/false`
2. **Fallback System**: Existing tool execution as backup
3. **A/B Testing**: Gradual rollout to users
4. **Monitoring**: Real-time error tracking during transition

---

**🎯 Ready for Implementation**: All prerequisites met, existing infrastructure ready, clear implementation path defined.