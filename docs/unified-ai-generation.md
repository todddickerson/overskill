# Unified AI Generation Architecture

## Overview
Unified AI generation flow that consolidates all app generation logic into the App model, eliminating duplicate code across controllers.

## Key Changes

### 1. App Model (`app/models/app.rb`)
- Added `initiate_generation!` method as single entry point for all AI generation
- Added `after_create :initiate_ai_generation` callback for automatic generation on new apps
- Intelligently determines which AI orchestrator to use based on configuration

### 2. Orchestrator Selection Priority
The system checks in this order:
1. **App-specific setting** - Individual app can override
2. **Team-level feature flag** - Team can have different settings  
3. **Global environment variable** - System-wide default

Available orchestrators:
- **V3 (GPT-5 optimized)** - `USE_V3_ORCHESTRATOR=true` - Recommended for production
- **Unified AI** - `USE_UNIFIED_AI=true` - Legacy coordinator
- **Legacy** - Original generation system

### 3. Controllers Simplified

#### `public/generator_controller.rb`
- Removed manual message creation and job queuing
- App model's `after_create` callback handles everything automatically

#### `account/apps_controller.rb`  
- Removed duplicate generation logic from `create` action
- `debug_error` now uses unified `initiate_generation!` method

#### `account/app_editors_controller.rb`
- `queue_ai_processing` now delegates to App model's unified method

### 4. New Job: ProcessAppUpdateJobV3
Created `app/jobs/process_app_update_job_v3.rb` to handle V3 orchestrator execution.

## Benefits

1. **DRY Code** - Single source of truth for generation logic
2. **Flexible Configuration** - Easy to switch between orchestrators
3. **Consistent Behavior** - All generation paths work the same way
4. **Easier Testing** - Can test generation logic in isolation
5. **Future-proof** - Easy to add new orchestrators

## Usage

### Creating an app (automatic generation)
```ruby
app = team.apps.create!(
  creator: membership,
  name: "My App",
  prompt: "Create a todo app",
  # ... other attributes
)
# Automatically triggers generation via after_create callback
```

### Manual generation trigger
```ruby
app.initiate_generation!("New prompt or update")
```

### Configure which orchestrator to use
```bash
# Environment variables (global default)
USE_V3_ORCHESTRATOR=true  # Use GPT-5 optimized orchestrator
USE_UNIFIED_AI=false      # Don't use legacy coordinator
USE_AI_ORCHESTRATOR=false # Don't use old orchestrator

# Or configure per-app or per-team via settings/feature flags
```

## Testing
Run `ruby test_unified_generation.rb` to verify the unified flow works correctly.

## Migration Notes
- Existing code paths remain compatible
- No database migrations required
- Can gradually migrate to V3 orchestrator by setting environment variable