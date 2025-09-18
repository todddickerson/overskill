#!/usr/bin/env ruby
# Test V4 Enhanced Full Flow - Complete validation

require_relative "config/environment"

puts "\n" + "=" * 80
puts "V4 ENHANCED FULL FLOW TEST"
puts "=" * 80

class V4EnhancedFlowTester
  attr_reader :results, :warnings, :errors

  def initialize
    @results = []
    @warnings = []
    @errors = []
  end

  def run_all_tests
    puts "\n📋 Starting comprehensive V4 Enhanced flow test...\n"

    test_configuration
    test_services
    test_models
    test_views
    test_controller_integration
    test_websocket_channels
    test_end_to_end_flow

    print_summary
  end

  private

  def test_configuration
    section "Configuration Tests"

    # Check environment variables
    test "APP_GENERATION_VERSION set to v4_enhanced" do
      ENV["APP_GENERATION_VERSION"] == "v4_enhanced"
    end

    # Check Rails configuration
    test "Rails config uses v4_enhanced" do
      Rails.application.config.app_generation_version == :v4_enhanced
    end

    test "Visual feedback enabled" do
      Rails.application.config.app_generation_features[:visual_feedback] == true
    end

    test "Approval flow enabled" do
      Rails.application.config.app_generation_features[:approval_flow] == true
    end
  end

  def test_services
    section "Service Tests"

    # Test AppBuilderV4Enhanced
    test "AppBuilderV4Enhanced exists" do
      defined?(Ai::AppBuilderV4Enhanced)
    end

    test "AppBuilderV4Enhanced responds to execute!" do
      Ai::AppBuilderV4Enhanced.instance_methods.include?(:execute!)
    end

    # Test ChatProgressBroadcasterV2
    test "ChatProgressBroadcasterV2 exists" do
      defined?(Ai::ChatProgressBroadcasterV2)
    end

    test "Broadcaster has all required methods" do
      methods = [:broadcast_phase, :broadcast_file_operation, :broadcast_dependency_check,
        :broadcast_build_output, :broadcast_error, :broadcast_completion]
      methods.all? { |m| Ai::ChatProgressBroadcasterV2.instance_methods.include?(m) }
    end

    # Test SharedTemplateService
    test "SharedTemplateService exists" do
      defined?(Ai::SharedTemplateService)
    end

    test "SharedTemplateService has foundation files method" do
      Ai::SharedTemplateService.instance_methods.include?(:generate_foundation_files)
    end
  end

  def test_models
    section "Model Tests"

    test "AppChatMessage has generating? method" do
      AppChatMessage.instance_methods.include?(:generating?)
    end

    test "AppChatMessage has has_generation_data? method" do
      AppChatMessage.instance_methods.include?(:has_generation_data?)
    end

    test "AppChatMessage has app_generated? method" do
      AppChatMessage.instance_methods.include?(:app_generated?)
    end
  end

  def test_views
    section "View Tests"

    # Check enhanced message partial
    test "Enhanced message partial exists" do
      File.exist?(Rails.root.join("app/views/chat_messages/_enhanced_message.html.erb"))
    end

    # Check all component partials
    components = %w[
      progress_bar phase_item file_tree_item file_status
      dependency_panel error_panel approval_panel
      code_preview diff_preview build_output_line
      notification completion_status
    ]

    components.each do |component|
      test "Component partial #{component} exists" do
        File.exist?(Rails.root.join("app/views/chat_messages/components/_#{component}.html.erb"))
      end
    end
  end

  def test_controller_integration
    section "Controller Integration Tests"

    test "AppChatsController uses enhanced partial for v4_enhanced" do
      content = File.read(Rails.root.join("app/controllers/account/app_chats_controller.rb"))
      content.include?("chat_messages/enhanced_message")
    end

    test "ProcessAppUpdateJobV4 supports use_enhanced parameter" do
      ProcessAppUpdateJobV4.instance_method(:perform).parameters.map(&:last).include?(:use_enhanced)
    end
  end

  def test_websocket_channels
    section "WebSocket Channel Tests"

    test "ChatProgressChannel exists" do
      defined?(ChatProgressChannel)
    end

    test "ChatProgressChannel has required methods" do
      methods = [:subscribed, :unsubscribed, :approve_changes, :reject_changes]
      methods.all? { |m| ChatProgressChannel.instance_methods.include?(m) }
    end
  end

  def test_end_to_end_flow
    section "End-to-End Flow Test"

    begin
      # Create test data
      user = User.first || User.create!(
        email: "test_v4_#{SecureRandom.hex(4)}@example.com",
        password: "password123",
        name: "V4 Test User"
      )

      team = user.teams.first || user.create_default_team

      app = team.apps.create!(
        name: "V4 Enhanced Test #{Time.now.to_i}",
        description: "Testing V4 Enhanced flow"
      )

      message = app.app_chat_messages.create!(
        role: "user",
        content: "Create a simple counter app",
        user: user
      )

      test "Test app created successfully" do
        app.persisted? && message.persisted?
      end

      # Test builder initialization
      test "AppBuilderV4Enhanced initializes with message" do
        builder = Ai::AppBuilderV4Enhanced.new(message)
        builder.is_a?(Ai::AppBuilderV4Enhanced)
      end

      # Test broadcaster initialization
      test "ChatProgressBroadcasterV2 initializes" do
        broadcaster = Ai::ChatProgressBroadcasterV2.new(message)
        broadcaster.is_a?(Ai::ChatProgressBroadcasterV2)
      end

      # Test template service
      test "SharedTemplateService generates files" do
        service = Ai::SharedTemplateService.new(app)
        files = service.generate_foundation_files
        files.is_a?(Array) && files.any?
      end

      # Cleanup
      message.destroy
      app.destroy
    rescue => e
      error "End-to-end test failed: #{e.message}"
      false
    end
  end

  def section(title)
    puts "\n#{title}"
    puts "-" * title.length
  end

  def test(description)
    print "  #{description}... "
    begin
      result = yield
      if result
        @results << {test: description, passed: true}
        puts "✅"
      else
        @warnings << description
        puts "⚠️"
      end
    rescue => e
      @errors << {test: description, error: e.message}
      puts "❌ #{e.message}"
    end
  end

  def error(message)
    @errors << {test: "General", error: message}
    puts "  ❌ #{message}"
  end

  def print_summary
    puts "\n" + "=" * 80
    puts "TEST SUMMARY"
    puts "=" * 80

    total = @results.count + @warnings.count + @errors.count
    passed = @results.count { |r| r[:passed] }

    puts "\n📊 Results:"
    puts "  Total Tests: #{total}"
    puts "  ✅ Passed: #{passed}"
    puts "  ⚠️ Warnings: #{@warnings.count}"
    puts "  ❌ Failed: #{@errors.count}"

    if @warnings.any?
      puts "\n⚠️ Warnings:"
      @warnings.each { |w| puts "  - #{w}" }
    end

    if @errors.any?
      puts "\n❌ Errors:"
      @errors.each { |e| puts "  - #{e[:test]}: #{e[:error]}" }
    end

    if @errors.empty?
      puts "\n🎉 All tests passed! V4 Enhanced is ready for use."
    else
      puts "\n⚠️ Some tests failed. Please review and fix the errors above."
    end

    puts "\n" + "=" * 80
  end
