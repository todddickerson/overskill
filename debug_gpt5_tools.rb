#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'

puts "🔍 Debug GPT-5 Tool Calls"
puts "=" * 30

# Check if OpenAI API key is set
if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'].empty?
  puts "❌ OPENAI_API_KEY not set in environment"
  exit 1
end

puts "✅ OpenAI API Key found: #{ENV['OPENAI_API_KEY'][0..15]}..."
ENV['VERBOSE_AI_LOGGING'] = 'true'

# Test GPT-5 directly
gpt5_client = Ai::OpenaiGpt5Client.instance

tools = [
  {
    type: "function",
    function: {
      name: "test_function",
      description: "A simple test function",
      parameters: {
        type: "object",
        properties: {
          message: { type: "string", description: "Test message" }
        },
        required: ["message"]
      }
    }
  }
]

messages = [
  { role: "user", content: "Use the test_function with message 'hello world'" }
]

puts "Testing GPT-5 client directly..."

begin
  response = gpt5_client.chat_with_tools(messages, tools, model: 'gpt-5', temperature: 1.0)
  
  puts "Response keys: #{response.keys}"
  puts "Success: #{response[:success]}"
  puts "Content: #{response[:content]}"
  puts "Tool calls: #{response[:tool_calls]&.length || 0}"
  
  if response[:tool_calls]
    puts "Tool call structure:"
    response[:tool_calls].each_with_index do |tool_call, i|
      puts "  Tool #{i}: #{tool_call.inspect}"
    end
  end
  
rescue => e
  puts "Exception: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5)
end

puts "\n" + "=" * 30