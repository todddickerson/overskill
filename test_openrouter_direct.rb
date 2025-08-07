#!/usr/bin/env ruby
# Direct OpenRouter client test to diagnose JSON parsing issues
# Run with: bin/rails runner test_openrouter_direct.rb

puts "=" * 60
puts "🔍 OPENROUTER CLIENT DIAGNOSTIC TEST"
puts "=" * 60

# Test the OpenRouter client directly
begin
  client = Ai::OpenRouterClient.new
  puts "✅ OpenRouter client initialized"
  
  # Simple test prompt
  test_prompt = "Create a simple HTML file that displays 'Hello World' with basic CSS styling."
  
  puts "\n🤖 Testing basic chat completion..."
  puts "Prompt: #{test_prompt[0..100]}..."
  
  start_time = Time.current
  
  # Test basic chat without tools
  response = client.chat([
    {
      role: "user",
      content: test_prompt
    }
  ])
  
  duration = Time.current - start_time
  
  puts "\n📊 Response received in #{duration.round(2)}s"
  puts "Response type: #{response.class}"
  
  if response.is_a?(Hash)
    puts "Response keys: #{response.keys.join(', ')}"
    
    if response[:content]
      content_preview = response[:content][0..200]
      puts "Content preview: #{content_preview}..."
      puts "Content length: #{response[:content].length} characters"
    end
    
    if response[:error]
      puts "❌ Error in response: #{response[:error]}"
    end
  else
    puts "⚠️  Unexpected response type: #{response.inspect[0..200]}..."
  end
  
  # Test with tool calling
  puts "\n🛠️  Testing tool calling capability..."
  
  tools = [
    {
      type: "function",
      function: {
        name: "write_file",
        description: "Write content to a file",
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
  
  tool_prompt = "Create an HTML file called index.html with 'Hello World' content."
  
  tool_response = client.chat_with_tools([
    {
      role: "user", 
      content: tool_prompt
    }
  ], tools)
  
  puts "Tool response type: #{tool_response.class}"
  
  if tool_response.is_a?(Hash)
    puts "Tool response keys: #{tool_response.keys.join(', ')}"
    
    if tool_response[:tool_calls]
      puts "Tool calls found: #{tool_response[:tool_calls].length}"
      tool_response[:tool_calls].each_with_index do |call, i|
        puts "  Call #{i+1} structure: #{call.keys.join(', ')}"
        if call[:function]
          puts "    Function name: #{call[:function][:name]}"
          if call[:function][:arguments]
            args_preview = call[:function][:arguments].to_s[0..100]
            puts "    Arguments preview: #{args_preview}..."
          end
        end
      end
    end
    
    if tool_response[:error]
      puts "❌ Tool error: #{tool_response[:error]}"
    end
  end
  
rescue => e
  puts "❌ Error testing OpenRouter client: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
end

# Test JSON parsing specifically
puts "\n🔍 Testing JSON parsing edge cases..."

test_jsons = [
  '{"simple": "test"}',
  '{"with_quotes": "He said \"hello\" to me"}',
  '{"multiline": "Line 1\nLine 2\nLine 3"}',
  '{"code": "const x = \"test\"; console.log(x);"}',
  '{"malformed": "This is missing a quote}'
]

test_jsons.each_with_index do |json_str, i|
  begin
    parsed = JSON.parse(json_str)
    puts "✅ Test #{i+1} parsed successfully: #{parsed.keys.join(', ')}"
  rescue JSON::ParserError => e
    puts "❌ Test #{i+1} failed: #{e.message}"
  end
end

puts "\n" + "=" * 60
puts "Diagnostic test completed"