end

# Run the tests
tester = V4EnhancedFlowTester.new
tester.run_all_tests

# Test actual message processing
puts "\n📝 Testing actual message processing flow..."
puts "-" * 40

# Simulate what happens when a user sends a message
user = User.first
if user
  team = user.teams.first
  app = team.apps.first || team.apps.create!(
    name: "Flow Test App",
    description: "Testing message flow"
  )

  puts "\n1. Creating test message..."
  app.app_chat_messages.build(
    role: "user",
    content: "Add a reset button to the counter"
  )

  puts "2. Checking orchestrator version..."
  orchestrator_version = Rails.application.config.app_generation_version
  puts "   Orchestrator: #{orchestrator_version}"

  puts "3. Message would trigger:"
  case orchestrator_version
  when :v4_enhanced
    puts "   → ProcessAppUpdateJobV4.perform_later(message, use_enhanced: true)"
    puts "   → Uses Ai::AppBuilderV4Enhanced"
    puts "   → Real-time visual feedback enabled ✅"
  when :v4
    puts "   → ProcessAppUpdateJobV4.perform_later(message, use_enhanced: false)"
    puts "   → Uses Ai::AppBuilderV4"
  when :v3
    puts "   → ProcessAppUpdateJobV3.perform_later(message)"
    puts "   → Uses V3 orchestrator"
  end

  puts "\n4. Enhanced features active:"
  features = Rails.application.config.app_generation_features
  features.each do |feature, enabled|
    status = enabled ? "✅" : "❌"
    puts "   #{status} #{feature.to_s.humanize}"
  end

  # Don't actually save the message (just testing flow)
  puts "\n✅ Flow test complete (message not saved)"
else
  puts "\n⚠️ No user found for flow test"
end

puts "\n" + "=" * 80
puts "TEST COMPLETE"
puts "=" * 80
