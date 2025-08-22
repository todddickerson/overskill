# MCP Integration Patterns for OverSkill Testing

This document provides specific patterns for integrating Playwright MCP with OverSkill's golden flow testing framework.

## 🎭 Playwright MCP Service Integration

### Current Architecture

```ruby
# app/services/testing/playwright_mcp_service.rb
class Testing::PlaywrightMcpService
  # Simulation methods (current)
  def simulate_navigate(url) -> Ready for MCP replacement
  def simulate_click(selector) -> Ready for MCP replacement  
  def simulate_fill(selector, value) -> Ready for MCP replacement
end
```

### MCP Integration Checklist

- [ ] **Step 1**: Verify Playwright MCP availability in Claude Code environment
- [ ] **Step 2**: Replace simulation methods with real MCP calls
- [ ] **Step 3**: Test golden flows with real browser automation
- [ ] **Step 4**: Add error handling for MCP-specific issues
- [ ] **Step 5**: Implement screenshot capture and console monitoring

## 🔄 Replacement Patterns

### Navigation Flow
```ruby
# BEFORE (Simulation)
def simulate_navigate(url)
  puts "→ Navigate to #{url}"
  true
end

# AFTER (Real MCP)  
def navigate(url)
  begin
    result = mcp__playwright__playwright_navigate(
      url: url,
      timeout: @config['timeout'],
      waitUntil: 'networkidle'
    )
    puts "→ Navigate to #{url} ✅"
    result
  rescue => e
    puts "→ Navigate failed: #{e.message} ❌"
    raise e
  end
end
```

### Form Interaction Flow
```ruby
# BEFORE (Simulation)
def simulate_fill(selector, value)
  puts "→ Fill '#{selector}' with '#{value}'"
  true
end

def simulate_click(selector)
  puts "→ Click '#{selector}'"
  true
end

# AFTER (Real MCP)
def fill_field(selector, value)
  mcp__playwright__playwright_fill(
    selector: selector,
    value: resolve_value(value)
  )
  puts "→ Fill '#{selector}' with '#{value}' ✅"
end

def click_element(selector)  
  mcp__playwright__playwright_click(selector: selector)
  puts "→ Click '#{selector}' ✅"
end
```

### Verification and Screenshots
```ruby
# BEFORE (Simulation)
def simulate_verify(selector)
  puts "→ Verify '#{selector}' exists"
  true
end

def simulate_screenshot(name)
  puts "→ Screenshot: #{name}"
  true  
end

# AFTER (Real MCP)
def verify_element(selector)
  # Use accessibility tree to verify element exists and is visible
  visible_html = mcp__playwright__playwright_get_visible_html(
    selector: selector,
    maxLength: 1000
  )
  
  exists = visible_html.include?(selector.gsub(/[\[\]"]/, ''))
  puts "→ Verify '#{selector}' exists: #{exists ? '✅' : '❌'}"
  exists
end

def capture_screenshot(name)
  mcp__playwright__playwright_screenshot(
    name: "#{name}-#{Time.current.strftime('%Y%m%d_%H%M%S')}",
    savePng: true,
    fullPage: false
  )
  puts "→ Screenshot: #{name} ✅"
end
```

## 🎯 Golden Flow Specific Patterns

### App Generation Flow
```ruby
def execute_app_generation_flow(flow_config)
  # 1. Navigate to new app page
  navigate(resolve_url('/apps/new'))
  
  # 2. Fill app creation form
  fill_field('[data-testid="app-name"]', 'Test Todo App')  
  fill_field('[data-testid="app-prompt"]', 'Create a simple todo app with add, edit, delete functionality')
  
  # 3. Start generation
  click_element('[data-testid="generate-button"]')
  
  # 4. Wait for progress (with real timeout handling)
  wait_for_element('[data-testid="generation-progress"]', timeout: 30000)
  wait_for_element('[data-testid="generation-complete"]', timeout: 120000)
  
  # 5. Verify results
  verify_element('[data-testid="app-files-list"]')
  verify_content_contains('[data-testid="app-files-list"]', 'index.html')
  
  # 6. Capture success state
  capture_screenshot('app-generation-complete')
end
```

