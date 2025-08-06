# App Versioning System Documentation

## Overview
The OverSkill platform maintains a comprehensive versioning system for generated applications, allowing users to track changes, restore previous versions, and maintain a complete history of their app's evolution.

## Architecture

### Database Schema

#### Core Tables
1. **`apps`** - The main application record
   - Contains current working files via `app_files` association
   - Has many `app_versions` for historical tracking

2. **`app_files`** - Current working files for each app
   - These are the files that get previewed and deployed
   - Directly modified during AI updates or manual edits
   - Structure:
     - `path` - File path (e.g., "index.html", "styles.css")
     - `content` - Current file content
     - `file_type` - Type classification (html, css, javascript, etc.)
     - `size_bytes` - File size in bytes
     - `is_entry_point` - Whether this is the main entry file
     - `team_id` - For multi-tenancy
     - `app_id` - Parent app reference

3. **`app_versions`** - Historical snapshots of the app
   - Created after AI updates, manual edits, or deployments
   - Structure:
     - `version_number` - Semantic version (e.g., "1.0.5")
     - `changelog` - Description of changes
     - `files_snapshot` - JSON snapshot of all files at this version
     - `changed_files` - List of files that were modified
     - `user_id` - Who made the changes
     - `team_id` - For multi-tenancy

### Version Storage System

All versions use the `files_snapshot` approach for consistency and efficiency:

#### `files_snapshot` Format
- Stores all files as a JSON blob in `app_versions.files_snapshot`
- Captures complete app state at time of version creation
- Format:
```json
[
  {
    "path": "index.html",
    "content": "<!DOCTYPE html>...",
    "file_type": "html"
  },
  {
    "path": "styles.css",
    "content": "body { ... }",
    "file_type": "css"
  }
]
```


## Version Creation Triggers

Versions are automatically created when:

1. **AI Updates** (via `AppUpdateOrchestrator`)
   - After successful AI-driven changes
   - Captures full file snapshot
   - Includes AI-generated changelog

2. **Manual Edits** (via `AppEditorsController#update_file`)
   - When users manually edit files in the code editor
   - Now captures full file snapshot (fixed)
   - Changelog indicates which file was edited

3. **Deployments** (via `DeployAppJob`)
   - When app is deployed to production
   - Marks the deployed state
   - Useful for rollback if issues arise

## Version Restore Process

The restore functionality (`AppVersionsController#restore`) works as follows:

1. **Creates a new version** - Never overwrites history
2. **Restores files from snapshot**:
   - First checks for `files_snapshot` (modern system)
   - Falls back to `app_version_files` (legacy system)
3. **Updates current `app_files`** with restored content
4. **Triggers preview update** to reflect changes
5. **Returns success with files restored count**

### Restore Process Details
1. **User triggers restore** from version history modal
2. **System creates new version** with "Restored from version X" changelog
3. **Clears current app_files** to ensure clean state
4. **Recreates all files** from the snapshot
5. **Copies snapshot** to new version for consistency
6. **Updates preview** automatically via background job

### Restore UI Flow
1. User opens version history modal
2. Sees list of versions with changelog and timestamp
3. Can preview or restore any version
4. Confirmation dialog before restore
5. Page refreshes to show restored content

## Implementation Files

### Controllers
- `/app/controllers/account/app_versions_controller.rb` - Version management and restore
- `/app/controllers/account/app_editors_controller.rb` - Manual edit versioning

### Services
- `/app/services/ai/app_update_orchestrator.rb` - AI update versioning
- `/app/services/ai/app_update_orchestrator_v2.rb` - Enhanced orchestrator with snapshots
- `/app/services/ai/app_update_orchestrator_streaming.rb` - Streaming version with snapshots

### Jobs
- `/app/jobs/process_app_update_job.rb` - Legacy job (uses app_version_files)
- `/app/jobs/process_app_update_job_v2.rb` - Modern job (delegates to orchestrator)
- `/app/jobs/deploy_app_job.rb` - Deployment versioning

### Views
- `/app/views/account/app_editors/_version_history_modal.html.erb` - Version history UI
- `/app/views/account/app_editors/_version_history_list.html.erb` - Version list component

### JavaScript
- `/app/javascript/controllers/version_preview_controller.js` - Handles preview/restore actions
- `/app/javascript/controllers/version_history_controller.js` - Modal management

## Best Practices

1. **Always capture snapshots** - Every version should include complete file state
2. **Never modify history** - Restore creates new versions, preserving history
3. **Meaningful changelogs** - Help users understand what changed
4. **Efficient storage** - Use `files_snapshot` for new versions
5. **Test restore functionality** - Ensure files are properly restored

## Standardized Implementation

As of August 2025, the system has been standardized to use only `files_snapshot`:
- All new versions capture complete file snapshots
- Restore only works with versions that have `files_snapshot`
- Legacy `app_version_files` table remains for historical data but is not actively used
- All controllers, jobs, and services use the same snapshot method

## Future Enhancements

1. **Diff visualization** - Show line-by-line changes between versions
2. **Branching** - Support multiple development branches
3. **Collaborative versioning** - Track who changed what in team environments
4. **Auto-save drafts** - Periodic snapshots during editing
5. **Version tagging** - Mark special versions (e.g., "v1.0 release")