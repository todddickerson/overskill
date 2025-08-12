# Fix for Deployment Timeout Issue

## Problem
When clicking deploy/publish in the UI, you're experiencing a timeout. This is caused by:

1. **Wrong Queue Name**: The `PublishAppToProductionJob` was using `queue_as :deployments` (plural) but Sidekiq is configured to process the `deployment` queue (singular).

2. **App Status Issues**: Apps can get stuck in "generating" status which prevents publishing.

3. **Conflicting Deploy Actions**: There are two deploy mechanisms:
   - Old: `/account/apps/:id/deploy` -> uses `DeployAppJob`
   - New: `/account/apps/:id/publish` -> uses `PublishAppToProductionJob`

## Solution Applied

### 1. Fixed Queue Name
Changed `PublishAppToProductionJob` from:
```ruby
queue_as :deployments  # Wrong - not processed
```
To:
```ruby
queue_as :deployment   # Correct - matches sidekiq.yml
```

### 2. Updated Sidekiq Configuration
The `config/sidekiq.yml` already includes the `deployment` queue:
```yaml
:queues:
  - critical
  - ai_generation
  - deployment  # <-- This is the correct queue
  - default
```

### 3. Manual Fix for Stuck Apps
If an app is stuck in "generating" status:
```ruby
rails runner "App.find(ID).update!(status: 'ready')"
```

## How to Deploy to Production Now

### Via Rails Console:
```ruby
app = App.find(YOUR_APP_ID)
app.publish_to_production!
```

### Via UI (once fixed):
The publish button should call the `/account/apps/:id/publish` endpoint which will:
1. Queue the `PublishAppToProductionJob` in the `deployment` queue
2. Build the app using Vite
3. Deploy to Cloudflare Workers at `{subdomain}.overskill.app`
4. Update app status to "published"

## Verification
To verify an app is published:
```ruby
app = App.find(YOUR_APP_ID)
puts app.status           # Should be "published"
puts app.production_url   # Should be https://{subdomain}.overskill.app
puts app.published?       # Should be true
```

## Next Steps for UI
1. Ensure the UI calls the correct `/publish` endpoint (not `/deploy`)
2. Add a loading spinner while deployment is in progress
3. Show the production URL once published
4. Add an "Unpublish" button for published apps

## Testing
The production deployment has been tested and works:
- App #109 successfully deployed to `https://updated-1755027947.overskill.app`
- HTTP 200 response confirmed
- Subdomain can be updated and will trigger re-deployment