#!/usr/bin/env ruby

# Simple test script to verify that the state-preserving controller works with open-by-default details

require 'minitest/autorun'
require 'capybara'
require 'capybara/dsl'
require 'selenium-webdriver'

class TestDetailsOpenByDefault < Minitest::Test
  include Capybara::DSL
  
  def setup
    Capybara.current_driver = :selenium_headless
    Capybara.app_host = 'http://localhost:3000'
    
    # Login and navigate to app editor (adjust as needed for your auth flow)
    visit '/users/sign_in'
    fill_in 'Email', with: 'test@example.com'
    fill_in 'Password', with: 'password'
    click_button 'Sign in'
  end
  
  def test_details_open_by_default
    # Navigate to an app with tool calls
    visit '/account/apps/1/editor'
    
    # Wait for page to load
    assert page.has_css?('details[data-state-preserving-target="details"]', wait: 5)
    
    # Check that details element is open by default
    details = page.find('details[data-state-preserving-target="details"]')
    assert details[:open], "Details element should be open by default"
    
    # Check that toggle text shows "Hide"
    toggle_text = page.find('[data-state-preserving-target="toggleText"]')
    assert_equal "Hide", toggle_text.text
    
    # Click to close
    toggle_text.click
    
    # Verify it's closed
    assert_nil details[:open], "Details element should be closed after clicking"
    assert_equal "Show All", toggle_text.text
    
    # Refresh page
    page.refresh
    
    # Verify state is preserved (should remain closed)
    details = page.find('details[data-state-preserving-target="details"]')
    assert_nil details[:open], "Details element should remain closed after refresh"
    assert_equal "Show All", toggle_text.text
  end
  
  def teardown
    Capybara.reset_sessions!
  end
end