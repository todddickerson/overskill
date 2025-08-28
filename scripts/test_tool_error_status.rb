#!/usr/bin/env ruby
# Test script to verify that tools with errors are marked as 'error' not 'complete'

require_relative '../config/environment'

puts "🧪 Testing Tool Error Status Handling"
puts "=" * 60
puts

# Find or create a test app
app = App.last || App.create!(
  user: User.first,
  name: "Tool Error Test App",
  status: "generating"
)

puts "Using app: #{app.name} (ID: #{app.id})"
puts

# Create a message with proper tools structure in conversation_flow
message = app.app_chat_messages.create!(
  user: User.first,
  content: "Test tool error handling",
  role: "user",
  conversation_flow: [
    {
      'type' => 'tools',
      'tools' => [
        {
          'name' => 'rename-app',
          'status' => 'pending',
          'args' => {}
        }
      ]
    }
  ]
)

puts "Created message ID: #{message.id}"
puts

# Create a streaming tool executor
executor = Ai::StreamingToolExecutor.new(message, app)

# Test 1: Tool that returns { success: false, error: "..." }
puts "Test 1: Testing rename-app with invalid arguments (should fail)..."
tool_call = {
  'name' => 'rename-app',
  'arguments' => {}  # Missing required 'name' argument
}

result = executor.execute_with_streaming(tool_call, 0)
puts "Result: #{result.inspect}"

# Check the conversation_flow for the tool status
message.reload
last_tool = message.conversation_flow&.reverse&.find { |item| item['type'] == 'tools' }
if last_tool && last_tool['tools']&.any?
  tool_status = last_tool['tools'].first
  puts "Tool status in conversation_flow:"
  puts "  - name: #{tool_status['name']}"
  puts "  - status: #{tool_status['status']}"
  puts "  - error: #{tool_status['error']}" if tool_status['error']
  
  if tool_status['status'] == 'error'
    puts "✅ PASS: Tool correctly marked as 'error'"
  else
    puts "❌ FAIL: Tool marked as '#{tool_status['status']}' instead of 'error'"
  end
else
  puts "❌ FAIL: No tool entry found in conversation_flow"
end

puts
puts "=" * 60

# Test 2: Tool that throws an exception
puts "Test 2: Testing with a tool that will throw an exception..."
message2 = app.app_chat_messages.create!(
  user: User.first,
  content: "Test exception handling",
  role: "user",
  conversation_flow: [
    {
      'type' => 'tools',
      'tools' => [
        {
          'name' => 'non-existent-tool',
          'status' => 'pending',
          'args' => { 'test' => 'value' }
        }
      ]
    }
  ]
)

executor2 = Ai::StreamingToolExecutor.new(message2, app)

# Try to call a non-existent tool which should trigger the rescue block
tool_call2 = {
  'name' => 'non-existent-tool',
  'arguments' => { 'test' => 'value' }
}

result2 = executor2.execute_with_streaming(tool_call2, 0)
puts "Result: #{result2.inspect}"

# Check the conversation_flow
message2.reload
last_tool2 = message2.conversation_flow&.reverse&.find { |item| item['type'] == 'tools' }
if last_tool2 && last_tool2['tools']&.any?
  tool_status2 = last_tool2['tools'].first
  puts "Tool status in conversation_flow:"
  puts "  - name: #{tool_status2['name']}"
  puts "  - status: #{tool_status2['status']}"
  puts "  - error: #{tool_status2['error']}" if tool_status2['error']
  
  if tool_status2['status'] == 'error'
    puts "✅ PASS: Exception correctly resulted in 'error' status"
  else
    puts "❌ FAIL: Tool marked as '#{tool_status2['status']}' instead of 'error'"
  end
else
  puts "❌ FAIL: No tool entry found in conversation_flow"
end

puts
puts "=" * 60
puts "📊 Test Summary:"
puts "Tools with errors should now properly show 'error' status instead of 'complete'"
puts "Check logs for [STREAMING] entries to see detailed execution flow"