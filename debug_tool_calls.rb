#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'

puts "🔍 Debug Tool Calls Structure"
puts "=" * 35

ENV['OPENAI_API_KEY'] = "your-api-key-here"

tools = [
  {
    type: "function",
    function: {
      name: "test_tool",
      description: "A simple test tool",
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
  { role: "user", content: "Use the test_tool with message 'hello world'" }
]

begin
  client = Ai::OpenRouterClient.new
  response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
  
  puts "Response success: #{response[:success]}"
  puts "Response keys: #{response.keys}"
  
  if response[:tool_calls]
    puts "Tool calls found: #{response[:tool_calls].length}"
    puts "Tool calls structure:"
    puts JSON.pretty_generate(response[:tool_calls])
    
    response[:tool_calls].each_with_index do |tool_call, i|
      puts "Tool call #{i}:"
      puts "  Type: #{tool_call.class}"
      puts "  Keys: #{tool_call.keys if tool_call.respond_to?(:keys)}"
      puts "  Content: #{tool_call.inspect}"
    end
  else
    puts "No tool calls in response"
  end
  
rescue => e
  puts "Exception: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
end

puts "\n" + "=" * 35