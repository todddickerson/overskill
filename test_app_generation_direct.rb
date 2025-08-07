#!/usr/bin/env ruby

# Direct AI App Generation Test
# Tests the actual generation process with GPT-5/Claude fallback

require_relative 'app/services/ai/open_router_client'

puts "🧪 Testing Direct AI App Generation"
puts "=" * 50

# Initialize the client
begin
  client = Ai::OpenRouterClient.new
  puts "✅ OpenRouter client initialized"
rescue => e
  puts "❌ Failed to initialize client: #{e.message}"
  exit 1
end

# Test 1: Simple chat request (no tools)
puts "\n📝 Test 1: Simple Chat Request"
begin
  messages = [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "Explain what React hooks are in one sentence." }
  ]
  
  response = client.chat(messages, model: :gpt5, temperature: 0.7)
  
  if response[:success]
    puts "✅ GPT-5 chat successful"
    puts "  Response length: #{response[:content]&.length || 0} chars"
    puts "  Model used: #{response[:model]}"
  else
    puts "❌ GPT-5 chat failed: #{response[:error]}"
  end
rescue => e
  puts "❌ Chat test failed: #{e.message}"
end

# Test 2: Tool calling request
puts "\n🛠️ Test 2: Tool Calling"
begin
  messages = [
    { role: "system", content: "You are a helpful coding assistant." },
    { role: "user", content: "Create a simple todo list app structure" }
  ]
  
  tools = [
    {
      type: "function",
      function: {
        name: "create_app_structure",
        description: "Create application file structure",
        parameters: {
          type: "object",
          properties: {
            files: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  path: { type: "string" },
                  content: { type: "string" }
                }
              }
            }
          }
        }
      }
    }
  ]
  
  response = client.chat_with_tools(messages, tools, model: :gpt5)
  
  if response[:success]
    puts "✅ GPT-5 tool calling successful"
    puts "  Content: #{response[:content]&.length || 0} chars"
    puts "  Tool calls: #{response[:tool_calls]&.size || 0}"
    puts "  Model used: #{response[:model]}"
    
    if response[:tool_calls]&.any?
      puts "  🎯 Tools were called successfully"
    else
      puts "  ⚠️  No tools were called"
    end
  else
    puts "❌ GPT-5 tool calling failed: #{response[:error]}"
  end
rescue => e
  puts "❌ Tool calling test failed: #{e.message}"
end

# Test 3: Fallback mechanism (force error to test Claude fallback)
puts "\n🔄 Test 3: Fallback Mechanism"
begin
  # This should test the fallback logic
  messages = [
    { role: "system", content: "You are a web developer creating React applications." },
    { role: "user", content: "Create a complex dashboard application with multiple features." }
  ]
  
  # Try with a model that might fail to test fallback
  response = client.chat(messages, model: :gpt5, temperature: 0.3, max_tokens: 1000)
  
  puts "✅ Model request completed"
  puts "  Model used: #{response[:model] || 'unknown'}"
  puts "  Success: #{response[:success]}"
  
  if !response[:success] && response[:error]
    puts "  Error (triggering fallback): #{response[:error]}"
  end
  
rescue => e
  puts "❌ Fallback test failed: #{e.message}"
end

# Test 4: App generation (the full pipeline)
puts "\n🏗️ Test 4: Full App Generation"
begin
  prompt = "Create a simple task management app with the following features: add tasks, mark as complete, delete tasks, filter by status. Use React and modern JavaScript."
  
  response = client.generate_app(prompt, framework: "react")
  
  if response[:success]
    puts "✅ App generation successful"
    
    if response[:tool_calls]&.any?
      tool_call = response[:tool_calls].first
      if tool_call.dig(:function, :name) == "generate_app" || tool_call.dig("function", "name") == "generate_app"
        puts "  🎯 generate_app function was called"
        
        # Try to extract arguments
        args = tool_call.dig(:function, :arguments) || tool_call.dig("function", "arguments")
        if args.is_a?(String)
          begin
            parsed_args = JSON.parse(args)
            if parsed_args["files"]
              puts "  📁 Generated #{parsed_args['files'].size} files"
              parsed_args["files"].each do |file|
                puts "    - #{file['path']}: #{file['content']&.length || 0} chars"
              end
            end
          rescue JSON::ParserError
            puts "  ⚠️  Could not parse function arguments"
          end
        end
      end
    else
      puts "  ⚠️  No function calls in response"
    end
  else
    puts "❌ App generation failed: #{response[:error]}"
  end
  
rescue => e
  puts "❌ App generation test failed: #{e.message}"
end

# Test 5: Error handling and recovery
puts "\n🛡️ Test 5: Error Handling"
begin
  # Test with invalid parameters to check error handling
  response = client.chat([], model: :invalid_model)
  
  if response[:success]
    puts "⚠️  Expected error but got success - error handling may be too permissive"
  else
    puts "✅ Error handling working"
    puts "  Error: #{response[:error]}"
    puts "  Suggestion: #{response[:suggestion]}" if response[:suggestion]
  end
  
rescue => e
  puts "✅ Exception caught properly: #{e.message}"
end

puts "\n" + "=" * 50
puts "🎯 DIRECT GENERATION TEST SUMMARY"
puts "All tests completed. Check individual results above."
puts "=" * 50