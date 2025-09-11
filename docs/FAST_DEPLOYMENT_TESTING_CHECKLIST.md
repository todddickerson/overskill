# Fast Deployment Testing Checklist

## Pre-Test Setup
- [ ] Ensure Redis is running: `redis-cli ping`
- [ ] Verify Sidekiq is running: `bundle exec sidekiq -C config/sidekiq.yml`
- [ ] Check ESBuild is installed: `which esbuild`
- [ ] Confirm Cloudflare credentials are set in `.env`
- [ ] Database migrations are current: `bin/rails db:migrate:status`

## 1. ActionCable WebSocket Testing

### Connection Tests
- [ ] Open browser console and verify WebSocket connection establishes
- [ ] Check for "HMR Connected" indicator in bottom-left corner
- [ ] Verify auto-reconnection after killing Rails server and restarting
- [ ] Test multiple browser tabs connect to same app channel
- [ ] Confirm app-specific isolation (different apps don't receive each other's updates)

### Test Commands
```bash
# Monitor WebSocket connections
bin/rails c
> ActionCable.server.connections.count

# Test broadcast
> AppPreviewChannel.broadcast_to(App.last, {type: 'test', message: 'Hello'})

# Check Redis subscriptions
redis-cli
> PUBSUB CHANNELS
```

## 2. FastBuildService Testing

### Build Performance Tests
- [ ] Single file compilation completes in <100ms
- [ ] Full app bundle builds in <2s
- [ ] Incremental builds complete in <500ms
- [ ] Cache hit returns instantly (<10ms)
- [ ] Source maps generate correctly

### Test Scenarios
```ruby
# Rails console tests
app = App.last
service = FastBuildService.new(app)

# Test single file build
service.build_file_async("src/App.tsx", "export default function App() { return <div>Test</div> }") do |result|
  puts "Build time: #{result[:build_time]}ms"
  puts "Success: #{result[:success]}"
end

# Test full bundle
result = service.build_full_bundle
puts "Bundle size: #{result[:bundle].bytesize} bytes"
puts "Build time: #{result[:build_time]}ms"

# Test cache
# Run same build twice - second should be instant
```

## 3. HMR Client Testing

### Live Update Tests
- [ ] CSS changes apply without page refresh
- [ ] Component updates preserve state
- [ ] Error overlay shows for build failures
- [ ] Multiple file updates batch correctly
- [ ] Source maps work in DevTools

### Manual Testing Steps
1. Open app in preview mode
2. Open browser DevTools console
3. Edit a CSS file via Rails console:
   ```ruby
   app = App.last
   channel = AppPreviewChannel.new(nil, nil)
   channel.update_file({
     'path' => 'src/styles/app.css',
     'content' => 'body { background: red; }'
   })
   ```
4. Verify background changes instantly without refresh
5. Check console for "[HMR] ✓ Updated src/styles/app.css"

## 4. EdgePreviewService Testing

### Deployment Tests
- [ ] Preview deploys in <2s
- [ ] Worker script stays under 10MB limit
- [ ] Custom domain routing works
- [ ] KV storage updates persist
- [ ] WebSocket connection establishes

### Test Commands
```ruby
# Deploy preview
app = App.last
service = EdgePreviewService.new(app)
result = service.deploy_preview
puts "Deploy time: #{result[:deploy_time]}ms"
puts "Preview URL: #{result[:preview_url]}"

# Test file update
service.update_file("src/App.tsx", "new content")

# Verify deployment
HTTParty.get(app.preview_url)
```

## 5. PuckToReactService Testing

### Conversion Tests
- [ ] Button component generates correctly
- [ ] Text component includes proper content
- [ ] Card component has all sections
- [ ] Container wraps children properly
- [ ] Hero component includes CTAs
- [ ] Styles generate with components

### Test Puck Configuration
```ruby
app = App.last
service = PuckToReactService.new(app)

puck_data = {
  'root' => {
    'children' => [
      {
        'type' => 'Hero',
        'props' => {
          'title' => 'Test Hero',
          'subtitle' => 'Test subtitle'
        }
      }
    ]
  }
}

result = service.convert(puck_data)
puts "Generated #{result[:files].keys}"
puts result[:files]['src/App.tsx']
```

