# Fix Plan: Message Splitting and Deployment Timeouts

## Problem Analysis

### App 1571 (Calccraft) Flow Map
```
18:42:34.378 - User: "build a calculator"
18:42:34.382 - Assistant Message #3240 (SUCCESS)
  ├─ 18:42:53Z: tools (2) + message (same timestamp!)
  └─ 18:43:33Z: tools (7) + message (same timestamp!)
  
18:44:37.898 - Assistant Message #3241 (FAILED) - NEW MESSAGE!
  ├─ 18:44:38Z: tools (2) + message (same timestamp!)
  └─ 18:45:03Z: tools (streaming) + message
  
19:05:04.000 - Assistant Message #3242 (FAILED)
  └─ "This request took too long to process..."
```

## Root Causes

### 1. Message Splitting Issue
**Problem**: IncrementalToolCompletionJob creates NEW assistant messages instead of updating existing ones.

**Current Flow**:
```ruby
# app/jobs/incremental_tool_completion_job.rb
AppChatMessage.create!(
  app: app,
  role: 'assistant',
  content: assistant_reply['content'],
  conversation_flow: updated_flow,
  # Creates NEW message each time!
)
```

**Impact**: Conversation fragmented across multiple messages, losing context.

### 2. Same Timestamp Ordering
**Problem**: Tool calls and content messages have identical timestamps.

**Current Code**:
```ruby
# app/services/ai/app_builder_v5.rb
timestamp = Time.current.iso8601  # Same for both!
@conversation_flow << { 'type' => 'tools', 'timestamp' => timestamp }
@conversation_flow << { 'type' => 'message', 'timestamp' => timestamp }
```

**Impact**: Ambiguous chronological ordering in UI.

### 3. Deployment Timeout Without Retry
**Problem**: No retry mechanism when deployment times out.

**Current State**:
- Tools stuck in 'streaming' status
- No timeout handler
- No retry logic

## Fix Implementation

### Fix 1: Prevent Message Splitting
```ruby
# app/jobs/incremental_tool_completion_job.rb
def perform(app_id, execution_id)
  # CHANGE: Update existing message instead of creating new
  message = app.app_chat_messages
    .where(role: 'assistant')
    .where("conversation_flow @> ?", 
      [{type: 'tools', execution_id: execution_id}].to_json)
    .first
  
  if message
    # Update existing message
    message.update!(
      conversation_flow: updated_flow,
      content: build_combined_content(updated_flow),
      status: all_complete? ? 'completed' : 'processing'
    )
  else
    # Only create if no existing message
    AppChatMessage.create!(...)
  end
end
```

### Fix 2: Add Timestamp Delays
```ruby
# app/services/ai/app_builder_v5.rb
def add_to_conversation_flow(type, content, delay_ms = 100)
  # Add small delay to ensure unique timestamps
  sleep(delay_ms / 1000.0) if @last_flow_timestamp == Time.current.to_f
  
  timestamp = Time.current.iso8601(3)  # Include milliseconds
  @conversation_flow << {
    'type' => type,
    'timestamp' => timestamp,
    'content' => content
  }
  @last_flow_timestamp = Time.current.to_f
end

# Usage
add_to_conversation_flow('tools', tool_data, 0)      # No delay for first
add_to_conversation_flow('message', content, 100)    # 100ms delay for ordering
```

### Fix 3: Deployment Timeout Handling
```ruby
# app/jobs/deploy_app_job.rb
class DeployAppJob
  include Sidekiq::Job
  sidekiq_options retry: 3, dead: false
  
  DEPLOYMENT_TIMEOUT = 5.minutes
  
  def perform(app_version_id)
    app_version = AppVersion.find(app_version_id)
    
    Timeout::timeout(DEPLOYMENT_TIMEOUT) do
      deploy_to_cloudflare(app_version)
    end
  rescue Timeout::Error => e
    handle_timeout(app_version)
    raise # Let Sidekiq retry
  end
  
  private
  
  def handle_timeout(app_version)
    # Mark deployment as failed
    message = app_version.app.app_chat_messages
      .where(role: 'assistant')
      .order(created_at: :desc)
      .first
    
    if message
      message.update!(
        status: 'failed',
        metadata: {
          error: 'Deployment timeout',
          deployment_status: 'timeout'
        }
      )
      
      # Broadcast failure to UI
      broadcast_deployment_status(
        message,
        status: 'failed',
        error: 'Deployment timed out after 5 minutes'
      )
    end
  end
end
```

