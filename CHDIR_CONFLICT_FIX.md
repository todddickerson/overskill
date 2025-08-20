# Fix for "conflicting chdir during another chdir block" Error

## Problem
When multiple deployment jobs ran simultaneously, they would conflict because both were trying to use `Dir.chdir` to change to their build directories. Ruby's `Dir.chdir` is not thread-safe and cannot be nested when called from different threads/processes.

## Root Cause
The `ExternalViteBuilder` service was using `Dir.chdir(temp_dir)` blocks to change into the build directory for running npm commands. When multiple deployments happened concurrently, these would conflict.

## Solution Implemented

### 1. Unique Temp Directories
Enhanced temp directory naming to include process ID and random hex to ensure uniqueness:
```ruby
unique_id = "#{Process.pid}_#{SecureRandom.hex(4)}"
temp_path = Rails.root.join('tmp', 'builds', "app_#{@app.id}_#{Time.current.to_i}_#{unique_id}")
```

### 2. Removed Dir.chdir Blocks
Replaced all `Dir.chdir` blocks with `cd` commands in shell:
```ruby
# Before (causes conflicts):
Dir.chdir(temp_dir) do
  install_output = `#{npm_path} install 2>&1`
end

# After (no conflicts):
install_output = `cd "#{temp_dir}" && #{npm_path} install 2>&1`
```

### 3. Changes Made
- `build_with_mode`: Removed Dir.chdir, uses `cd` in shell commands
- `build_with_incremental_mode`: Removed Dir.chdir, uses `cd` in shell commands
- Added unique identifiers to temp directory names

## Files Modified
- `/app/services/deployment/external_vite_builder.rb`

## Benefits
- ✅ No more chdir conflicts with concurrent deployments
- ✅ Each deployment gets its own isolated build directory
- ✅ Commands still run in the correct directory context
- ✅ Thread-safe for multiple simultaneous builds

## Testing
Confirmed deployment works successfully after fixes:
- App #1140 deployed without chdir conflicts
- Multiple concurrent deployments now possible