## 6. End-to-End Integration Tests

### Full Flow Test
1. [ ] Generate new app with AI
2. [ ] Verify preview deploys in <10s
3. [ ] Make CSS change - verify HMR update
4. [ ] Make component change - verify hot reload
5. [ ] Add PuckEditor component - verify renders
6. [ ] Save Puck changes - verify conversion
7. [ ] Check database state tracking is accurate

### Performance Benchmarks
Record actual times:
- [ ] Initial preview deployment: _____ seconds (target: <10s)
- [ ] CSS HMR update: _____ ms (target: <100ms)
- [ ] Component hot reload: _____ ms (target: <500ms)
- [ ] Full bundle rebuild: _____ seconds (target: <2s)
- [ ] Edge propagation: _____ ms (target: <500ms)

## 7. Database State Tracking

### AppDeployment Model Tests
- [ ] `start_build!` sets correct status and timestamp
- [ ] `complete_build!` calculates duration correctly
- [ ] `complete_deployment!` updates all fields
- [ ] `fail_deployment!` captures error details
- [ ] Deployment scopes return correct records

### Test Commands
```ruby
app = App.last
deployment = AppDeployment.create_for_environment!(
  app: app,
  environment: 'preview',
  deployment_id: SecureRandom.uuid
)

deployment.start_build!
sleep 1
deployment.complete_build!
puts "Build duration: #{deployment.build_duration_seconds}s"

deployment.complete_deployment!("https://test.overskill.app")
puts "Status: #{deployment.status}"
```

## 8. Error Handling Tests

### Failure Scenarios
- [ ] ESBuild compilation error shows in UI
- [ ] Worker script >10MB rejected gracefully
- [ ] WebSocket disconnection auto-recovers
- [ ] Redis down falls back gracefully
- [ ] Cloudflare API errors handled
- [ ] Invalid Puck data doesn't crash

### Test Error Cases
```ruby
# Test build error
service = FastBuildService.new(App.last)
service.build_file_async("test.tsx", "invalid { syntax") do |result|
  puts "Error: #{result[:error]}"
end

# Test oversized bundle
app = App.last
app.app_files.create!(
  path: "huge.js",
  content: "x" * 11_000_000  # 11MB
)
EdgePreviewService.new(app).deploy_preview
```

## 9. Load Testing

### Concurrent User Tests
- [ ] 10 concurrent preview sessions work
- [ ] 50 concurrent HMR updates process
- [ ] 100 WebSocket connections stable
- [ ] 1000 preview deployments/hour sustainable

### Load Test Script
```ruby
# test/load/preview_load_test.rb
require 'concurrent'

pool = Concurrent::FixedThreadPool.new(10)
apps = App.limit(10)

apps.each do |app|
  pool.post do
    service = EdgePreviewService.new(app)
    result = service.deploy_preview
    puts "App #{app.id}: #{result[:deploy_time]}ms"
  end
end

pool.shutdown
pool.wait_for_termination
```

## 10. Production Readiness

### Final Checks
- [ ] All tests pass in CI/CD pipeline
- [ ] Monitoring dashboards configured
- [ ] Error tracking integrated (Sentry/Rollbar)
- [ ] Performance metrics baseline established
- [ ] Rollback procedure documented
- [ ] Team trained on new architecture

### Deployment Verification
```bash
# Check all services running
ps aux | grep -E "sidekiq|redis|rails"

# Verify WebSocket connections
bin/rails runner "puts ActionCable.server.connections.count"

# Test preview deployment
bin/rails runner "EdgePreviewService.new(App.last).deploy_preview"

# Monitor logs
tail -f log/development.log | grep -E "HMR|FastBuild|EdgePreview"
```

## Sign-off

- [ ] Development team approval
- [ ] QA team validation
- [ ] DevOps infrastructure review
- [ ] Product owner acceptance
- [ ] Documentation complete

---

**Testing Environment**: Development
**Tester**: _________________
**Date**: _________________
**All Tests Passed**: ☐ Yes ☐ No

**Notes/Issues Found**:
_________________________________
_________________________________
_________________________________