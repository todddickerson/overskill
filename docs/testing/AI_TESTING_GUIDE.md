# AI Testing Guide for OverSkill

This guide enables Claude Code and other AI assistants to understand and execute OverSkill's golden flow testing framework.

## 🎯 Golden Flow Philosophy

**Golden flows are the critical user workflows that must always work:**
- Users clicking "Generate" and seeing apps created
- Users publishing apps and accessing live URLs  
- Users authenticating and accessing their dashboard

These flows represent real user value - not technical complexity.

## 🎭 Playwright MCP Integration

### Quick Start Commands

```bash
# Run all golden flow tests (simulation mode)
bin/rails runner "Testing::PlaywrightMcpService.new('development').run_golden_flow_tests"

# Run baseline performance measurements  
bin/rails runner "Testing::GoldenFlowBaselineService.new.measure_all_flows"

# Audit existing test coverage
bin/rails runner "Testing::TestAuditorService.new.analyze_test_coverage"
```

### Available Testing Services

#### 1. PlaywrightMcpService
**Purpose**: Execute golden flow tests using browser automation
**Status**: Simulation ready, MCP integration pending

```ruby
# Usage patterns for Claude Code:
service = Testing::PlaywrightMcpService.new('development')
results = service.run_golden_flow_tests
# Returns detailed success/failure results with timing
```

**Ready for Real MCP Integration**: Replace simulation methods with:
```ruby
# Instead of simulate_navigate(url)
mcp__playwright__playwright_navigate(url: url)

# Instead of simulate_click(selector)  
mcp__playwright__playwright_click(selector: selector)

# Instead of simulate_fill(selector, value)
mcp__playwright__playwright_fill(selector: selector, value: value)
```

#### 2. GoldenFlowBaselineService
**Purpose**: Establish performance baselines for critical workflows
**Status**: Fully operational

```ruby
# Measure actual app generation performance
service = Testing::GoldenFlowBaselineService.new
baseline = service.measure_actual_app_generation
# Returns: { duration: 1.7, files_created: 3, status: "success" }
```

#### 3. TestAuditorService
**Purpose**: Analyze existing test coverage and classify by golden flow relevance
**Status**: Fully operational

```ruby
# Get comprehensive test analysis
auditor = Testing::TestAuditorService.new  
report = auditor.analyze_test_coverage
# Returns golden flow coverage percentages and recommendations
```

## 🛡️ Authentication Requirements

OverSkill is a **Bullet Train Rails app** requiring authentication:

```ruby
# Test users are automatically created with proper associations:
# - User with email: "playwright-test@overskill.app"
# - Team membership with admin privileges  
# - Generated test apps with proper creator/team assignments
```

**For Claude Code**: Always ensure test data includes proper Bullet Train associations (User → Membership → Team → App).

## 📋 Golden Flow Definitions

Located in `config/playwright_golden_flows.yml`:

### 1. End-to-End App Generation
**User Journey**: Create app → Generate with AI → See files created
**Test Elements**: 
- `[data-testid="app-name"]` - App name input
- `[data-testid="generate-button"]` - Generation trigger  
- `[data-testid="generation-complete"]` - Success indicator
- `[data-testid="app-files-list"]` - Generated files display

### 2. End-to-End Publishing  
**User Journey**: Publish app → Access live URL → Verify deployment
**Test Elements**:
- `[data-testid="publish-button"]` - Publishing trigger
- `[data-testid="production-url"]` - Live URL display
- Dynamic URL extraction and new tab testing

### 3. Basic User Authentication
**User Journey**: Sign up → Log in → Access dashboard → View apps
**Test Elements**:
- `[data-testid="email-field"]` - Email input
- `[data-testid="dashboard"]` - Main dashboard
- `[data-testid="apps-section"]` - User's apps area

## 🔧 MCP Function Reference

When Playwright MCP is available, use these patterns:

### Navigation
```javascript
mcp__playwright__playwright_navigate({
  url: "http://localhost:3000/apps/new",
  timeout: 30000
})
```

### Form Interaction  
```javascript
mcp__playwright__playwright_fill({
  selector: '[data-testid="app-name"]',
  value: "My Test App"
})

mcp__playwright__playwright_click({
  selector: '[data-testid="generate-button"]'  
})
```

### Verification
```javascript
mcp__playwright__playwright_screenshot({
  name: "generation-complete",
  savePng: true
})

// Check console for errors
mcp__playwright__playwright_console_logs({
  type: "error",
  clear: false
})
```

### Advanced Workflows
```javascript
// Extract dynamic values (like production URLs)
mcp__playwright__playwright_evaluate({
  script: `document.querySelector('[data-testid="production-url"]').textContent`
})

// New tab navigation for deployment verification
mcp__playwright__playwright_click_and_switch_tab({
  selector: '[data-testid="external-link"]'
})
```

## 🎨 Data-TestID Strategy

**For Claude Code UI Development**:
Always add `data-testid` attributes to critical user interface elements:

```erb
<!-- Generation form -->
<%= form.text_field :name, data: { testid: "app-name" } %>
<%= button_tag "Generate", data: { testid: "generate-button" } %>

<!-- Progress indicators -->
<div data-testid="generation-progress">Generating...</div>
<div data-testid="generation-complete" style="display: none;">Complete!</div>

<!-- Results display -->
<ul data-testid="app-files-list">
  <% @app.app_files.each do |file| %>
    <li><%= file.path %></li>
  <% end %>
</ul>
```

**Naming Convention**: Use kebab-case describing the element's purpose from a user perspective.

## 📊 Reporting and Analysis

### Test Reports
Generated in `test/reports/` with markdown format including:
- ✅/❌ Flow success indicators
- ⏱️ Execution timing  
- 🎯 Success criteria validation
- 💡 Next steps for real MCP integration

### Performance Baselines
Track these key metrics:
- **App Generation Time**: Target < 2.0s (current: ~1.7s)
- **File Creation Count**: Expect 3+ files (HTML, JS, CSS)
- **Authentication Flow**: Target < 1.0s for dashboard load
- **Publishing Deployment**: Target < 180s for live URL

## 🚀 Integration with Claude Code

### Recommended Workflow

1. **Before UI Changes**: Run baseline tests to establish current performance
```bash
bin/rails runner "Testing::GoldenFlowBaselineService.new.measure_all_flows"
```

2. **After UI Changes**: Run golden flow tests to verify functionality  
```bash  
bin/rails runner "Testing::PlaywrightMcpService.new('development').run_golden_flow_tests"
```

3. **Before Deployment**: Ensure all golden flows pass
```bash
bin/rails runner "Testing::PlaywrightMcpService.new('production').run_golden_flow_tests"
```

### AI Decision Making

**When Golden Flows Fail**: 
- Prioritize fixing golden flows over other testing
- Focus on actual user-clicking workflows, not controller/API complexity
- Ensure `data-testid` attributes exist for new UI elements

**When Adding Features**:
- Update golden flow definitions if core user workflows change
- Add baseline measurements for performance-critical features
- Consider authentication requirements for new protected flows

## 🎭 Ready for Real Browser Testing

The framework is designed for seamless transition from simulation to real browser automation:

1. **Simulation Mode** (Current): All methods prefixed with `simulate_` 
2. **MCP Integration** (Ready): Replace simulations with `mcp__playwright__*` calls
3. **Hybrid Mode** (Future): Combine real browser testing with intelligent fallbacks

**Claude Code can immediately start using real Playwright MCP** by modifying the service methods - the configuration, flows, and reporting infrastructure is complete.

---

*This guide enables AI assistants to protect OverSkill's golden flows through intelligent, user-focused browser testing. 🎯*