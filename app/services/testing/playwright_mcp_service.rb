# app/services/testing/playwright_mcp_service.rb
class Testing::PlaywrightMcpService
  def initialize(environment = Rails.env)
    @environment = environment
    @config = load_config
    @results = []
  end

  def run_golden_flow_tests
    puts "\n🎭 Running Golden Flow Tests with Playwright MCP"
    puts "Environment: #{@environment}"
    puts "Base URL: #{@config["base_url"]}"

    @config["golden_flows"].each do |flow_key, flow_config|
      puts "\n🎯 Testing: #{flow_config["name"]}"
      result = run_single_flow(flow_key, flow_config)
      @results << result
    end

    generate_test_report
    display_summary
  end

  def run_single_flow(flow_key, flow_config)
    start_time = Time.current

    begin
      # This would integrate with Playwright MCP when available
      # For now, we'll simulate the test structure

      puts "   📋 #{flow_config["description"]}"

      # Check prerequisites
      prerequisites = flow_config["prerequisites"]
      if prerequisites.is_a?(Array) && prerequisites.any? { |p| p["requires_generated_app"] }
        unless generated_app_available?
          return {
            flow: flow_key,
            success: false,
            error: "No generated app available for publishing test",
            duration: 0
          }
        end
      end

      # Variable storage for dynamic values
      variables = {}

      # Simulate running test steps
      flow_config["test_steps"].each_with_index do |step, index|
        puts "      #{index + 1}. #{step["description"]}"

        # This is where we would call Playwright MCP commands:
        case step["action"]
        when "navigate"
          simulate_navigate(resolve_url(step["url"], variables))
        when "fill"
          simulate_fill(step["selector"], resolve_value(step["value"]))
        when "click"
          simulate_click(step["selector"])
        when "wait_for"
          simulate_wait_for(step["selector"], step["timeout"] || @config["timeout"])
        when "verify"
          simulate_verify(step["selector"])
        when "screenshot"
          simulate_screenshot(step["name"])
        when "extract_text"
          variables[step["variable"]] = simulate_extract_text(step["selector"], step["variable"])
        when "navigate_new_tab"
          simulate_navigate_new_tab(resolve_url(step["url"], variables))
        else
          puts "        ⚠️ Unknown action: #{step["action"]}"
        end

        # Small delay to simulate real browser interaction
        sleep 0.1
      rescue => step_error
        puts "        ❌ Error in step #{index + 1}: #{step_error.message}"
        puts "        Step data: #{step.inspect}"
        raise step_error
      end

      # Check success criteria
      success = validate_success_criteria(flow_config["success_criteria"])
      duration = Time.current - start_time

      if success
        puts "      ✅ Flow completed successfully (#{duration.round(2)}s)"
      else
        puts "      ❌ Flow failed validation"
      end

      {
        flow: flow_key,
        name: flow_config["name"],
        success: success,
        duration: duration,
        steps_completed: flow_config["test_steps"].size,
        error: success ? nil : "Success criteria not met"
      }
    rescue => e
      puts "      ❌ Error running flow: #{e.message}"
      {
        flow: flow_key,
        success: false,
        error: e.message,
        duration: Time.current - start_time
      }
    end
  end

  # These methods would be replaced with actual Playwright MCP calls

  def simulate_navigate(url)
    puts "        → Navigate to #{url}"
    # In real implementation:
    # mcp__playwright__playwright_navigate(url: resolve_url(url))
    true
  end

  def simulate_fill(selector, value)
    puts "        → Fill '#{selector}' with '#{value}'"
    # In real implementation:
    # mcp__playwright__playwright_fill(selector: selector, value: resolve_value(value))
    true
  end

  def simulate_click(selector)
    puts "        → Click '#{selector}'"
    # In real implementation:
    # mcp__playwright__playwright_click(selector: selector)
    true
  end

  def simulate_wait_for(selector, timeout)
    puts "        → Wait for '#{selector}' (timeout: #{timeout}ms)"
    # In real implementation:
    # Wait for element to appear with timeout
    # This would use Playwright MCP's waiting capabilities
    true
  end

  def simulate_verify(selector)
    puts "        → Verify '#{selector}' exists"
    # In real implementation:
    # Check if element exists and is visible using accessibility tree
    true
  end

  def simulate_screenshot(name)
    puts "        → Screenshot: #{name}"
    # In real implementation:
    # mcp__playwright__playwright_screenshot(name: name, savePng: true)
    true
  end

  def simulate_navigate_new_tab(url)
    puts "        → Open new tab: #{url}"
    # In real implementation:
    # Handle new tab navigation and verification
    true
  end

  def simulate_extract_text(selector, variable)
    # Simulate extracting text from an element
    simulated_value = case variable
    when "production_url"
      # Simulate a production URL for publishing flow
      "https://app-#{rand(1000..9999)}.overskill.app"
    else
      "simulated-#{variable}-value"
    end

    puts "        → Extract '#{variable}' from '#{selector}': #{simulated_value}"
    simulated_value
  end

  def validate_success_criteria(criteria)
    return true unless criteria

    # In real implementation, this would check actual browser state
    # For now, simulate success based on flow type
    puts "        ✓ Validating success criteria..."

    criteria.each do |criterion|
      if criterion.is_a?(Hash)
        # Handle hash format like { element_contains: { selector: "...", text: "..." } }
        criterion.each do |key, value|
          case key
          when "element_exists"
            puts "          - Element exists: #{value}"
          when "element_contains"
            if value.is_a?(Hash)
              puts "          - Element contains: #{value["selector"]} → '#{value["text"]}'"
            else
              puts "          - Element contains: #{value}"
            end
          when "no_errors_in_console"
            puts "          - No console errors: #{value}"
          when "production_url_accessible"
            puts "          - Production URL accessible: #{value}"
          when "app_loads_successfully"
            puts "          - App loads successfully: #{value}"
          when "user_authenticated"
            puts "          - User authenticated: #{value}"
          when "can_create_apps"
            puts "          - Can create apps: #{value}"
          when "no_deployment_errors"
            puts "          - No deployment errors: #{value}"
          when "page_loads"
            puts "          - Page loads: #{value}"
          when "form_elements_present"
            puts "          - Form elements present: #{value}"
          end
        end
      elsif criterion.is_a?(String)
        # Handle simple string criteria
        puts "          - #{criterion}"
      else
        puts "          - Unknown criterion: #{criterion.inspect}"
      end
    end

    true # Simulate success for now
  end

  def generated_app_available?
    # Check if there's a generated app available for testing
    App.where(status: "generated").exists?
  end

  def resolve_url(url, variables = {})
    resolved_url = url

    # Replace variable placeholders like {app_id} or {production_url}
    variables.each do |var_name, var_value|
      resolved_url = resolved_url.gsub("{#{var_name}}", var_value.to_s)
    end

    # Replace {app_id} with a test app if available
    if resolved_url.include?("{app_id}")
      test_app_id = get_or_create_test_app&.id || 1
      resolved_url = resolved_url.gsub("{app_id}", test_app_id.to_s)
    end

    # Make relative URLs absolute
    if resolved_url.start_with?("/")
      @config["base_url"] + resolved_url
    else
      resolved_url
    end
  end

  def resolve_value(value)
    return value unless value.is_a?(String)

    # Replace placeholders like {timestamp}
    resolved = value.gsub("{timestamp}", Time.current.to_i.to_s)

    # Handle test email generation
    if resolved.include?("test-") && resolved.include?("@example.com")
      resolved = "test-#{Time.current.to_i}@example.com"
    end

    resolved
  end

  def get_or_create_test_app
    # Find or create a test app for publishing flow tests
    test_user = get_or_create_test_user
    test_app = App.find_by(name: "Test Generated App")

    unless test_app
      # Ensure user has a membership and team
      membership = test_user.memberships.first
      unless membership
        team = Team.create!(name: "Test Team #{Time.current.to_i}")
        membership = Membership.create!(user: test_user, team: team)
      end

      # Create a minimal test app if none exists
      test_app = App.create!(
        name: "Test Generated App",
        prompt: "Test app for golden flow testing",
        status: "generated",
        team: membership.team,
        creator: membership # Bullet Train apps need a creator membership
      )

      # Create some basic files to simulate a generated app
      test_app.app_files.create!([
        {path: "index.html", content: "<h1>Test App</h1>"},
        {path: "app.js", content: "console.log('test');"},
        {path: "style.css", content: "body { margin: 0; }"}
      ])
    end

    test_app
  end

  def get_or_create_test_user
    # Create a test user for authenticated flows
    test_email = "playwright-test@overskill.app"

    user = User.find_by(email: test_email)
    unless user
      user = User.create!(
        email: test_email,
        password: "testpassword123",
        first_name: "Playwright",
        last_name: "Test",
        time_zone: "UTC"
      )

      # Create a team for the user (Bullet Train requirement)
      team = Team.create!(name: "Playwright Test Team")
      membership = Membership.create!(user: user, team: team)

      # Set admin role if role system exists
      if defined?(Role) && Role.table_exists?
        admin_role = Role.find_by(key: "admin") || Role.find_by(name: "Admin")
        membership.update!(role_ids: [admin_role.id]) if admin_role
      end
    end

    user
  end

  def load_config
    config_path = Rails.root.join("config", "playwright_golden_flows.yml")
    unless File.exist?(config_path)
      raise "Playwright golden flows config not found at #{config_path}"
    end

    YAML.load_file(config_path)[@environment]
  end

  def generate_test_report
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    report_path = "playwright_mcp_test_report_#{timestamp}.md"

    File.open(report_path, "w") do |f|
      f.puts generate_markdown_report
    end

    puts "\n📊 Test report saved to: #{report_path}"
  end

  def generate_markdown_report
    report = []
    report << "# Playwright MCP Golden Flow Test Report"
    report << "*Generated: #{Time.current.strftime("%B %d, %Y at %I:%M %p")}*"
    report << ""
    report << "## Test Environment"
    report << "- **Environment**: #{@environment}"
    report << "- **Base URL**: #{@config["base_url"]}"
    report << "- **Browser**: #{@config["browser"]}"
    report << "- **Headless**: #{@config["headless"]}"
    report << ""

    # Summary
    total_tests = @results.size
    passed_tests = @results.count { |r| r[:success] }
    failed_tests = total_tests - passed_tests

    report << "## Summary"
    report << "- **Total Tests**: #{total_tests}"
    report << "- **Passed**: #{passed_tests} ✅"
    report << "- **Failed**: #{failed_tests} ❌"
    report << "- **Success Rate**: #{((passed_tests.to_f / total_tests) * 100).round(1)}%"
    report << ""

    # Individual test results
    report << "## Test Results"
    report << ""

    @results.each do |result|
      status_emoji = result[:success] ? "✅" : "❌"
      report << "### #{status_emoji} #{result[:name] || result[:flow]}"
      report << "- **Duration**: #{result[:duration].round(2)}s"

      if result[:steps_completed]
        report << "- **Steps Completed**: #{result[:steps_completed]}"
      end

      if result[:error]
        report << "- **Error**: #{result[:error]}"
      end

      report << ""
    end

    # Instructions for enabling real Playwright MCP
    report << "## 🚀 Enabling Real Browser Testing"
    report << ""
    report << "This report shows simulated test results. To enable real browser testing:"
    report << ""
    report << "1. **Ensure Playwright MCP is available** in your Claude Code environment"
    report << "2. **Replace simulation methods** in PlaywrightMcpService with actual MCP calls:"
    report << "   ```ruby"
    report << "   def navigate(url)"
    report << "     mcp__playwright__playwright_navigate(url: url)"
    report << "   end"
    report << ""
    report << "   def fill_field(selector, value)"
    report << "     mcp__playwright__playwright_fill(selector: selector, value: value)"
    report << "   end"
    report << ""
    report << "   def click_element(selector)"
    report << "     mcp__playwright__playwright_click(selector: selector)"
    report << "   end"
    report << "   ```"
    report << "3. **Add data-testid attributes** to your HTML elements for reliable selection"
    report << "4. **Run tests with**: `Testing::PlaywrightMcpService.new.run_golden_flow_tests`"
    report << ""

    report.join("\n")
  end

  def display_summary
    puts "\n" + "=" * 60
    puts "🎭 PLAYWRIGHT MCP TEST SUMMARY"
    puts "=" * 60

    total_tests = @results.size
    passed_tests = @results.count { |r| r[:success] }
    failed_tests = total_tests - passed_tests

    puts "Total Tests: #{total_tests}"
    puts "Passed: #{passed_tests} ✅"
    puts "Failed: #{failed_tests} ❌"
    puts "Success Rate: #{((passed_tests.to_f / total_tests) * 100).round(1)}%"

    puts "\n🎯 FLOW RESULTS:"
    @results.each do |result|
      status = result[:success] ? "✅" : "❌"
      duration = result[:duration].round(2)
      puts "#{status} #{result[:name] || result[:flow]}: #{duration}s"
    end

    if failed_tests > 0
      puts "\n❌ FAILURES:"
      @results.select { |r| !r[:success] }.each do |result|
        puts "• #{result[:flow]}: #{result[:error]}"
      end
    end

    puts "\n💡 NEXT STEPS:"
    puts "1. Add data-testid attributes to UI elements"
    puts "2. Replace simulation with real Playwright MCP calls"
    puts "3. Test golden flows in real browser environment"
    puts "4. Set up CI/CD integration for automated testing"
    puts "=" * 60
  end
end
