#!/usr/bin/env ruby
# Simple test of AI API connectivity

require_relative 'config/environment'

puts "Testing AI API connectivity..."
puts "="*60

client = Ai::OpenRouterClient.new

# Test with a simple message
messages = [
  { role: "user", content: "Say 'Hello World' and nothing else" }
]

puts "\n🔄 Testing basic chat..."
result = client.chat(messages, model: :claude_sonnet, temperature: 0.1, max_tokens: 100)

if result[:success]
  puts "✅ API call successful!"
  puts "Response: #{result[:content]}"
else
  puts "❌ API call failed!"
  puts "Error: #{result[:error]}"
end

puts "\n🔄 Testing with function calling..."
tools = [
  {
    type: "function",
    function: {
      name: "test_function",
      description: "A test function",
      parameters: {
        type: "object",
        properties: {
          message: { type: "string", description: "A test message" }
        }
      }
    }
  }
]

result = client.chat_with_tools(messages, tools, model: :claude_sonnet, temperature: 0.1, max_tokens: 100)

if result[:success]
  puts "✅ Function calling API successful!"
  puts "Tool calls: #{result[:tool_calls]&.any? ? 'Yes' : 'No'}"
else
  puts "❌ Function calling failed!"
  puts "Error: #{result[:error]}"
end

puts "\n" + "="*60
puts "Test complete!"