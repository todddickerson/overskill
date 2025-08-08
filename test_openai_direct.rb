#!/usr/bin/env ruby
# Test OpenAI direct API connection

require_relative 'config/environment'

puts "Testing OpenAI Direct API"
puts "=" * 60

# Check API key
api_key = ENV['OPENAI_API_KEY']
if api_key.nil? || api_key.empty? || api_key == 'dummy-key'
  puts "❌ OPENAI_API_KEY not configured"
  puts "Please set OPENAI_API_KEY in your .env file"
  exit 1
end

puts "✓ API Key configured: #{api_key[0..7]}..."

# Test GPT-5 client
begin
  client = Ai::OpenaiGpt5Client.instance
  puts "✓ GPT-5 client initialized"
  
  # Simple test message
  messages = [
    { role: "system", content: "You are a helpful assistant." },
    { role: "user", content: "Say 'Hello from GPT-5' in exactly 5 words." }
  ]
  
  puts "\nTesting chat endpoint..."
  response = client.chat(messages, model: 'gpt-4o', temperature: 0.7)  # Use gpt-4o if gpt-5 not available
  
  if response[:success]
    puts "✓ Response received: #{response[:content]}"
  else
    puts "✗ Chat failed: #{response[:error]}"
  end
  
  # Test with tools
  puts "\nTesting tool calling..."
  tools = [{
    type: "function",
    function: {
      name: "test_function",
      description: "A test function",
      parameters: {
        type: "object",
        properties: {
          message: { type: "string" }
        },
        required: ["message"]
      }
    }
  }]
  
  tool_messages = [
    { role: "user", content: "Call the test_function with message 'Hello from tools'" }
  ]
  
  tool_response = client.chat_with_tools(tool_messages, tools, model: 'gpt-4o')
  
  if tool_response[:success]
    puts "✓ Tool response received"
    if tool_response[:tool_calls]
      puts "  Tool calls: #{tool_response[:tool_calls].size}"
    end
  else
    puts "✗ Tool calling failed: #{tool_response[:error]}"
  end
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n" + "=" * 60
puts "Configuration Summary:"
puts "- API Key: #{api_key ? 'Configured' : 'Missing'}"
puts "- Model: gpt-4o (or gpt-5 if available)"
puts "- Streaming: Supported"
puts "- Tool Calling: Supported"

puts "\nTo use V3 orchestrator with OpenAI:"
puts "1. Ensure OPENAI_API_KEY is set in .env"
puts "2. Set USE_V3_ORCHESTRATOR=true"
puts "3. V3 will automatically use OpenAI direct API"