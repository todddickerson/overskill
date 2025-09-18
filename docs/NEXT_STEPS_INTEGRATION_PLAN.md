# Next Steps: Fast Deployment Integration Plan

## Current State Assessment

### ✅ What's Complete
1. **Backend Infrastructure**
   - FastBuildService (Vite-based) - Ready
   - ActionCable AppPreviewChannel - Ready
   - EdgePreviewService - Ready
   - PuckToReactService - Ready
   - Database state tracking - Ready
   - HMR client JavaScript - Created but not integrated

2. **Documentation**
   - Architecture plan - Complete
   - Testing checklist - Complete
   - Production rollout plan - Complete
   - Vite integration - Complete

### ❌ What's Missing
1. **Frontend Integration**
   - HMR client not loaded in preview frame
   - PuckEditor not installed in package.json
   - No UI for manual edit mode toggle

2. **Pipeline Integration**
   - AppBuilderV5 uses DeployAppJob (3-5 min)
   - Not using EdgePreviewService (5-10s)
   - No fast preview deployment trigger

3. **Testing Infrastructure**
   - No test app created
   - HMR flow not validated
   - Performance benchmarks not run

## Immediate Next Steps

### 1. Frontend HMR Integration via ActionCable (Priority: HIGH)
**Goal**: Enable HMR in preview iframe using ActionCable (NOT Durable Objects)

#### Architecture Decision: ActionCable over Durable Objects
**Date**: September 2025
**Decision**: Use ActionCable for HMR instead of Durable Objects

**Why ActionCable Wins**:
- **No hibernation delays**: Always instant 50ms updates (vs 2s wake-up after idle)
- **Simpler architecture**: Users already connected to Rails for editing
- **Cost-free**: Uses existing Rails infrastructure (vs $5/month per 1000 apps)
- **More reliable**: Single connection path (vs complex edge routing)
- **Consistent UX**: Predictable latency regardless of idle time

#### Tasks:
```erb
# app/views/account/app_editors/_preview_frame.html.erb
# Add after line 45 (before iframe):
<% if app.preview_url.present? %>
  <div data-controller="hmr"
       data-hmr-app-id-value="<%= app.id %>"
       data-hmr-channel-value="AppPreviewChannel">
    <!-- ActionCable HMR connection managed by Stimulus -->
    <%= turbo_stream_from "app_preview_#{app.id}" %>
  </div>
<% end %>
```

#### Update Stimulus controller for ActionCable:
```javascript
// app/javascript/controllers/hmr_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static values = { appId: String }

  connect() {
    // Connect to ActionCable AppPreviewChannel (NOT Durable Objects)
    this.channel = consumer.subscriptions.create(
      {
        channel: "AppPreviewChannel",
        app_id: this.appIdValue
      },
      {
        received: (data) => this.handleHMRUpdate(data),
        connected: () => console.log("[HMR] Connected via ActionCable"),
        disconnected: () => console.log("[HMR] Disconnected")
      }
    )
  }

  handleHMRUpdate(data) {
    if (data.type === 'file_update') {
      // Update preview iframe without full reload
      const iframe = document.querySelector('#preview_frame iframe')
      if (iframe && data.path && data.content) {
        // Inject updated file via postMessage to iframe
        iframe.contentWindow.postMessage({
          type: 'hmr_update',
          path: data.path,
          content: data.content
        }, '*')
      }
    }
  }

  disconnect() {
    if (this.channel) {
      this.channel.unsubscribe()
    }
  }
}
```

### 2. Fast Preview Deployment Hook (Priority: HIGH)
**Goal**: Use EdgePreviewService for instant preview

#### Modify AppBuilderV5:
```ruby
# app/services/ai/app_builder_v5.rb
def deploy_app
  # NEW: Fast preview deployment
  if ENV['FAST_PREVIEW_ENABLED'] == 'true'
    deploy_fast_preview
  else
    deploy_standard # existing code
  end
end

def deploy_fast_preview
  Rails.logger.info "[V5_FAST_DEPLOY] Starting fast preview deployment"
  
  # Use EdgePreviewService for instant deployment
  service = EdgePreviewService.new(@app)
  result = service.deploy_preview
  
  if result[:success]
    @app.update!(preview_url: result[:preview_url])
    broadcast_deployment_progress(
      status: 'deployed',
      progress: 100,
      phase: 'Preview ready!',
      deployment_url: result[:preview_url]
    )
    
    # Queue GitHub sync in background (non-blocking)
    GitHubSyncJob.perform_later(@app.id)
  end
  
  result
end
```

### 3. Install PuckEditor (Priority: MEDIUM)
**Goal**: Enable visual editing mode

```bash
# Add to package.json
npm install @measured/puck --save

# Create React component
# app/javascript/components/PuckEditorWrapper.jsx
```

### 4. Create Test Flow (Priority: HIGH)
**Goal**: Validate end-to-end system

