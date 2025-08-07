#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔧 Test Direct Tool Calling"
puts "=" * 40

ENV['OPENAI_API_KEY'] = "your-api-key-here"
ENV['VERBOSE_AI_LOGGING'] = 'true'

# Test simple tool calling
client = Ai::OpenRouterClient.new

# Define simple tools
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

puts "Testing tool calling..."
begin
  response = client.chat_with_tools(messages, tools, model: :gpt5)
  
  puts "Response success: #{response[:success]}"
  if response[:success]
    puts "Content: #{response[:content]}"
    puts "Tool calls present: #{response[:tool_calls] ? 'YES' : 'NO'}"
    if response[:tool_calls]
      puts "Tool calls structure:"
      response[:tool_calls].each_with_index do |tool_call, i|
        puts "  Tool call #{i}:"
        puts "    ID: #{tool_call[:id] || tool_call['id']}"
        puts "    Type: #{tool_call[:type] || tool_call['type']}"
        puts "    Function name: #{tool_call.dig(:function, :name) || tool_call.dig('function', 'name')}"
        puts "    Arguments: #{tool_call.dig(:function, :arguments) || tool_call.dig('function', 'arguments')}"
      end
    end
  else
    puts "Error: #{response[:error]}"
  end
  
rescue => e
  puts "Exception: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3)}"
end

puts "\n" + "=" * 40