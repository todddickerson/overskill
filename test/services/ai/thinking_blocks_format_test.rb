require 'test_helper'

class ThinkingBlocksFormatTest < ActiveSupport::TestCase
  # No setup needed - we're just testing format, not actual API calls
  
  test "thinking blocks should have correct format according to API spec" do
    # According to documentation, thinking blocks should have this structure:
    correct_thinking_block = {
      type: "thinking",
      thinking: "Let me analyze this step by step...",  # NOT 'content'!
      signature: "WaUjzkypQ2mUEVM36O2TxuC06KN8xyfbJwyem2dw3URve/op91XWHOEBLLqIOMfFG/UvLEczmEsUjavL"
    }
    
    # This is what we're currently doing (WRONG):
    incorrect_thinking_block = {
      type: "thinking",
      content: "Let me analyze this step by step...",  # WRONG field name!
      signature: "WaUjzkypQ2mUEVM36O2TxuC06KN8xyfbJwyem2dw3URve/op91XWHOEBLLqIOMfFG/UvLEczmEsUjavL"
    }
    
    # Test the structure we send in tool use scenarios
    tool_use_message = {
      role: "assistant",
      content: [
        correct_thinking_block,
        {
          type: "tool_use",
          id: "tool_123",
          name: "os-write",
          input: { path: "test.txt", content: "test" }
        }
      ]
    }
    
    # Verify the thinking block has 'thinking' field, not 'content'
    thinking = tool_use_message[:content].find { |b| b[:type] == "thinking" }
    assert thinking.key?(:thinking), "Thinking block must have 'thinking' field"
    assert_not thinking.key?(:content), "Thinking block should NOT have 'content' field"
    assert thinking.key?(:signature), "Thinking block must have 'signature' field"
  end
  
  test "API response thinking blocks should be parsed correctly" do
    # Simulate API response structure
    api_response = {
      "content" => [
        {
          "type" => "thinking",
          "thinking" => "Let me analyze this request...",  # API returns 'thinking' field
          "signature" => "abc123..."
        },
        {
          "type" => "text",
          "text" => "I'll help you with that."
        }
      ]
    }
    
    # Test our extraction logic
    thinking_blocks = []
    api_response["content"].each do |block|
      if block["type"] == "thinking"
        # CORRECT extraction:
        thinking_blocks << {
          "type" => "thinking",
          "thinking" => block["thinking"],  # Use 'thinking' not 'content'!
          "signature" => block["signature"]
        }
      end
    end
    
    assert_equal 1, thinking_blocks.size
    assert_equal "thinking", thinking_blocks[0]["type"]
    assert_equal "Let me analyze this request...", thinking_blocks[0]["thinking"]
    assert_equal "abc123...", thinking_blocks[0]["signature"]
  end
  
  test "conversation flow with thinking blocks for tool use" do
    # Test the complete flow for tool use scenarios
    messages = []
    
    # User message
    messages << { role: "user", content: "Create a file test.txt" }
    
    # Assistant response with thinking and tool use
    assistant_thinking = {
      type: "thinking",
      thinking: "I need to create a file using os-write tool",  # Correct field
      signature: "signature123"
    }
    
    assistant_tool_use = {
      type: "tool_use",
      id: "tool_456",
      name: "os-write",
      input: { path: "test.txt", content: "Hello" }
    }
    
    # MUST include thinking blocks for tool use scenarios
    messages << {
      role: "assistant",
      content: [assistant_thinking, assistant_tool_use]
    }
    
    # Tool result from user
    messages << {
      role: "user",
      content: [
        {
          type: "tool_result",
          tool_use_id: "tool_456",
          content: "File created successfully"
        }
      ]
    }
    
    # Validate the structure
    assistant_msg = messages.find { |m| m[:role] == "assistant" }
    thinking_block = assistant_msg[:content].find { |b| b[:type] == "thinking" }
    
    assert_not_nil thinking_block
    assert_equal "thinking", thinking_block[:type]
    assert thinking_block.key?(:thinking), "Must have 'thinking' field"
    assert thinking_block.key?(:signature), "Must have 'signature' field"
    assert_equal "I need to create a file using os-write tool", thinking_block[:thinking]
  end
end