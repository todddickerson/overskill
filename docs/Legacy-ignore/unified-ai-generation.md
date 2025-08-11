# Unified AI Generation Architecture

## Overview
Unified AI generation flow that consolidates all app generation logic into the App model, eliminating duplicate code across controllers.

## Key Changes

### 1. App Model (`app/models/app.rb`)
- Added `initiate_generation!` method as single entry point for all AI generation
- Added `after_create :initiate_ai_generation` callback for automatic generation on new apps
- Intelligently determines which AI orchestrator to use based on configuration

### 2. V3 Optimized (Always Used)

The system now always uses the **V3 Optimized orchestrator** - the best and tested version.

**Current orchestrator:**
- **V3 Optimized (GPT-5)** - Always enabled, fastest and most reliable

**Deprecated orchestrators:** All old orchestrators have been moved to `bak/lib/deprecated_generators/`

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

### V3 Optimized (No Configuration Needed)

V3 Optimized is always used - no environment variables or configuration needed!

```ruby
# All generation automatically uses V3 Optimized
app.initiate_generation!("Any prompt")  # Uses V3 Optimized
```

## Testing
Run `ruby test_unified_generation.rb` to verify the unified flow works correctly.

## Migration Notes
- V3 Optimized is now the only orchestrator
- All legacy orchestrators deprecated and moved to `bak/lib/deprecated_generators/`
- No configuration needed - works out of the box