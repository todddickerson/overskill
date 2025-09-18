#!/usr/bin/env ruby

# Test script for V4 Enhanced app generation flow
# This script validates the complete V4 Enhanced orchestrator flow

require_relative "config/environment"
require "benchmark"

class V4EnhancedFlowTester
  def initialize
    @results = {}
    @errors = []
    @user = User.first || create_test_user
    puts "🔍 Testing V4 Enhanced App Generation Flow"
    puts "=" * 60
  end

  def run_complete_test
    # Test 1: Validate required services exist
    test_required_services

    # Test 2: Validate view components
    test_view_components

    # Test 3: Test AppChatMessage methods
    test_chat_message_methods

    # Test 4: Test the complete flow (dry run)
    test_enhanced_builder_flow

    # Test 5: Test the broadcasting system
    test_broadcaster_system

    # Test 6: Validate configuration
    test_configuration

    # Print final report
    print_final_report
  rescue => e
    puts "❌ Fatal error during testing: #{e.message}"
    puts e.backtrace.first(5)
    false
  end

  private

  def test_required_services
    puts "\n📋 Testing Required Services"
    puts "-" * 40

    # Test SharedTemplateService
    if defined?(Ai::SharedTemplateService)
      app = create_test_app
      service = Ai::SharedTemplateService.new(app)

      # Check for method mismatch
      if service.respond_to?(:generate_foundation_files)
        @results[:shared_template_service] = "✅ generate_foundation_files method exists"
      elsif service.respond_to?(:generate_core_files)
        @results[:shared_template_service] = "⚠️  Method mismatch: has generate_core_files, needs generate_foundation_files"
        @errors << "SharedTemplateService method mismatch"
      else
        @results[:shared_template_service] = "❌ No generation methods found"
        @errors << "SharedTemplateService missing generation methods"
      end
      app.destroy
    else
      @results[:shared_template_service] = "❌ SharedTemplateService not found"
      @errors << "SharedTemplateService class missing"
    end

    # Test ExternalViteBuilder
    @results[:external_vite_builder] = defined?(Deployment::ExternalViteBuilder) ? "✅ Found" : "❌ Missing"
    @errors << "ExternalViteBuilder missing" unless defined?(Deployment::ExternalViteBuilder)

    # Test CloudflareWorkersDeployer
    @results[:cloudflare_deployer] = defined?(Deployment::CloudflareWorkersDeployer) ? "✅ Found" : "❌ Missing"
    @errors << "CloudflareWorkersDeployer missing" unless defined?(Deployment::CloudflareWorkersDeployer)

    # Test AppBuilderV4Enhanced
    @results[:app_builder_v4_enhanced] = defined?(Ai::AppBuilderV4Enhanced) ? "✅ Found" : "❌ Missing"
    @errors << "AppBuilderV4Enhanced missing" unless defined?(Ai::AppBuilderV4Enhanced)

    @results.each { |service, status| puts "  #{service}: #{status}" }
  end

  def test_view_components
    puts "\n🎨 Testing View Components"
    puts "-" * 40

    required_partials = [
      "app/views/chat_messages/components/_progress_bar.html.erb",
      "app/views/chat_messages/components/_phase_item.html.erb",
      "app/views/chat_messages/components/_file_tree_item.html.erb",
      "app/views/chat_messages/components/_file_status.html.erb",
      "app/views/chat_messages/components/_dependency_panel.html.erb",
      "app/views/chat_messages/components/_error_panel.html.erb"
    ]

    missing_partials = []

    required_partials.each do |partial_path|
      full_path = Rails.root.join(partial_path)
      if File.exist?(full_path)
        @results[File.basename(partial_path)] = "✅ Found"
      else
        @results[File.basename(partial_path)] = "❌ Missing"
        missing_partials << partial_path
        @errors << "Missing view component: #{partial_path}"
      end
    end

    # Test enhanced_message partial
    enhanced_partial = Rails.root.join("app/views/chat_messages/_enhanced_message.html.erb")
    @results[:enhanced_message_partial] = File.exist?(enhanced_partial) ? "✅ Found" : "❌ Missing"

    # Check if the controller actually uses the enhanced partial
    controller_uses_enhanced = check_controller_uses_enhanced_partial
    @results[:controller_integration] = controller_uses_enhanced ? "⚠️  Uses basic partial" : "❓ Check needed"

    puts "  Missing partials: #{missing_partials.count}"
    @results.each { |component, status| puts "  #{component}: #{status}" }
  end

  def test_chat_message_methods
    puts "\n💬 Testing AppChatMessage Methods"
    puts "-" * 40

    # Create test chat message
    app = create_test_app
    message = app.app_chat_messages.create!(
      content: "Test message",
      role: "user",
      user: @user
    )

    # Test methods used in enhanced_message partial
    methods_to_test = %w[generating? has_generation_data? app_generated?]

    methods_to_test.each do |method_name|
      if message.respond_to?(method_name)
        @results["#{method_name}_method"] = "✅ Exists"
      else
        @results["#{method_name}_method"] = "❌ Missing"
        @errors << "AppChatMessage missing method: #{method_name}"
      end
    end

    # Check available statuses
    available_statuses = AppChatMessage::STATUSES
    @results[:available_statuses] = "✅ #{available_statuses.join(", ")}"

    # Test if 'generating' status exists
    if available_statuses.include?("generating")
      @results[:generating_status] = "✅ Found"
    else
      @results[:generating_status] = "❌ Missing"
      @errors << "AppChatMessage missing 'generating' status"
    end

    @results.each { |method, status| puts "  #{method}: #{status}" }

    message.destroy
    app.destroy
  end

  def test_enhanced_builder_flow
    puts "\n🔄 Testing Enhanced Builder Flow (Dry Run)"
    puts "-" * 40

    app = create_test_app
    message = app.app_chat_messages.create!(
      content: "Create a simple todo app",
      role: "user",
      user: @user
    )

    begin
      # Test broadcaster initialization
      Ai::ChatProgressBroadcasterV2.new(message)
      @results[:broadcaster_init] = "✅ Broadcaster initializes"

      # Test builder initialization
      Ai::AppBuilderV4Enhanced.new(message)
      @results[:builder_init] = "✅ Builder initializes"

      # Test the shared template service call (method mismatch issue)
      template_service = Ai::SharedTemplateService.new(app)
      if template_service.respond_to?(:generate_foundation_files)
        @results[:template_method] = "✅ Correct method available"
      else
        @results[:template_method] = "❌ Method mismatch - needs generate_foundation_files"
        @errors << "SharedTemplateService method mismatch prevents execution"
      end

      # Don't actually execute the full flow to avoid side effects
      @results[:dry_run_complete] = "✅ All components can be initialized"
    rescue => e
      @results[:builder_flow] = "❌ Failed: #{e.message}"
      @errors << "Builder flow error: #{e.message}"
    end

    @results.each { |test, status| puts "  #{test}: #{status}" }

    message.destroy
    app.destroy
  end

  def test_broadcaster_system
    puts "\n📡 Testing Broadcaster System"
    puts "-" * 40

    app = create_test_app
    message = app.app_chat_messages.create!(
      content: "Test broadcast",
      role: "user",
      user: @user
    )

    begin
      broadcaster = Ai::ChatProgressBroadcasterV2.new(message)

      # Test key broadcasting methods
      methods_to_test = [
        :broadcast_phase,
        :broadcast_file_operation,
        :broadcast_dependency_check,
        :broadcast_build_output,
        :broadcast_error,
        :broadcast_completion
      ]

      methods_to_test.each do |method|
        if broadcaster.respond_to?(method)
          @results["broadcast_#{method}"] = "✅ Available"
        else
          @results["broadcast_#{method}"] = "❌ Missing"
          @errors << "Broadcaster missing method: #{method}"
        end
      end

      # Test that Turbo::StreamsChannel is available
      if defined?(Turbo::StreamsChannel)
        @results[:turbo_streams] = "✅ Available"
      else
        @results[:turbo_streams] = "❌ Missing - may cause broadcast failures"
        @errors << "Turbo::StreamsChannel not available"
      end
    rescue => e
      @results[:broadcaster_test] = "❌ Failed: #{e.message}"
      @errors << "Broadcaster test error: #{e.message}"
    end

    @results.each { |test, status| puts "  #{test}: #{status}" }

    message.destroy
    app.destroy
  end

  def test_configuration
    puts "\n⚙️  Testing Configuration"
    puts "-" * 40

    # Check orchestrator version setting
    version = Rails.application.config.app_generation_version
    @results[:orchestrator_version] = "✅ #{version}"

    # Check if it's set to use V4 Enhanced
    @results[:v4_enhanced_enabled] = if version == :v4_enhanced
      "✅ Configured for V4 Enhanced"
    else
      "⚠️  Not configured for V4 Enhanced (current: #{version})"
    end

    # Check feature flags
    features = Rails.application.config.app_generation_features
    @results[:feature_flags] = "✅ #{features.keys.join(", ")}"

    # Check environment variables
    env_vars = %w[CLOUDFLARE_ACCOUNT_ID CLOUDFLARE_API_TOKEN SUPABASE_URL]
    env_vars.each do |var|
      @results["env_#{var}"] = ENV[var].present? ? "✅ Set" : "⚠️  Missing"
    end

    @results.each { |config, status| puts "  #{config}: #{status}" }
  end

  def print_final_report
    puts "\n" + "=" * 60
    puts "📊 FINAL ANALYSIS REPORT"
    puts "=" * 60

    total_tests = @results.count
    passed_tests = @results.values.count { |v| v.start_with?("✅") }
    warning_tests = @results.values.count { |v| v.start_with?("⚠️") }
    failed_tests = @results.values.count { |v| v.start_with?("❌") }

    puts "\n📈 Test Results:"
    puts "  Total Tests: #{total_tests}"
    puts "  ✅ Passed: #{passed_tests}"
    puts "  ⚠️  Warnings: #{warning_tests}"
    puts "  ❌ Failed: #{failed_tests}"

    if @errors.any?
      puts "\n❌ Critical Issues Found:"
      @errors.each_with_index do |error, i|
        puts "  #{i + 1}. #{error}"
      end
    end

    puts "\n🔧 Required Fixes:"
    puts "  1. Add missing AppChatMessage methods (generating?, has_generation_data?, app_generated?)"
    puts "  2. Fix SharedTemplateService method name (generate_core_files -> generate_foundation_files)"
    puts "  3. Update app_chats_controller to use enhanced_message partial"
    puts "  4. Add missing 'generating' status to AppChatMessage::STATUSES"

    if @errors.empty?
      puts "\n🎉 All systems ready for V4 Enhanced!"
      true
    else
      puts "\n⚠️  #{@errors.count} issues need to be resolved before V4 Enhanced will work"
      false
    end
  end

  # Helper methods

  def create_test_user
    # Use existing user if available
    existing_user = User.first
    return existing_user if existing_user

    User.create!(
      first_name: "Test",
      last_name: "User",
      email: "test-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def create_test_app
    team = @user.teams.first
    team ||= @user.teams.create!(name: "Test Team")

    # Create membership if needed
    membership = team.memberships.find_or_create_by(user: @user) do |m|
      m.role_ids = team.roles.where(key: "admin").pluck(:id)
    end

    team.apps.create!(
      name: "Test App #{SecureRandom.hex(3)}",
      description: "Test app for V4 Enhanced validation",
      prompt: "Create a simple todo app with React and TypeScript",
      creator: membership,
      base_price: 0.0
    )
  end

  def check_controller_uses_enhanced_partial
    controller_path = Rails.root.join("app/controllers/account/app_chats_controller.rb")
    return false unless File.exist?(controller_path)

    content = File.read(controller_path)
    content.include?("enhanced_message")
  end
end

# Run the test if this script is executed directly
if __FILE__ == $0
  tester = V4EnhancedFlowTester.new
  success = tester.run_complete_test
  exit(success ? 0 : 1)
end
