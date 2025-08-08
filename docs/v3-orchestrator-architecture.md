# V3 Orchestrator Architecture

## Overview
The V3 Orchestrator (`AppUpdateOrchestratorV3`) is the unified AI handler for both app creation and updates. It uses GPT-5 with tool calling for reliable, streaming app generation with real-time progress updates.

## Key Features

### 1. Unified CREATE/UPDATE Handler
- **Single orchestrator** handles both new app creation and existing app updates
- Automatically detects operation type based on app state
- Consistent UX for all AI operations

### 2. Real-time Progress Streaming
- **App Versions**: Creates version at start, updates throughout
- **Chat Messages**: Streams progress via assistant messages  
- **Turbo Broadcasts**: Live UI updates for versions, files, and status
- **Progress Stages**: Structured phases with percentage tracking

### 3. GPT-5 Tool Calling
Enhanced tools for reliable execution:
```ruby
- create_file         # Create new files with validation
- update_file         # Modify existing files
- broadcast_progress  # Send status updates to user
- create_version_snapshot  # Save milestones
- finish_app         # Complete with summary
```

### 4. Standards Compliance
- Automatically loads and enforces `AI_APP_STANDARDS.md`
- Validates JavaScript/JSX to prevent TypeScript syntax
- Ensures React CDN setup (no bundlers)
- Enforces Tailwind CSS and professional UI patterns

### 5. Smart Post-Generation
For new apps, automatically:
- Creates authentication settings if user data detected
- Sets up Supabase database tables
- Queues logo generation
- Triggers deployment if enabled

## Architecture Flow

### New App Creation
```
User Prompt → App Model (after_create) → ProcessAppUpdateJobV3
    ↓
AppUpdateOrchestratorV3.new(message)
    ↓
1. Create app_version (v1.0.0)
2. Define stages: analyzing → planning → coding → reviewing → deploying
3. Analyze requirements with AI_APP_STANDARDS
4. Create execution plan
5. Execute with GPT-5 tools (stream progress)
6. Review and optimize code
7. Setup auth/database if needed
8. Finalize with summary
    ↓
App Ready with Files + Version History
```

### App Update
```
User Feedback → Create Message → App.initiate_generation!
    ↓
ProcessAppUpdateJobV3 → AppUpdateOrchestratorV3
    ↓
1. Create app_version (increment)
2. Define stages: analyzing → planning → coding → reviewing
3. Analyze current structure + changes needed
4. Plan modifications
5. Execute updates with tools
6. Review changes
7. Finalize with summary
    ↓
Updated App with Version History
```

## Key Components

### AppUpdateOrchestratorV3
Main orchestrator class with:
- Intelligent CREATE vs UPDATE detection
- Version management throughout execution
- Progress broadcasting via `ProgressBroadcaster`
- Tool calling with GPT-5
- Standards enforcement
- Error recovery and validation

### ProcessAppUpdateJobV3
Background job that:
- Handles retry logic (3 attempts)
- Initializes orchestrator
- Manages job lifecycle
- Reports failures gracefully

### App Model Integration
```ruby
def initiate_generation!(prompt = nil)
  # Create user message
  message = create_or_find_message(prompt)
  
  # Use V3 if enabled
  if use_v3_orchestrator?
    ProcessAppUpdateJobV3.perform_later(message)
  else
    # Legacy fallback
    AppGenerationJob.perform_later(generation)
  end
end

def use_v3_orchestrator?
  # Check app setting → team flag → ENV variable
  ENV['USE_V3_ORCHESTRATOR'] == 'true'
end
```

## Progress Broadcasting

### 1. Chat Messages
```ruby
# Assistant messages show real-time progress
@broadcaster.update("Building component...", 0.5)
# Updates assistant message content with progress bar
```

### 2. Version Cards
```ruby
# Version updates throughout execution
@app_version.update!(
  status: 'in_progress',
  metadata: { progress: 50, current_stage: 'coding' }
)
broadcast_version_update
```

### 3. File Updates
```ruby
# Broadcast each file creation/update
broadcast_file_update("src/App.jsx", "created")
# Shows in file activity feed
```

### 4. App Status
```ruby
# Update app status badge
broadcast_app_update
# Updates status badge and preview
```

## Tool Implementation

### create_file
- Validates JavaScript/JSX syntax
- Removes TypeScript annotations
- Creates app_file record
- Creates version_file record
- Broadcasts update

### update_file
- Find/replace in existing files
- Validates changes
- Updates version tracking
- Broadcasts progress

### broadcast_progress
- Updates assistant message
- Shows progress bar
- Updates version metadata
- Live UI refresh

### create_version_snapshot
- Saves current state
- Updates changelog
- Marks milestone
- Useful for complex apps

### finish_app
- Generates summary
- Completes version
- Updates app status
- Triggers preview update

## Configuration

### Enable V3 Orchestrator
```bash
# Environment variable (global)
USE_V3_ORCHESTRATOR=true

# Or per-app setting
app.app_settings.create!(key: 'use_v3_orchestrator', value: 'true')

# Or team feature flag (if implemented)
team.enable_feature!('v3_orchestrator')
```

### Testing
```bash
# Run test script
ruby test_v3_orchestrator.rb

# Monitor logs
tail -f log/development.log | grep AppUpdateOrchestratorV3

# Watch Sidekiq
bundle exec sidekiq
```

## Benefits Over Legacy System

1. **Unified Interface**: Single orchestrator for all operations
2. **Real-time Feedback**: Streaming progress vs batch updates
3. **Better Reliability**: GPT-5 with structured tool calling
4. **Version Tracking**: Complete history with snapshots
5. **Standards Enforcement**: Automatic compliance with AI_APP_STANDARDS
6. **Error Recovery**: Validation and auto-fixing of common issues
7. **Professional UX**: Similar to Lovable.dev experience

## Monitoring

### Key Metrics
- Generation success rate
- Average generation time
- Files per app
- Version creation rate
- Tool call patterns

### Logs to Watch
```
[AppUpdateOrchestratorV3] Starting GPT-5 enhanced execution
[AppUpdateOrchestratorV3] Operation type: CREATE/UPDATE
[AppUpdateOrchestratorV3] GPT-5 iteration N
[AppUpdateOrchestratorV3] Created/updated file: path
[AppUpdateOrchestratorV3] Implementation complete
```

## Troubleshooting

### Common Issues

1. **TypeScript in JavaScript files**
   - Orchestrator auto-detects and fixes
   - Removes type annotations
   - Converts to plain JS/JSX

2. **Slow Generation**
   - Check GPT-5 API status
   - Monitor iteration count (max 25)
   - Review plan complexity

3. **Missing Standards**
   - Ensure AI_APP_STANDARDS.md exists
   - Falls back to basic standards
   - Check file path in logs

4. **Broadcast Issues**
   - Verify Turbo Streams setup
   - Check ActionCable connection
   - Review target DOM IDs

## Future Enhancements

1. **Incremental Generation**: Build apps in smaller chunks
2. **Parallel Tool Execution**: Run multiple tools simultaneously  
3. **Smart Caching**: Cache analysis and plans for similar requests
4. **Multi-Model Support**: Use different models for different tasks
5. **Visual Progress**: Rich UI for generation progress
6. **Rollback Support**: Revert to previous versions easily