#### Test Script:
```ruby
# scripts/test_fast_deployment.rb
require_relative '../config/environment'

class FastDeploymentTester
  def run
    puts "🚀 Testing Fast Deployment System"
    
    # 1. Create test app
    app = create_test_app
    
    # 2. Deploy with EdgePreviewService
    deploy_result = test_edge_preview(app)
    
    # 3. Test HMR update
    hmr_result = test_hmr_update(app)
    
    # 4. Benchmark performance
    benchmark_results = run_benchmarks(app)
    
    # 5. Report results
    print_results(deploy_result, hmr_result, benchmark_results)
  end
  
  private
  
  def create_test_app
    team = Team.first
    app = App.create!(
      name: "Fast Deploy Test #{Time.current.to_i}",
      team: team,
      status: 'generated'
    )
    
    # Add sample files
    app.app_files.create!(
      path: 'src/App.tsx',
      content: 'export default function App() { return <div>Test App</div> }'
    )
    
    app
  end
  
  def test_edge_preview(app)
    start_time = Time.current
    service = EdgePreviewService.new(app)
    result = service.deploy_preview
    
    {
      success: result[:success],
      deploy_time: ((Time.current - start_time) * 1000).round,
      preview_url: result[:preview_url]
    }
  end
  
  def test_hmr_update(app)
    # Update a file
    file = app.app_files.first
    original_content = file.content
    
    start_time = Time.current
    
    # Trigger HMR update via ActionCable
    channel = AppPreviewChannel.new(nil, nil)
    channel.update_file({
      'path' => file.path,
      'content' => 'export default function App() { return <div>Updated!</div> }'
    })
    
    update_time = ((Time.current - start_time) * 1000).round
    
    # Restore original
    file.update!(content: original_content)
    
    {
      success: true,
      update_time: update_time
    }
  end
  
  def run_benchmarks(app)
    {
      single_file_compile: benchmark_single_file(app),
      full_bundle_build: benchmark_full_bundle(app),
      incremental_build: benchmark_incremental(app)
    }
  end
  
  def benchmark_single_file(app)
    service = FastBuildService.new(app)
    
    start = Time.current
    result = nil
    service.build_file_async("test.tsx", "const x = 1") do |r|
      result = r
    end
    sleep 0.1 while result.nil?
    
    ((Time.current - start) * 1000).round
  end
  
  def benchmark_full_bundle(app)
    service = FastBuildService.new(app)
    
    start = Time.current
    service.build_full_bundle
    ((Time.current - start) * 1000).round
  end
  
  def benchmark_incremental(app)
    service = FastBuildService.new(app)
    
    start = Time.current
    service.incremental_build(['src/App.tsx'])
    ((Time.current - start) * 1000).round
  end
  
  def print_results(deploy, hmr, benchmarks)
    puts "\n📊 Test Results:"
    puts "=" * 50
    
    puts "\n🚀 Deployment:"
    puts "  Deploy time: #{deploy[:deploy_time]}ms (target: <10,000ms)"
    puts "  Preview URL: #{deploy[:preview_url]}"
    puts "  Status: #{deploy[:success] ? '✅' : '❌'}"
    
    puts "\n⚡ HMR Update:"
    puts "  Update time: #{hmr[:update_time]}ms (target: <100ms)"
    puts "  Status: #{hmr[:success] ? '✅' : '❌'}"
    
    puts "\n📈 Benchmarks:"
    puts "  Single file: #{benchmarks[:single_file_compile]}ms (target: <100ms)"
    puts "  Full bundle: #{benchmarks[:full_bundle_build]}ms (target: <2000ms)"
    puts "  Incremental: #{benchmarks[:incremental_build]}ms (target: <500ms)"
    
    puts "\n" + "=" * 50
    
    # Overall assessment
    all_passing = deploy[:deploy_time] < 10_000 &&
                  hmr[:update_time] < 100 &&
                  benchmarks[:single_file_compile] < 100 &&
                  benchmarks[:full_bundle_build] < 2000 &&
                  benchmarks[:incremental_build] < 500
    
    if all_passing
      puts "✅ ALL TESTS PASSING - System ready for production!"
    else
      puts "⚠️  Some targets not met - review performance"
    end
  end
end

# Run the test
FastDeploymentTester.new.run
```

## Critical Path to Production

### Phase 1: Wire Up (TODAY)
1. [ ] Add HMR client to preview frame
2. [ ] Create Stimulus controller for HMR
3. [ ] Add environment flag for fast preview
4. [ ] Run test script to validate

### Phase 2: Integration (THIS WEEK)
1. [ ] Modify AppBuilderV5 to use EdgePreviewService
2. [ ] Setup GitHub sync as background job
3. [ ] Install PuckEditor npm package
4. [ ] Create PuckEditor React wrapper

### Phase 3: Testing (NEXT WEEK)
1. [ ] Run full benchmark suite
2. [ ] Test with 10 concurrent apps
3. [ ] Validate HMR with complex apps
4. [ ] Load test WebSocket connections

### Phase 4: Rollout (2 WEEKS)
1. [ ] Enable for internal team
2. [ ] Monitor performance metrics
3. [ ] Gradual user rollout
4. [ ] Full production deployment

## Blocking Issues

### Must Fix Before Production:
1. **HMR client not loaded** - Preview iframe doesn't include HMR JavaScript
2. **No fast deploy trigger** - AppBuilderV5 still uses slow DeployAppJob
3. **Missing npm packages** - PuckEditor not installed
4. **No test coverage** - Need automated tests for HMR flow

### Nice to Have:
1. Vite dev server integration for local development
2. Advanced PuckEditor components
3. Performance monitoring dashboard
4. A/B testing framework

## Success Criteria

### Minimum Viable Product:
- [ ] Preview deploys in <10s
- [ ] HMR updates in <100ms
- [ ] Works with existing app generation
- [ ] No regression in current features

### Full Success:
- [ ] PuckEditor visual editing works
- [ ] 1000+ concurrent preview sessions
- [ ] GitHub sync runs in background
- [ ] Zero downtime deployment

## Command Summary

```bash
# Test the system
bin/rails runner scripts/test_fast_deployment.rb

# Enable fast preview
export FAST_PREVIEW_ENABLED=true

# Monitor performance
tail -f log/development.log | grep -E "FAST|HMR|EdgePreview"

# Check WebSocket connections
bin/rails runner "puts ActionCable.server.connections.count"
```

## Recommendation

**IMMEDIATE ACTION**: Wire up the HMR client in the preview frame and run the test script. This will validate that our architecture works end-to-end before investing more time in UI polish and advanced features.

The system is architecturally complete but needs these final integration points to become functional.