# Rails Testing Pipeline for OverSkill

Implementing Rails 8 and Bullet Train standard testing practices with golden flow integration.

## 🛤️ Rails 8 Testing Standards

### Built-in Authentication Testing
Rails 8 includes built-in authentication - OverSkill uses Bullet Train which extends this:

```ruby
# test/test_helper.rb - Standard Rails 8 setup
ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

class ActiveSupport::TestCase
  # Run tests in parallel with specified workers  
  parallelize(workers: :number_of_processors)

  # Setup all fixtures in test/fixtures/*.yml
  fixtures :all

  # Bullet Train authentication helpers
  include Devise::Test::IntegrationHelpers
end
```

### Query Log Tags (Rails 8)
Rails 8 includes enhanced query logging for performance tracking:

```ruby
# config/application.rb - Enable query log tags
config.active_record.query_log_tags_enabled = true
config.active_record.query_log_tags = [
  :namespaced_controller,
  :action, 
  :job,
  {
    request_id: ->(context) { context[:request_id] },
    user_id: ->(context) { context[:current_user]&.id }
  }
]
```

## 🎯 Golden Flow Integration

### System Testing with Real Browser
Integrating golden flows with Rails system testing:

```ruby
# test/system/golden_flows_test.rb
require "application_system_test_case"

class GoldenFlowsTest < ApplicationSystemTestCase
  driven_by :selenium, using: :chrome, screen_size: [1400, 1400]

  test "end to end app generation golden flow" do
    # Authenticate user
    user = users(:one)
    sign_in user
    
    # Execute golden flow
    visit new_app_path
    
    fill_in "app_name", with: "Test Todo App"
    fill_in "app_prompt", with: "Create a simple todo app"
    
    click_button "Generate"
    
    # Wait for generation with realistic timeout
    assert_selector '[data-testid="generation-complete"]', wait: 120
    
    # Verify files created
    assert_selector '[data-testid="app-files-list"]'
    assert_text "index.html"
    assert_text ".js"
    assert_text ".css"
    
    # Verify no console errors
    assert_no_selector ".alert-danger"
  end

  test "end to end publishing golden flow" do
    # Setup generated app
    user = users(:one)  
    app = apps(:generated_app)
    sign_in user
    
    visit app_path(app)
    
    click_button "Publish to Production"
    
    # Wait for deployment
    assert_selector '[data-testid="production-url"]', wait: 180
    
    # Get production URL and verify
    production_url = find('[data-testid="production-url"]').text
    assert_not_empty production_url
    
    # Test in new window (basic verification)
    visit production_url
    assert_no_selector ".error"
  end
  
  test "basic authentication golden flow" do
    visit new_user_registration_path
    
    fill_in "Email", with: "test@example.com"
    fill_in "Password", with: "password123"
    fill_in "Password confirmation", with: "password123" 
    
    click_button "Sign up"
    
    # Verify dashboard access
    assert_selector '[data-testid="dashboard"]'
    assert_selector '[data-testid="apps-section"]'
    
    # Verify can create apps
    assert_link "New App"
  end
end
```

### Application System Test Case Enhancement
```ruby
# test/application_system_test_case.rb
require "test_helper"
require "capybara/rails"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :chrome, screen_size: [1400, 1400] do |driver_options|
    driver_options.add_argument("--headless") if ENV["HEADLESS"]
    driver_options.add_argument("--no-sandbox")
    driver_options.add_argument("--disable-dev-shm-usage")
  end

  # Golden flow specific helpers
  def wait_for_generation_complete(timeout: 120)
    assert_selector '[data-testid="generation-complete"]', wait: timeout
  end

  def wait_for_deployment_complete(timeout: 180)
    assert_selector '[data-testid="production-url"]', wait: timeout
  end

  def verify_no_js_errors
    # Check for JavaScript errors in console
    logs = page.driver.browser.logs.get(:browser)
    errors = logs.select { |log| log.level == 'SEVERE' }
    
    if errors.any?
      puts "JavaScript errors found:"
      errors.each { |error| puts "  - #{error.message}" }
    end
    
    assert_empty errors, "JavaScript errors found in console"
  end

  def create_test_user(email: "test@example.com")
    User.create!(
      email: email,
      password: "password123",
      password_confirmation: "password123",
      first_name: "Test",
      last_name: "User"
    )
  end
end
```