### Publishing Flow with URL Extraction
```ruby  
def execute_publishing_flow(app_id)
  # 1. Navigate to app page
  navigate(resolve_url("/apps/#{app_id}"))
  
  # 2. Initiate publishing
  click_element('[data-testid="publish-button"]')
  wait_for_element('[data-testid="deployment-progress"]')
  
  # 3. Wait for deployment completion
  wait_for_element('[data-testid="production-url"]', timeout: 180000)
  
  # 4. Extract production URL dynamically
  production_url = extract_text_content('[data-testid="production-url"]')
  
  # 5. Verify deployment in new tab
  mcp__playwright__playwright_click_and_switch_tab(
    selector: '[data-testid="production-url"] a'
  )
  
  # 6. Verify app loads successfully
  wait_for_page_load(timeout: 60000)
  verify_no_console_errors()
  capture_screenshot('published-app-live')
  
  production_url
end
```

## 🛠️ Error Handling Patterns

### Robust Wait Strategies
```ruby
def wait_for_element(selector, timeout: 30000)
  start_time = Time.current
  
  loop do
    # Check if element exists using accessibility tree
    html = mcp__playwright__playwright_get_visible_html(
      selector: selector,
      maxLength: 500
    )
    
    return true if html.present?
    
    elapsed = (Time.current - start_time) * 1000
    if elapsed > timeout
      raise "Timeout waiting for #{selector} after #{elapsed}ms"
    end
    
    sleep 0.5
  end
end

def verify_no_console_errors
  logs = mcp__playwright__playwright_console_logs(
    type: 'error',
    limit: 10
  )
  
  if logs.present?
    puts "⚠️ Console errors detected:"
    logs.each { |log| puts "  - #{log}" }
    return false
  end
  
  true
end
```

### Graceful Degradation
```ruby
def execute_with_fallback(action_name, &block)
  retries = 0
  max_retries = 2
  
  begin
    block.call
  rescue => e
    retries += 1
    
    if retries <= max_retries
      puts "⚠️ #{action_name} failed (attempt #{retries}): #{e.message}"
      puts "🔄 Retrying in 2 seconds..."
      sleep 2
      retry
    else
      puts "❌ #{action_name} failed after #{max_retries} retries: #{e.message}"
      raise e
    end
  end
end
```

## 🎨 Data-TestID Integration

### Automatic Element Discovery
```ruby
def discover_test_elements(page_name)
  # Get all elements with data-testid attributes
  html = mcp__playwright__playwright_get_visible_html(maxLength: 20000)
  
  test_ids = html.scan(/data-testid="([^"]+)"/).flatten
  
  puts "📋 Available test elements on #{page_name}:"
  test_ids.each { |id| puts "  - [data-testid=\"#{id}\"]" }
  
  test_ids
end

def suggest_missing_test_ids(flow_config)
  required_selectors = flow_config['test_steps']
    .select { |step| step['selector'] }
    .map { |step| step['selector'] }
  
  available_ids = discover_test_elements("current page")
  
  missing = required_selectors.reject do |selector|
    available_ids.any? { |id| selector.include?(id) }
  end
  
  if missing.any?
    puts "⚠️ Missing data-testid attributes:"
    missing.each { |selector| puts "  - #{selector}" }
  end
end
```

## 🚀 Performance Monitoring

### Timing Integration
```ruby
def measure_flow_performance(flow_name)
  start_time = Time.current
  
  result = yield
  
  duration = Time.current - start_time
  
  # Log performance metrics
  puts "⏱️ #{flow_name}: #{duration.round(2)}s"
  
  # Check against baselines  
  baseline = get_baseline_for_flow(flow_name)
  if baseline && duration > baseline * 1.5
    puts "⚠️ Performance regression detected! Expected: #{baseline}s, Actual: #{duration}s"
  end
  
  { result: result, duration: duration }
end

def get_baseline_for_flow(flow_name)
  baselines = {
    'end_to_end_app_generation' => 2.0,
    'basic_auth_flow' => 1.0,
    'end_to_end_publishing' => 180.0
  }
  
  baselines[flow_name]
end
```

## 🎯 Integration with Existing Framework

### Service Method Updates
```ruby
# Update the main service to use real MCP when available
class Testing::PlaywrightMcpService
  def initialize(environment = Rails.env)
    @environment = environment
    @config = load_config
    @results = []
    @mcp_available = check_mcp_availability
  end

  private

  def check_mcp_availability
    # Test if MCP functions are available
    begin
      mcp__playwright__playwright_get_visible_text
      true
    rescue NoMethodError
      puts "🎭 Playwright MCP not available - using simulation mode"
      false
    end
  end

  def execute_action(step)
    if @mcp_available
      execute_real_action(step)
    else
      execute_simulated_action(step)
    end
  end
end
```

This pattern allows seamless transition from simulation to real browser testing while maintaining the same interface and reporting capabilities.

---

*Ready for Claude Code to enable real browser automation for golden flow protection! 🎭*