#!/usr/bin/env ruby
# Test improved token allocation system
# Run with: bin/rails runner test_improved_tokens.rb

ENV["VERBOSE_AI_LOGGING"] = "true"  # Enable detailed logging

puts "=" * 80
puts "🚀 TESTING IMPROVED DYNAMIC TOKEN ALLOCATION"
puts "=" * 80

begin
  client = Ai::OpenRouterClient.new
  puts "✅ OpenRouter client initialized with dynamic token allocation"

  # Test 1: Short prompt should get high output tokens
  puts "\n[TEST 1] Short prompt test"
  puts "-" * 40
  
  short_messages = [
    {
      role: "user",
      content: "Create a simple React component that displays 'Hello World'"
    }
  ]
  
  puts "Testing Kimi K2 with short prompt..."
  response1 = client.chat(short_messages, model: :kimi_k2)
  puts "✅ Response received: #{response1[:success] ? 'SUCCESS' : 'FAILED'}"
  if response1[:success]
    puts "   Content length: #{response1[:content].length} characters"
    puts "   Usage: #{response1[:usage]}"
  else
    puts "   Error: #{response1[:error]}"
  end

  # Test 2: Long prompt should still get adequate output tokens
  puts "\n[TEST 2] Long prompt test"
  puts "-" * 40
  
  # Create a very long prompt to test token allocation
  long_prompt = "Create a comprehensive React TypeScript application with the following features:\n\n"
  (1..50).each do |i|
    long_prompt += "#{i}. Feature #{i}: This is a detailed description of feature #{i} that requires specific implementation with proper error handling, state management, user interface components, and comprehensive testing. "
  end
  long_prompt += "\n\nPlease provide a complete implementation with proper TypeScript types, error handling, and best practices."
  
  long_messages = [
    {
      role: "user",
      content: long_prompt
    }
  ]
  
  puts "Long prompt length: #{long_prompt.length} characters"
  puts "Testing Kimi K2 with long prompt..."
  response2 = client.chat(long_messages, model: :kimi_k2)
  puts "✅ Response received: #{response2[:success] ? 'SUCCESS' : 'FAILED'}"
  if response2[:success]
    puts "   Content length: #{response2[:content].length} characters"
    puts "   Usage: #{response2[:usage]}"
    
    # Check if response is complete JSON (no truncation)
    if response2[:content].include?("```") && response2[:content].count("```") % 2 == 0
      puts "   ✅ Response appears complete (balanced code blocks)"
    else
      puts "   ⚠️  Response may be truncated"
    end
  else
    puts "   Error: #{response2[:error]}"
  end

  # Test 3: Test with Claude Sonnet 4 for comparison
  puts "\n[TEST 3] Claude Sonnet 4 comparison"
  puts "-" * 40
  
  puts "Testing Claude Sonnet 4 with short prompt..."
  response3 = client.chat(short_messages, model: :claude_sonnet_4)
  puts "✅ Response received: #{response3[:success] ? 'SUCCESS' : 'FAILED'}"
  if response3[:success]
    puts "   Content length: #{response3[:content].length} characters"
    puts "   Usage: #{response3[:usage]}"
  else
    puts "   Error: #{response3[:error]}"
  end

  # Test 4: Tool calling with dynamic tokens
  puts "\n[TEST 4] Tool calling with dynamic tokens"
  puts "-" * 40
  
  tools = [
    {
      type: "function",
      function: {
        name: "create_file",
        description: "Create a new file with content",
        parameters: {
          type: "object",
          properties: {
            path: { type: "string", description: "File path" },
            content: { type: "string", description: "File content" }
          },
          required: ["path", "content"]
        }
      }
    }
  ]
  
  tool_messages = [
    {
      role: "user",
      content: "Create a complete React TypeScript component file for a todo list with full CRUD operations, proper TypeScript types, and modern React patterns."
    }
  ]
  
  puts "Testing tool calling with Kimi K2..."
  tool_response = client.chat_with_tools(tool_messages, tools, model: :kimi_k2)
  puts "✅ Tool response received: #{tool_response[:success] ? 'SUCCESS' : 'FAILED'}"
  if tool_response[:success]
    puts "   Tool calls: #{tool_response[:tool_calls]&.length || 0}"
    puts "   Content length: #{tool_response[:content]&.length || 0} characters"
    puts "   Usage: #{tool_response[:usage]}"
    
    # Check tool call completeness
    if tool_response[:tool_calls]&.any?
      first_call = tool_response[:tool_calls].first
      if first_call[:function] && first_call[:function][:arguments]
        begin
          args = JSON.parse(first_call[:function][:arguments])
          puts "   ✅ Tool arguments parsed successfully"
          puts "     File path: #{args['path']}"
          puts "     Content length: #{args['content']&.length || 0} characters"
        rescue JSON::ParserError => e
          puts "   ❌ Tool arguments parsing failed: #{e.message}"
        end
      end
    end
  else
    puts "   Error: #{tool_response[:error]}"
  end

rescue => e
  puts "❌ Test error: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
end

puts "\n" + "=" * 80
puts "🏁 DYNAMIC TOKEN ALLOCATION TEST COMPLETED"
puts "=" * 80