## 🔧 Model and Unit Testing

### Bullet Train Model Testing Patterns
```ruby
# test/models/app_test.rb
require "test_helper"

class AppTest < ActiveSupport::TestCase
  test "should create app with valid attributes" do
    user = users(:one)
    team = user.teams.first
    membership = user.memberships.first
    
    app = App.new(
      name: "Test App",
      prompt: "Create a test app", 
      team: team,
      creator: membership
    )
    
    assert app.valid?
    assert app.save
  end

  test "should require name and prompt" do
    app = App.new
    assert_not app.valid?
    assert_includes app.errors[:name], "can't be blank"
    assert_includes app.errors[:prompt], "can't be blank"
  end

  test "should track app generation lifecycle" do
    app = apps(:one)
    
    # Test status transitions
    assert_equal "pending", app.status
    
    app.update!(status: "generating")
    assert_equal "generating", app.status
    
    app.update!(status: "generated")
    assert_equal "generated", app.status
    
    # Verify files can be attached after generation
    app.app_files.create!(
      path: "index.html",
      content: "<h1>Test</h1>",
      team: app.team
    )
    
    assert_equal 1, app.app_files.count
  end
end

# test/models/app_file_test.rb  
class AppFileTest < ActiveSupport::TestCase
  test "should belong to app and team" do
    app = apps(:one)
    
    file = AppFile.new(
      path: "src/App.tsx",
      content: "console.log('test');",
      app: app,
      team: app.team
    )
    
    assert file.valid?
    assert_equal app, file.app
    assert_equal app.team, file.team
  end

  test "should validate file path format" do
    app = apps(:one)
    
    # Valid paths
    valid_paths = %w[
      index.html
      src/App.tsx  
      styles/main.css
      public/favicon.ico
      .env
    ]
    
    valid_paths.each do |path|
      file = AppFile.new(path: path, content: "test", app: app, team: app.team)
      assert file.valid?, "#{path} should be valid"
    end
  end
end
```

### Service Testing  
```ruby
# test/services/testing/playwright_mcp_service_test.rb
require "test_helper"

class Testing::PlaywrightMcpServiceTest < ActiveSupport::TestCase
  test "should load configuration successfully" do
    service = Testing::PlaywrightMcpService.new('test')
    
    assert_not_nil service.instance_variable_get(:@config)
    assert_equal 'http://localhost:3000', service.instance_variable_get(:@config)['base_url']
  end

  test "should create test user and app properly" do
    service = Testing::PlaywrightMcpService.new('test')
    
    # Test user creation
    user = service.send(:get_or_create_test_user)
    assert_not_nil user
    assert_equal "playwright-test@overskill.app", user.email
    assert user.teams.any?
    
    # Test app creation  
    app = service.send(:get_or_create_test_app)
    assert_not_nil app
    assert_equal "Test Generated App", app.name
    assert_equal "generated", app.status
    assert app.app_files.any?
  end

  test "should run golden flow simulation" do
    service = Testing::PlaywrightMcpService.new('test')
    
    # Mock the individual flow execution
    service.stub(:run_single_flow, {success: true, duration: 1.0}) do
      results = service.run_golden_flow_tests
    end
    
    assert service.instance_variable_get(:@results).any?
  end
end
```

## 🚀 CI/CD Integration

