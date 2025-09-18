# frozen_string_literal: true

require "test_helper"

class Ai::Prompts::AgentPromptServiceTest < ActiveSupport::TestCase
  def setup
    @service = Ai::Prompts::AgentPromptService.new
  end

  test "initializes with default variables" do
    assert_equal "OverSkill", @service.variables[:platform_name]
    assert_equal "os-", @service.variables[:tool_prefix]
    assert_equal "additional_data", @service.variables[:context_section_name]
  end

  test "allows custom variables to override defaults" do
    custom_service = Ai::Prompts::AgentPromptService.new(
      platform_name: "CustomPlatform",
      tool_prefix: "custom-"
    )

    assert_equal "CustomPlatform", custom_service.variables[:platform_name]
    assert_equal "custom-", custom_service.variables[:tool_prefix]
    assert_equal "additional_data", custom_service.variables[:context_section_name] # default preserved
  end

  test "generates complete configuration" do
    config = @service.generate_config

    assert config.key?(:prompt)
    assert config.key?(:tools)
    assert config.key?(:metadata)

    assert config[:prompt].is_a?(String)
    assert config[:tools].is_a?(Array)
    assert config[:metadata].is_a?(Hash)
  end

  test "substitutes variables in prompt" do
    prompt = @service.generate_prompt

    assert_includes prompt, "OverSkill"
    assert_includes prompt, "os-"
    assert_includes prompt, "additional_data"
    refute_includes prompt, "{{platform_name}}"
    refute_includes prompt, "{{tool_prefix}}"
  end

  test "generates valid tools JSON" do
    tools = @service.generate_tools

    assert tools.is_a?(Array)
    assert tools.all? { |tool| tool.key?("name") && tool.key?("description") }

    # All tool names should use the correct prefix
    tool_names = tools.map { |tool| tool["name"] }
    assert tool_names.all? { |name| name.start_with?("os-") }
  end

  test "provides tool names list" do
    tool_names = @service.tool_names

    assert tool_names.is_a?(Array)
    assert tool_names.include?("os-add-dependency")
    assert tool_names.include?("os-write")
    assert tool_names.include?("os-view")
  end

  test "validates configuration" do
    assert @service.valid_config?

    invalid_service = Ai::Prompts::AgentPromptService.new(platform_name: "")
    refute invalid_service.valid_config?
  end

  test "creates platform-specific configurations" do
    overskill_service = Ai::Prompts::AgentPromptService.for_platform(:overskill)
    lovable_service = Ai::Prompts::AgentPromptService.for_platform(:lovable)

    assert_equal "OverSkill", overskill_service.variables[:platform_name]
    assert_equal "os-", overskill_service.variables[:tool_prefix]

    assert_equal "Lovable", lovable_service.variables[:platform_name]
    assert_equal "lov-", lovable_service.variables[:tool_prefix]
    assert_equal "useful-context", lovable_service.variables[:context_section_name]
  end

  test "lists available platforms" do
    platforms = Ai::Prompts::AgentPromptService.available_platforms

    assert_includes platforms, :overskill
    assert_includes platforms, :lovable
    assert_includes platforms, :generic
  end

  test "exports configuration to files" do
    Dir.mktmpdir do |temp_dir|
      export_path = @service.export_to_files(temp_dir)

      assert File.exist?(File.join(export_path, "prompt.txt"))
      assert File.exist?(File.join(export_path, "tools.json"))
      assert File.exist?(File.join(export_path, "metadata.json"))

      # Verify content
      prompt_content = File.read(File.join(export_path, "prompt.txt"))
      assert_includes prompt_content, "OverSkill"

      tools_content = JSON.parse(File.read(File.join(export_path, "tools.json")))
      assert tools_content.is_a?(Array)
    end
  end

  test "handles current date as lambda" do
    # Freeze time for consistent testing
    travel_to Time.zone.parse("2025-01-15") do
      service = Ai::Prompts::AgentPromptService.new
      prompt = service.generate_prompt

      assert_includes prompt, "2025-01-15"
    end
  end

  test "custom variables with lambdas work correctly" do
    custom_service = Ai::Prompts::AgentPromptService.new(
      current_date: -> { "CUSTOM-DATE" },
      platform_name: -> { "DYNAMIC-PLATFORM" }
    )

    prompt = custom_service.generate_prompt
    assert_includes prompt, "CUSTOM-DATE"
    assert_includes prompt, "DYNAMIC-PLATFORM"
  end
end
