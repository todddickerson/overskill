# Legacy Code Cleanup Plan
**Date**: January 26, 2025  
**Purpose**: Remove confusion and technical debt from deployment pipeline

## 🎯 Current State Analysis

### Active Pipeline (KEEP)
```
ProcessAppUpdateJobV5 → AppBuilderV5 → DeployAppJob
```

### Legacy Pipeline (REMOVE)
```
ProcessAppUpdateJobV3 → Orchestrators → Old Builders
ProcessAppUpdateJobV4 → (bypassed by V5)
```

## 📝 Files to Clean Up

### Phase 1: Remove Deprecated Jobs (Immediate)
```ruby
# Files to DELETE
/app/jobs/process_app_update_job_v3.rb  # Superseded by V5
/app/jobs/process_app_update_job_v4.rb  # V5 bypasses this entirely
/app/jobs/deploy_built_app_job.rb       # Replaced by DeployAppJob
/app/jobs/publish_app_to_production_job.rb  # Merged into DeployAppJob

# Action Required
1. Search for references to these jobs
2. Update any remaining references to use V5
3. Delete files
4. Remove from job queues/sidekiq
```

### Phase 2: Fix Broken References
```ruby
# app/jobs/app_generation_job.rb - Line 56
# CURRENT (BROKEN):
orchestrator = Ai::AppUpdateOrchestratorV3Optimized.new(message)
result = orchestrator.execute!

# FIXED:
# Use ProcessAppUpdateJobV5 which delegates to AppBuilderV5
# This maintains consistency with the rest of the pipeline
ProcessAppUpdateJobV5.perform_later(message)
# Remove the result handling as it's now async
```

### Phase 3: Remove Deprecated Services
```ruby
# Files to DELETE (after verification)
/app/services/deployment/fast_preview_service.rb           # Replaced by new architecture
/app/services/deployment/fast_preview_service_simple.rb    # Test/duplicate
/app/services/deployment/production_deployment_service.rb  # Old approach
/app/services/deployment/automated_cloudflare_deployment_service.rb  # Pre-WFP

# Files to KEEP but REFACTOR
/app/services/deployment/wfp_preview_service.rb  # Update for ActionCable
/app/services/deployment/cloudflare_workers_deployer.rb  # Still needed
```

### Phase 4: Clean Test/Debug Files
```ruby
# Files to DELETE from root
/test_deployment_fix.rb      # Debug file
/test_fixed_deployment.rb    # Debug file  
/redeploy_app.rb            # Debug script

# Move to /scripts/debug/ if needed for reference
```

## 🔧 ProcessAppUpdateJobV5 Refactor

### Current Implementation (Confusing)
```ruby
# app/jobs/process_app_update_job_v5.rb
class ProcessAppUpdateJobV5 < ApplicationJob
  def perform(message_or_id)
    # Just delegates to AppBuilderV5
    service = Ai::AppBuilderV5.new(message)
    service.execute!
  end
end
```

### Recommended Refactor (Clear)
```ruby
# app/jobs/process_app_update_job_v5.rb
class ProcessAppUpdateJobV5 < ApplicationJob
  queue_as :ai_processing
  
  # This is the CURRENT active job for processing AI app updates
  # Pipeline: User Message → This Job → AppBuilderV5 → File Creation
  # 
  # Legacy versions (V3, V4) have been removed - DO NOT resurrect them
  # 
  # @param message_or_id [AppChatMessage, Integer, String] The message to process
  def perform(message_or_id)
    message = resolve_message(message_or_id)
    
    Rails.logger.info "[ProcessAppUpdateJobV5] Processing message ##{message.id}"
    Rails.logger.info "[ProcessAppUpdateJobV5] App: #{message.app.name} (##{message.app.id})"
    
    # Track in database for Rails best practices
    update_app_status(message.app, 'processing')
    
    # Execute with AppBuilderV5 - our single source of truth for AI building
    service = Ai::AppBuilderV5.new(message)
    result = service.execute!
    
    # Update database state
    if result
      update_app_status(message.app, 'generated')
      trigger_deployment_if_enabled(message.app)
    else
      update_app_status(message.app, 'failed')
    end
  end
  
  private
  
  def resolve_message(message_or_id)
    case message_or_id
    when AppChatMessage
      message_or_id
    when Integer, String
      AppChatMessage.find(message_or_id)
    else
      # Handle GlobalID cases
      AppChatMessage.find(message_or_id)
    end
  end
  
  def update_app_status(app, status)
    app.update!(
      status: status,
      last_processed_at: Time.current
    )
  end
  
  def trigger_deployment_if_enabled(app)
    if ENV["AUTO_DEPLOY_AFTER_GENERATION"] == "true"
      # Queue deployment as parallel background job
      DeployAppJob.perform_later(app.id)
      
      # Also queue GitHub sync for version control
      # This runs in parallel, non-blocking
      GithubSyncJob.perform_later(app.id) if defined?(GithubSyncJob)
    end
  end
end
```

