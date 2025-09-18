require "application_system_test_case"

class GoldenFlowsTest < ApplicationSystemTestCase
  # Golden Flow system tests implementing Rails 8 + Bullet Train standards
  # Integration with OverSkill's Playwright MCP framework

  test "end to end app generation golden flow" do
    # Setup authenticated user
    user = users(:one)
    sign_in user

    # Navigate to app creation
    visit new_app_path

    # Fill app creation form using data-testid selectors
    fill_in find('[data-testid="app-name"]'), with: "Test Todo App"
    fill_in find('[data-testid="app-prompt"]'), with: "Create a simple todo app with add, edit, delete functionality"

    # Start generation process
    click_button find('[data-testid="generate-button"]')

    # Wait for generation progress with realistic timeout
    assert_selector '[data-testid="generation-progress"]', wait: 30

    # Wait for generation completion (AI generation can take time)
    assert_selector '[data-testid="generation-complete"]', wait: 120

    # Verify generated files are visible to user
    assert_selector '[data-testid="app-files-list"]'

    within('[data-testid="app-files-list"]') do
      assert_text "index.html"
      assert_text ".js"
      assert_text ".css"
    end

    # Verify no error alerts shown to user
    assert_no_selector ".alert-danger"
    assert_no_selector ".error"

    # Verify JavaScript console has no severe errors
    verify_no_js_errors

    # Capture screenshot for golden flow documentation
    save_screenshot("golden_flow_app_generation_complete.png")
  end

  test "end to end publishing golden flow" do
    # Setup user with generated app
    user = users(:one)
    app = apps(:generated_app)
    sign_in user

    # Navigate to app page
    visit app_path(app)

    # Initiate publishing
    click_button find('[data-testid="publish-button"]')

    # Wait for deployment progress indicator
    assert_selector '[data-testid="deployment-progress"]', wait: 30

    # Wait for deployment completion (can take several minutes)
    assert_selector '[data-testid="production-url"]', wait: 180

    # Extract and verify production URL
    production_url_element = find('[data-testid="production-url"]')
    production_url = production_url_element.text

    assert_not_empty production_url
    assert production_url.include?("overskill.app"), "Production URL should use overskill.app domain"

    # Basic accessibility check - production URL should be clickable
    assert_selector '[data-testid="production-url"] a', text: production_url

    # Verify no deployment errors
    assert_no_selector ".deployment-error"
    assert_no_selector ".alert-danger"

    # Capture publishing success state
    save_screenshot("golden_flow_publishing_complete.png")
  end

  test "basic authentication golden flow" do
    # Test new user signup flow
    visit new_user_registration_path

    # Generate unique email to avoid conflicts
    test_email = "test-#{Time.current.to_i}@example.com"

    # Fill registration form
    fill_in find('[data-testid="email-field"]'), with: test_email
    fill_in find('[data-testid="password-field"]'), with: "password123"
    fill_in find('[data-testid="password-confirmation-field"]'), with: "password123"

    # Complete signup
    click_button find('[data-testid="sign-up-button"]')

    # Verify successful authentication and dashboard access
    assert_selector '[data-testid="dashboard"]', wait: 30
    assert_selector '[data-testid="apps-section"]'

    # Verify user can access app creation (core functionality)
    assert_link "New App"

    # Verify user info is displayed correctly
    assert_text test_email

    # Verify no authentication errors
    assert_no_selector ".authentication-error"
    assert_no_selector ".alert-danger"

    # Capture authenticated dashboard state
    save_screenshot("golden_flow_authentication_complete.png")
  end

  private

  def verify_no_js_errors
    # Check browser console for JavaScript errors
    # This helps catch client-side issues that might break user workflows
    return unless page.driver.respond_to?(:browser)

    begin
      logs = page.driver.browser.logs.get(:browser)
      severe_errors = logs.select { |log| log.level == "SEVERE" }

      if severe_errors.any?
        puts "⚠️ JavaScript errors detected in golden flow:"
        severe_errors.each { |error| puts "  - #{error.message}" }
      end

      assert_empty severe_errors, "JavaScript errors detected in golden flow execution"
    rescue => e
      puts "Note: Could not check JavaScript console logs: #{e.message}"
    end
  end
end
