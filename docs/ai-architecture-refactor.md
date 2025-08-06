# AI Architecture Refactor Documentation

## Overview

This document describes the refactored AI architecture for OverSkill, implementing a cleaner, more maintainable system with Claude Code-style TODO tracking.

## New Architecture Components

### 1. Core Services

#### `Ai::UnifiedAiCoordinator`
**Purpose**: Single entry point for all AI operations
**Location**: `app/services/ai/unified_ai_coordinator.rb`

- Coordinates between smaller, focused services
- Manages TODO tracking and progress broadcasting
- Handles all message types (generation, update, question, command)
- Provides consistent error handling

#### `Ai::TodoTracker`
**Purpose**: Claude Code-style task management
**Location**: `app/services/ai/todo_tracker.rb`

- Allows AI to track its own tasks
- Provides visual progress in chat messages
- Records timing and success/failure states
- Automatically updates chat messages with task lists

#### `Ai::Services::MessageRouter`
**Purpose**: Determine how to handle incoming messages
**Location**: `app/services/ai/services/message_router.rb`

- Analyzes message content and context
- Routes to appropriate handler (generate, update, question, command)
- Extracts metadata (urgency, file references, deployment intent)

#### `Ai::Services::ProgressBroadcaster`
**Purpose**: Unified progress tracking and broadcasting
**Location**: `app/services/ai/services/progress_broadcaster.rb`

- Manages stage-based progress (thinking, planning, coding, etc.)
- Provides consistent progress bars and status updates
- Handles Turbo Stream broadcasts
- Records timing for each stage

### 2. Job Structure

#### `UnifiedAiProcessingJob`
**Purpose**: Single job for all AI message processing
**Location**: `app/jobs/unified_ai_processing_job.rb`

- Replaces multiple legacy jobs
- Simple delegation to UnifiedAiCoordinator
- Consistent retry logic and error handling

### 3. Controller Changes

#### `Account::AppEditorsController#create_message`
**Improvements**:
- Cleaner method structure with single responsibility
- Better separation of concerns
- Clear comments explaining each step
- Extracted helper methods for readability

## Flow Example

### User Creates a New App:

1. **Controller** receives message
   ```ruby
   @message = build_user_message
   queue_ai_processing(@message)
   ```

2. **UnifiedAiProcessingJob** starts
   ```ruby
   coordinator = Ai::UnifiedAiCoordinator.new(app, message)
   coordinator.execute!
   ```

3. **MessageRouter** determines action
   ```ruby
   routing = router.route  # => { action: :generate }
   ```

4. **TodoTracker** creates task list
   ```
   📋 Task Progress
   ⏳ Analyze requirements
   ⏳ Create index.html
   ⏳ Create app.js
   ⏳ Create styles.css
   ```

5. **ProgressBroadcaster** shows stages
   ```
   🤔 Understanding your requirements
   ████░░░░░░░░░░░░░░░░ 20%
   ```

6. **UnifiedAiCoordinator** executes tasks
   - Marks each TODO as in_progress, then completed
   - Updates progress bar for each stage
   - Creates files and version
   - Queues deployment

7. **Final state**
   ```
   ✅ Operation Complete!
   
   📋 Task Progress
   ✅ Analyze requirements (2.1s)
   ✅ Create index.html (1.5s)
   ✅ Create app.js (1.8s)
   ✅ Create styles.css (1.2s)
   
   Progress: 100%
   Time taken: 6.6 seconds
   ```

## Migration Strategy

### Phase 1: Parallel Running (Current)
- New system available via `USE_UNIFIED_AI=true`
- Legacy system remains default
- Monitor performance and reliability

### Phase 2: Gradual Migration
- Switch specific app types to new system
- A/B test with subset of users
- Gather feedback and fix issues

### Phase 3: Full Migration
- Make unified system default
- Keep legacy as fallback via feature flag
- Monitor for edge cases

### Phase 4: Cleanup
- Remove legacy code:
  - `ProcessAppUpdateJob`
  - `ProcessAppUpdateJobV2`
  - `AppUpdateOrchestratorV2`
  - `AppUpdateOrchestratorStreaming`
  - `LovableStyleGenerator`
  - `EnhancedAppGenerator`

## Benefits

### 1. **Maintainability**
- Single code path for all AI operations
- Clear separation of concerns
- Consistent patterns throughout

### 2. **Debuggability**
- TODO tracking shows exactly what AI is doing
- Stage-based progress makes it easy to identify failures
- Comprehensive logging at each step

### 3. **User Experience**
- Claude Code-style task lists show progress
- Consistent progress indicators
- Better error messages

### 4. **Performance**
- Fewer redundant AI calls
- Optimized prompt construction
- Efficient file operations

### 5. **Extensibility**
- Easy to add new message types
- Simple to modify stages or tasks
- Clear plugin points for new features

## Configuration

### Environment Variables

```bash
# Enable new unified AI system (default: true)
USE_UNIFIED_AI=true

# Legacy flags (to be deprecated)
USE_AI_ORCHESTRATOR=false
USE_LOVABLE_GENERATOR=false
```

## Testing

### Manual Testing
```ruby
# Rails console
app = App.find(123)
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a dashboard with charts",
  user: User.first
)

coordinator = Ai::UnifiedAiCoordinator.new(app, message)
coordinator.execute!
```

### Monitoring
- Watch for `[UnifiedAI]` tags in logs
- Monitor job queue for failures
- Check TODO completion rates
- Track stage timing for performance

## Next Steps

1. **Immediate**
   - Add feature flag for gradual rollout
   - Create monitoring dashboard
   - Write integration tests

2. **Short-term**
   - Migrate simple operations first
   - Gather user feedback
   - Optimize prompt templates

3. **Long-term**
   - Remove all legacy code
   - Add advanced features (multi-step planning, rollback, etc.)
   - Implement learning from successful patterns

## Conclusion

This refactor significantly improves the AI system's maintainability, reliability, and user experience. The Claude Code-style TODO tracking provides transparency into AI operations, while the unified architecture eliminates code duplication and inconsistencies.