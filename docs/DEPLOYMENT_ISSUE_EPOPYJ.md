# Deployment Investigation: App ePopYJ

## Issue Summary
**Date**: August 29, 2025  
**App**: Calculator (ID: 1574, Obfuscated: ePopYJ)  
**Problems**:
1. Preview deployment shows template content instead of generated calculator
2. Production deployment shows correct calculator content  
3. GitHub monitor service failed to detect the deployment

## Investigation Findings

### 1. GitHub Actions Workflow Execution
- **Workflow Run**: [17331988134](https://github.com/Overskill-apps/calccraft-ePopYJ/actions/runs/17331988134)
- **Status**: ✅ Completed successfully
- **Time**: 2025-08-29T18:56:58Z to 2025-08-29T18:58:20Z
- **Both preview and production deployed**: Same `dist/index.js` file used for both

### 2. Build Process Analysis
- **Generated Content**: Calculator app correctly generated in `src/pages/Index.tsx`
- **Build Output**: Contains "Calccraft - Modern Calculator" in HTML title
- **Bundle**: Same `dist/index.js` deployed to both environments
- **Validation**: Added 8 React imports automatically, build succeeded

### 3. GitHub Monitor Service Failure
```
[DeployAppJob] GitHub Actions deployment failed: 
No workflow runs found after 3 minutes of retrying
```

**Root Cause**: Timing issue between:
- DeployAppJob triggering the deployment
- GitHub Actions workflow starting
- Monitor service checking for workflow runs

The monitor service gave up after 3 minutes but the workflow did run successfully.

### 4. Preview vs Production Discrepancy

**Evidence**:
- Preview URL: https://preview-epopyj.overskill.app (shows "OverSkill App" template)
- Production URL: https://epopyj.overskill.app (shows "Calccraft" calculator)
- Same build artifact deployed to both environments

**Possible Causes**:
1. **CloudFlare WFP Caching**: Preview namespace may have cached old worker
2. **Namespace Configuration**: Preview namespace might have different settings
3. **Deployment Order**: Preview deployed first, might have been overwritten
4. **Worker Script Name Collision**: `preview-epopyj` might conflict with existing worker

## Technical Details

### Deployment Flow
1. AppBuilderV5 completes generation
2. DeployAppJob enqueued with 5-second delay
3. GitHub repository updated with 85 files
4. Commit includes `[production]` tag
5. GitHub Actions workflow triggered
6. Both preview and production deployments executed
7. Monitor service couldn't find workflow runs (timing issue)

### GitHub Actions Deployment Commands
```bash
# Preview deployment
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/dispatch/namespaces/overskill-development-preview/scripts/preview-epopyj"

# Production deployment  
curl -X PUT "https://api.cloudflare.com/client/v4/accounts/${CLOUDFLARE_ACCOUNT_ID}/workers/dispatch/namespaces/overskill-development-production/scripts/epopyj"
```

## Update: Re-deployment Attempt

Triggered re-deployment via new commit (workflow run 17332494732) - completed successfully but preview still shows template content. This confirms the issue is with the CloudFlare WFP preview namespace configuration, not the deployment process.

## Recommended Fixes

### 1. Fix Preview Deployment (Requires CloudFlare Access)
The issue is confirmed to be at the CloudFlare WFP level. Options:
1. **Clear worker script directly via CloudFlare API**
2. **Check preview namespace routing configuration**
3. **Verify preview subdomain DNS/routing**
4. **Possible namespace-level caching or override**

### 2. Fix GitHub Monitor Service (Code)
```ruby
# app/services/deployment/github_actions_monitor_service.rb
def get_workflow_runs_with_retry(max_retry_time: 5.minutes) # Increase from 3 minutes
  # Add initial delay for workflow to start
  if @app.updated_at > 1.minute.ago
    Rails.logger.info "[GithubActionsMonitor] Recent deployment, waiting 30s for workflow to start"
    sleep 30
  end
  
  # ... rest of retry logic
end
```

### 3. Add Deployment Verification
```ruby
# app/jobs/deploy_app_job.rb
def verify_deployment_urls(app)
  preview_check = HTTParty.get(app.preview_url)
  production_check = HTTParty.get(app.production_url)
  
  # Verify content matches expected app
  preview_valid = preview_check.body.include?(app.name)
  production_valid = production_check.body.include?(app.name)
  
  unless preview_valid && production_valid
    Rails.logger.error "[DeployAppJob] Deployment verification failed"
    # Trigger re-deployment or alert
  end
end
```

### 4. Improve Worker Deployment Reliability
- Add retry logic for CloudFlare API calls
- Implement cache purge before deployment
- Add deployment verification endpoint
- Use different script names to avoid conflicts

## Prevention

1. **Increase monitor timeout**: Give workflows more time to start
2. **Add initial delay**: Wait before checking for workflow runs  
3. **Verify deployments**: Check actual content after deployment
4. **Cache management**: Clear CloudFlare cache before preview deployments
5. **Better error handling**: Detect and retry transient failures

## Related Issues
- Similar to jWbgQN deployment issue (missing DeployAppJob)
- Part of broader deployment reliability improvements needed
- CloudFlare WFP preview environment needs investigation