### GitHub Actions Workflow
```yaml
# .github/workflows/test.yml
name: Test Suite

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 5432:5432
      
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
        ports:
          - 6379:6379

    steps:
    - uses: actions/checkout@v4
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        bundler-cache: true
    
    - name: Set up Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
    
    - name: Install dependencies
      run: |
        bundle install
        npm install
        
    - name: Setup test database
      env:
        RAILS_ENV: test
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/overskill_test
        REDIS_URL: redis://localhost:6379/1
      run: |
        bundle exec rails db:create db:schema:load
        
    - name: Run tests
      env:
        RAILS_ENV: test
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/overskill_test
        REDIS_URL: redis://localhost:6379/1
      run: |
        bundle exec rails test
        
    - name: Run system tests
      env:
        RAILS_ENV: test
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/overskill_test
        REDIS_URL: redis://localhost:6379/1
        HEADLESS: true
      run: |
        bundle exec rails test:system
        
    - name: Run golden flow baseline tests
      env:
        RAILS_ENV: test  
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/overskill_test
        REDIS_URL: redis://localhost:6379/1
      run: |
        bundle exec rails runner "Testing::GoldenFlowBaselineService.new.measure_all_flows"
        
    - name: Run golden flow playwright tests (simulation)
      env:
        RAILS_ENV: test
        DATABASE_URL: postgres://postgres:postgres@localhost:5432/overskill_test  
        REDIS_URL: redis://localhost:6379/1
      run: |
        bundle exec rails runner "Testing::PlaywrightMcpService.new('test').run_golden_flow_tests"
        
    - name: Upload test artifacts
      uses: actions/upload-artifact@v4
      if: failure()
      with:
        name: test-screenshots
        path: tmp/screenshots/
```

### Test Configuration
```ruby
# config/environments/test.rb enhancements
Rails.application.configure do
  # Standard Rails 8 test config
  config.cache_classes = true
  config.eager_load = false
  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => 'public, max-age=3600'
  }
  
  # Golden flow specific settings
  config.action_controller.perform_caching = false
  config.action_dispatch.show_exceptions = false
  config.action_controller.allow_forgery_protection = false
  
  # Bullet Train test settings
  config.active_storage.service = :test
  config.action_mailer.perform_caching = false
  config.action_mailer.delivery_method = :test
  
  # Performance testing
  config.active_record.query_log_tags_enabled = true
  
  # Golden flow timeout settings
  config.x.golden_flow_timeouts = {
    app_generation: 120, # 2 minutes
    app_publishing: 180, # 3 minutes
    user_auth: 30        # 30 seconds
  }
end
```

## 📊 Performance Testing Integration

### Benchmark Helpers
```ruby
# test/support/performance_helpers.rb
module PerformanceHelpers
  def measure_performance(operation_name)
    start_time = Time.current
    result = yield
    duration = Time.current - start_time
    
    Rails.logger.info "Performance: #{operation_name} took #{duration.round(3)}s"
    
    # Log to performance baseline if in CI
    if ENV['CI']
      log_performance_metric(operation_name, duration)
    end
    
    result
  end
  
  def log_performance_metric(operation, duration)
    File.open("tmp/performance_metrics.log", "a") do |f|
      f.puts "#{Time.current.iso8601},#{operation},#{duration}"
    end
  end
  
  def assert_performance_within(expected_duration, tolerance: 0.5)
    actual_duration = yield
    max_allowed = expected_duration * (1 + tolerance)
    
    assert actual_duration <= max_allowed, 
      "Performance regression: expected <= #{expected_duration}s (±#{tolerance*100}%), got #{actual_duration}s"
  end
end
```

### Integration with Existing Baselines
```ruby
# test/system/performance_test.rb
class PerformanceTest < ApplicationSystemTestCase
  include PerformanceHelpers
  
  test "app generation performance baseline" do
    user = create_test_user
    sign_in user
    
    visit new_app_path
    
    duration = measure_performance("app_generation_ui_flow") do
      fill_in "app_name", with: "Performance Test App"
      fill_in "app_prompt", with: "Create a simple test app"
      click_button "Generate"
      
      wait_for_generation_complete
    end
    
    # Allow 50% variance from 2-second baseline
    assert_performance_within(2.0, tolerance: 0.5) { duration }
  end
  
  test "dashboard load performance" do
    user = create_test_user
    
    duration = measure_performance("dashboard_load") do
      sign_in user
      visit dashboard_path
      assert_selector '[data-testid="dashboard"]'
    end
    
    # Dashboard should load quickly
    assert_performance_within(1.0) { duration }
  end
end
```