### Fix 4: Unified Message Assembly
```ruby
# app/services/ai/incremental_tool_coordinator.rb
def complete_conversation_cycle(execution_id)
  # Ensure all updates go to same message
  with_message_lock(execution_id) do |message|
    # Collect all flow items
    flow = collect_all_flow_items(execution_id)
    
    # Update single message
    message.update!(
      conversation_flow: flow,
      content: build_narrative_content(flow),
      status: determine_status(flow)
    )
    
    # Trigger deployment only if all successful
    if all_tools_successful?(flow)
      trigger_deployment(message)
    end
  end
end

private

def with_message_lock(execution_id)
  key = "message_lock:#{execution_id}"
  Rails.cache.redis.then do |redis|
    redis.set(key, "1", nx: true, ex: 30)
    yield find_or_create_message(execution_id)
  ensure
    redis.del(key)
  end
end
```

## Testing Strategy

### 1. Unit Tests
```ruby
# spec/jobs/incremental_tool_completion_job_spec.rb
it "updates existing message instead of creating new" do
  existing = create(:app_chat_message, conversation_flow: [...])
  
  expect {
    IncrementalToolCompletionJob.perform_now(app.id, execution_id)
  }.not_to change { AppChatMessage.count }
  
  expect(existing.reload.conversation_flow).to include(...)
end
```

### 2. Integration Tests  
```ruby
# spec/services/ai/app_builder_v5_spec.rb
it "adds delays between flow items" do
  builder = AI::AppBuilderV5.new(app)
  
  builder.add_to_conversation_flow('tools', {})
  timestamp1 = builder.conversation_flow.last['timestamp']
  
  builder.add_to_conversation_flow('message', {})
  timestamp2 = builder.conversation_flow.last['timestamp']
  
  expect(Time.parse(timestamp2)).to be > Time.parse(timestamp1)
end
```

### 3. Golden Flow Test
```ruby
bin/rails runner "
  # Test calculator app generation
  app = App.create!(name: 'Test', team_id: 1)
  message = app.app_chat_messages.create!(
    role: 'user',
    content: 'build a calculator'
  )
  
  AI::AppBuilderV5.new(app).process_message(message)
  
  # Verify single message
  assistant_messages = app.app_chat_messages.where(role: 'assistant')
  expect(assistant_messages.count).to eq(1)
  
  # Verify deployment
  expect(app.app_versions.last.deployment_status).to eq('deployed')
"
```

## Rollout Plan

1. **Phase 1**: Add timestamp delays (low risk)
2. **Phase 2**: Fix message splitting (medium risk) 
3. **Phase 3**: Add deployment timeout handling (medium risk)
4. **Phase 4**: Full integration testing

## Monitoring

```bash
# Watch for message splitting
tail -f log/development.log | grep "AppChatMessage.create"

# Monitor deployment timeouts  
tail -f log/sidekiq.log | grep -E "DeployAppJob|timeout"

# Check conversation flow ordering
bin/rails runner "
  AppChatMessage.last.conversation_flow.each do |f|
    puts \"\#{f['timestamp']} - \#{f['type']}\"
  end
"
```

## Success Metrics

- [ ] Single assistant message per conversation cycle
- [ ] No duplicate timestamps in conversation_flow
- [ ] Deployment timeouts handled gracefully
- [ ] Golden flow tests passing
- [ ] No "streaming" stuck status in production