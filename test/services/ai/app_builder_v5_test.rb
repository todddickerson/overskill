require "test_helper"
require "minitest/mock"

module Ai
  class AppBuilderV5Test < ActiveSupport::TestCase
    setup do
      # Create test user and team directly
      @user = User.create!(
        email: "test@example.com",
        password: "password123",
        time_zone: "UTC"
      )
      @team = Team.create!(
        name: "Test Team"
      )
      @membership = @team.memberships.create!(user: @user)

      # Create an App for the chat message
      @app = App.create!(
        name: "Test App",
        team: @team,
        creator: @membership,
        description: "Test app for V5 builder",
        prompt: "Build a simple todo app"
      )

      @chat_message = AppChatMessage.create!(
        app: @app,
        user: @user,
        content: "Build a simple todo app",
        role: "user"
      )
      @builder = AppBuilderV5.new(@chat_message)

      # Mock Anthropic client
      @mock_client = Minitest::Mock.new
    end

    test "execute_tool_calling_cycle handles tool_use stop reason correctly" do
      # Mock response with tool_use stop reason
      mock_response = {
        success: true,
        content: "I'll create a todo app for you.",
        tool_calls: [
          {
            "id" => "toolu_001",
            "function" => {
              "name" => "os-write",
              "arguments" => '{"file_path": "App.tsx", "content": "import React from \"react\";"}'
            }
          }
        ],
        stop_reason: "tool_use",
        thinking_blocks: []
      }

      # Second response after tool execution
      final_response = {
        success: true,
        content: "File created successfully.",
        tool_calls: [],
        stop_reason: "stop",
        thinking_blocks: []
      }

      # Match the actual signature: chat_with_tools(messages, tools, options_hash)
      @mock_client.expect(:chat_with_tools, mock_response) do |messages, tools, options|
        messages.is_a?(Array) && tools.is_a?(Array) && options.is_a?(Hash)
      end
      @mock_client.expect(:chat_with_tools, final_response) do |messages, tools, options|
        messages.is_a?(Array) && tools.is_a?(Array) && options.is_a?(Hash)
      end

      Ai::AnthropicClient.stub :instance, @mock_client do
        result = @builder.send(:execute_tool_calling_cycle, @mock_client, [], [], "session-123")

        assert_equal 1, result[:tool_cycles]
        assert_equal "File created successfully.", result[:content]
      end

      @mock_client.verify
    end

    test "tool results are formatted with tool_result blocks FIRST in content array" do
      tool_calls = [
        {
          "id" => "toolu_001",
          "function" => {
            "name" => "os-write",
            "arguments" => '{"file_path": "test.txt", "content": "test content"}'
          }
        },
        {
          "id" => "toolu_002",
          "function" => {
            "name" => "os-read",
            "arguments" => '{"file_path": "package.json"}'
          }
        }
      ]

      results = @builder.send(:execute_and_format_tool_results, tool_calls)

      # Verify all results are tool_result blocks
      assert results.all? { |r| r[:type] == "tool_result" }

      # Verify each has proper structure
      results.each do |result|
        assert result.key?(:tool_use_id)
        assert result.key?(:content)
      end

      # Verify results array is returned (for SINGLE user message)
      assert_instance_of Array, results
      assert_equal 2, results.length
    end

    test "parallel tool calls are batched in single user message" do
      # Mock multiple tool calls in parallel
      mock_response = {
        success: true,
        content: "Creating multiple files...",
        tool_calls: [
          {
            "id" => "toolu_001",
            "function" => {"name" => "os-write", "arguments" => '{"file_path": "App.tsx", "content": "app"}'}
          },
          {
            "id" => "toolu_002",
            "function" => {"name" => "os-write", "arguments" => '{"file_path": "Todo.tsx", "content": "todo"}'}
          },
          {
            "id" => "toolu_003",
            "function" => {"name" => "os-write", "arguments" => '{"file_path": "index.css", "content": "css"}'}
          }
        ],
        stop_reason: "tool_use",
        thinking_blocks: []
      }

      # Capture the messages sent to the API
      captured_messages = nil

      @mock_client.expect(:chat_with_tools, mock_response) do |messages, tools, opts|
        captured_messages = messages if messages.any? { |m| m[:role] == "user" && m[:content].is_a?(Array) }
        true
      end

      # Final response
      @mock_client.expect(:chat_with_tools, {success: true, content: "Done", tool_calls: [], stop_reason: "stop"}) do |messages, tools, options|
        messages.is_a?(Array) && tools.is_a?(Array) && options.is_a?(Hash)
      end

      Ai::AnthropicClient.stub :instance, @mock_client do
        @builder.send(:execute_tool_calling_cycle, @mock_client, [], [], "session-123")
      end

      # Verify all tool results were in a single user message
      if captured_messages
        user_messages_with_tool_results = captured_messages.select do |m|
          m[:role] == "user" && m[:content].is_a?(Array) && m[:content].any? { |c| c[:type] == "tool_result" }
        end

        assert_equal 1, user_messages_with_tool_results.length, "All tool results should be in single user message"
      end
    end

    test "thinking blocks are preserved during tool cycles" do
      mock_response = {
        success: true,
        content: "Let me analyze this...",
        tool_calls: [
          {
            "id" => "toolu_001",
            "function" => {"name" => "os-write", "arguments" => '{"file_path": "test.txt", "content": "test"}'}
          }
        ],
        thinking_blocks: [
          {
            "type" => "thinking",
            "content" => "I need to create a todo app with React components...",
            "signature" => "mock_sig_123"
          }
        ],
        stop_reason: "tool_use"
      }

      assistant_content = @builder.send(:build_assistant_content_with_tools, mock_response)

      # Verify thinking blocks are included
      thinking_blocks = assistant_content.select { |b| b["type"] == "thinking" }
      assert_equal 1, thinking_blocks.length
      assert_equal "I need to create a todo app with React components...", thinking_blocks.first["content"]

      # Verify order: text, thinking, tool_use
      types = assistant_content.map { |b| b[:type] || b["type"] }
      expected_order = ["text", "thinking", "tool_use"]
      assert_equal expected_order, types
    end

    test "stop reason handling for max_tokens" do
      mock_response = {
        success: true,
        content: "This is a very long response that got truncated...",
        tool_calls: [],
        stop_reason: "max_tokens",
        thinking_blocks: []
      }

      @mock_client.expect(:chat_with_tools, mock_response) do |messages, tools, options|
        messages.is_a?(Array) && tools.is_a?(Array) && options.is_a?(Hash)
      end

      Ai::AnthropicClient.stub :instance, @mock_client do
        result = @builder.send(:execute_tool_calling_cycle, @mock_client, [], [], "session-123")

        # Should exit the loop on max_tokens
        assert_equal 0, result[:tool_cycles]
        assert_equal "max_tokens", result[:stop_reason]
      end
    end

    test "tool cycle prevents infinite loops" do
      # Mock response that always returns tool_use
      mock_response = {
        success: true,
        content: "Processing...",
        tool_calls: [
          {
            "id" => "toolu_001",
            "function" => {"name" => "os-write", "arguments" => '{"file_path": "test.txt", "content": "test"}'}
          }
        ],
        stop_reason: "tool_use",
        thinking_blocks: []
      }

      # Expect exactly 5 calls (max_tool_cycles)
      5.times do
        @mock_client.expect(:chat_with_tools, mock_response) do |messages, tools, options|
          messages.is_a?(Array) && tools.is_a?(Array) && options.is_a?(Hash)
        end
      end

      Ai::AnthropicClient.stub :instance, @mock_client do
        result = @builder.send(:execute_tool_calling_cycle, @mock_client, [], [], "session-123")

        # Should stop at max cycles
        assert_equal 5, result[:tool_cycles]
      end
    end

    test "execute_single_tool handles os-write correctly" do
      file = @builder.send(:execute_single_tool, "os-write", {
        "file_path" => "test.txt",
        "content" => "test content"
      })

      assert file[:content].include?("File written successfully")
      refute file[:error]
    end

    test "execute_single_tool handles blank content error" do
      result = @builder.send(:execute_single_tool, "os-write", {
        "file_path" => "test.txt",
        "content" => ""
      })

      assert result[:error]
      assert result[:error].include?("blank content")
    end

    test "execute_single_tool handles unknown tools" do
      result = @builder.send(:execute_single_tool, "unknown-tool", {})

      assert result[:error]
      assert result[:error].include?("Unknown tool")
    end

    test "conversation history includes tool cycles" do
      # Set up some tool calls in assistant message
      @builder.instance_variable_get(:@assistant_message).tool_calls = [
        {"name" => "os-write", "file_path" => "App.tsx", "status" => "complete"},
        {"name" => "os-write", "file_path" => "Todo.tsx", "status" => "complete"}
      ]

      messages = []
      @builder.send(:add_conversation_history, messages)

      # Should include tool execution summary
      system_messages = messages.select { |m| m[:role] == "system" }
      tool_summary = system_messages.find { |m| m[:content].include?("RECENT ACTIONS TAKEN") }

      assert tool_summary
      assert tool_summary[:content].include?("os-write")
      assert tool_summary[:content].include?("App.tsx")
    end
  end
end