## 🎭 Golden Flow Test Suite

### Comprehensive Flow Testing
```ruby
# test/system/comprehensive_golden_flows_test.rb
class ComprehensiveGoldenFlowsTest < ApplicationSystemTestCase
  
  # Run the actual golden flow definitions from YAML
  test "execute all golden flows from configuration" do
    config = YAML.load_file(Rails.root.join('config', 'playwright_golden_flows.yml'))['test']
    
    config['golden_flows'].each do |flow_key, flow_config|
      puts "Testing golden flow: #{flow_config['name']}"
      
      execute_golden_flow(flow_key, flow_config)
    end
  end
  
  private
  
  def execute_golden_flow(flow_key, flow_config)
    # Setup based on prerequisites
    setup_flow_prerequisites(flow_config)
    
    # Execute each test step
    flow_config['test_steps'].each do |step|
      execute_flow_step(step)
    end
    
    # Verify success criteria
    verify_success_criteria(flow_config['success_criteria'])
  end
  
  def execute_flow_step(step)
    case step['action']
    when 'navigate'
      visit step['url']
    when 'fill'
      fill_in step['selector'].gsub(/[\[\]"]/, ''), with: step['value']
    when 'click'
      click_button step['selector'].gsub(/[\[\]"]/, '')
    when 'wait_for'
      assert_selector step['selector'], wait: (step['timeout'] || 30000) / 1000
    when 'verify'
      assert_selector step['selector']
    when 'screenshot'
      save_screenshot("#{step['name']}.png")
    end
  end
  
  def setup_flow_prerequisites(flow_config)
    if flow_config['prerequisites']&.any? { |p| p['requires_generated_app'] }
      # Create test app for publishing flow
      @test_user = create_test_user
      @test_app = create_test_generated_app(@test_user)
    end
  end
  
  def create_test_generated_app(user)
    team = user.teams.first
    membership = user.memberships.first
    
    App.create!(
      name: "Test Generated App",
      prompt: "Test app for golden flow testing",
      status: "generated", 
      team: team,
      creator: membership
    ).tap do |app|
      # Create test files
      app.app_files.create!([
        { path: "index.html", content: "<h1>Test App</h1>", team: team },
        { path: "app.js", content: "console.log('test');", team: team },
        { path: "style.css", content: "body { margin: 0; }", team: team }
      ])
    end
  end
end
```

## 🛠️ Test Data and Fixtures

### Rails 8 Fixture Enhancements
```yaml
# test/fixtures/users.yml
one:
  email: test1@example.com
  first_name: Test
  last_name: User
  time_zone: UTC
  encrypted_password: <%= Devise::Encryptor.digest(User, 'password123') %>

two:
  email: test2@example.com  
  first_name: Another
  last_name: User
  time_zone: UTC
  encrypted_password: <%= Devise::Encryptor.digest(User, 'password123') %>

# test/fixtures/teams.yml
one:
  name: Test Team One
  time_zone: UTC

two:
  name: Test Team Two
  time_zone: UTC

# test/fixtures/memberships.yml  
one:
  user: one
  team: one
  
two:
  user: two
  team: two

# test/fixtures/apps.yml
generated_app:
  name: Generated Test App
  prompt: Create a test app with basic functionality
  status: generated
  team: one
  creator: one

pending_app:
  name: Pending Test App  
  prompt: Create another test app
  status: pending
  team: one
  creator: one
```

This comprehensive Rails testing pipeline integrates golden flows with standard Rails 8 and Bullet Train practices, ensuring robust CI/CD while protecting critical user workflows.

---

*Rails 8 + Bullet Train + Golden Flows = Comprehensive Testing Excellence! 🛤️*