## 🗄️ Database State Tracking

### Add Migration for Better State Tracking
```ruby
class AddDeploymentTrackingToApps < ActiveRecord::Migration[7.1]
  def change
    # Track processing state
    add_column :apps, :last_processed_at, :datetime
    add_column :apps, :processing_started_at, :datetime
    add_column :apps, :processing_completed_at, :datetime
    
    # Track deployment state in AppDeployment
    add_column :app_deployments, :status, :string, default: 'pending'
    add_column :app_deployments, :build_started_at, :datetime
    add_column :app_deployments, :build_completed_at, :datetime
    add_column :app_deployments, :deploy_started_at, :datetime
    add_column :app_deployments, :deploy_completed_at, :datetime
    add_column :app_deployments, :build_duration_seconds, :integer
    add_column :app_deployments, :deploy_duration_seconds, :integer
    add_column :app_deployments, :error_message, :text
    
    # Add indexes for performance
    add_index :app_deployments, :status
    add_index :app_deployments, [:app_id, :environment, :status]
  end
end
```

### Update AppDeployment Model
```ruby
class AppDeployment < ApplicationRecord
  # Add status enum
  enum status: {
    pending: 'pending',
    building: 'building',
    deploying: 'deploying',
    deployed: 'deployed',
    failed: 'failed',
    rolled_back: 'rolled_back'
  }, _prefix: :deployment
  
  # Add callbacks to track durations
  before_save :calculate_durations
  
  private
  
  def calculate_durations
    if build_started_at && build_completed_at
      self.build_duration_seconds = (build_completed_at - build_started_at).to_i
    end
    
    if deploy_started_at && deploy_completed_at
      self.deploy_duration_seconds = (deploy_completed_at - deploy_started_at).to_i
    end
  end
end
```

## 📊 Cleanup Execution Plan

### Week 1: Analysis & Testing
- [ ] Run test suite to ensure no hidden dependencies
- [ ] Search codebase for references to deprecated files
- [ ] Document any unexpected dependencies

### Week 2: Gradual Removal
- [ ] Day 1: Remove test/debug files from root
- [ ] Day 2: Fix AppGenerationJob reference
- [ ] Day 3: Remove V3/V4 job files
- [ ] Day 4: Remove deprecated services
- [ ] Day 5: Run full test suite

### Week 3: Database Updates
- [ ] Create and run migration for state tracking
- [ ] Update models with new tracking logic
- [ ] Update DeployAppJob to use new fields

### Week 4: Documentation
- [ ] Update all documentation
- [ ] Remove references to old pipeline
- [ ] Create architecture diagram of new flow

## ✅ Success Criteria
- No references to V3/V4 jobs remain
- All tests pass
- Deployment pipeline works end-to-end
- Database properly tracks all state changes
- Code is well-commented
- Documentation is current

## 🚨 Rollback Plan
If issues arise:
1. Revert Git commits
2. Restore deleted files from Git history
3. Re-deploy previous version
4. Investigate issues before re-attempting

## Notes
- Keep Git history clean with meaningful commit messages
- Tag repository before major deletions
- Consider keeping deprecated files in archive branch temporarily