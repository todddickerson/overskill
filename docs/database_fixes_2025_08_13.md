# Database Schema Fixes - August 13, 2025

## Issues Found and Fixed

### 1. DatabaseShard Connection Issue
**Problem**: `DatabaseShard` model throws "No database connection defined for '' shard" error when accessed directly.

**Root Cause**: Rails 8 sharding features conflict with the model name.

**Solution**: 
- Use direct SQL queries when accessing DatabaseShard data in critical paths
- Added fallback SQL in seeds file
- Created workaround in test scripts

### 2. Missing DatabaseShard Record
**Problem**: `SupabaseAuthSyncJob` failing because no DatabaseShard records existed.

**Solution**: 
- Created default `shard-001` record via SQL
- Added `SUPABASE_PROJECT_ID` to `.env.local`
- Updated seeds to create shard automatically

### 3. UserShardMapping Migration Issue
**Problem**: Migration file had invalid timestamp format `20250114_create_user_shard_mappings.rb`

**Solution**:
- Renamed to proper timestamp: `20250807000000_create_user_shard_mappings.rb`
- Marked migration as completed in schema_migrations table

### 4. SupabaseAuthSyncJob Parameter Issue
**Problem**: Job receiving user_id (Integer) but treating it as User object.

**Solution**:
- Fixed `perform` method to handle both User objects and IDs
- Changed parameter from `user` to `user_or_id`
- Added type checking and User.find() when needed

### 5. Missing Columns in Models
**Issues Checked**:
- ✅ `app_version_files` has `content` column
- ✅ `user_shard_mappings` table exists with proper columns
- ✅ `apps` table has `database_shard_id` column
- ⚠️ `database_shards` using plain text keys (not encrypted columns)

## Files Modified

1. **app/jobs/supabase_auth_sync_job.rb**
   - Fixed to handle user_id parameter properly

2. **db/seeds/development.rb**
   - Added SQL fallback for DatabaseShard creation
   - Changed shard_number from 0 to 1
   - Better error handling

3. **db/migrate/20250807000000_create_user_shard_mappings.rb**
   - Renamed from invalid timestamp format

4. **.env.local**
   - Added `SUPABASE_PROJECT_ID=bsbgwixlklvgeoxvjmtb`

## New Files Created

1. **test_db_setup.rb**
   - Comprehensive database verification script
   - Tests all critical functionality
   - All 6 tests passing

2. **bin/setup_db**
   - Automated setup script for new environments
   - Handles migration, seeding, and verification
   - Executable script for easy setup

## Verification Results

```
DATABASE SETUP VERIFICATION
================================================================================
Testing Database shard exists... ✅ PASSED
Testing User creation... ✅ PASSED
Testing App creation... ✅ PASSED
Testing Supabase sync job... ✅ PASSED
Testing V5 builder initialization... ✅ PASSED
Testing Test environment readiness... ✅ PASSED

RESULTS SUMMARY
================================================================================
✅ Passed: 6/6
🎉 All tests passed! Database is properly configured.
```

## Setup Instructions for New Environments

1. Clone the repository
2. Copy `.env.development.local` to `.env.local` and add your API keys
3. Make sure `SUPABASE_PROJECT_ID` is set
4. Run `bin/setup_db`
5. Verify with `ruby test_db_setup.rb`

## Known Issues / TODO

1. **DatabaseShard Model Connection**: The model has issues when accessed directly due to Rails 8 sharding. Needs investigation for proper fix.

2. **Encryption**: DatabaseShard keys are stored in plain text, not using Rails encryption yet.

3. **Test Environment**: May need additional configuration for parallel test execution.

## Database State

- **database_shards**: 1 record (shard-001, status: available)
- **user_shard_mappings**: Table exists, ready for use
- **Schema version**: Updated and synchronized with actual database
- **All migrations**: Up to date through 20250813124746