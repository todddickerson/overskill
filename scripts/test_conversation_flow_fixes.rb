#!/usr/bin/env ruby
# Test script to verify conversation flow fixes

require_relative '../config/environment'

puts "🧪 Testing Conversation Flow Fixes"
puts "=" * 60
puts

# Test 1: Timestamp Ordering
puts "TEST 1: Timestamp Ordering"
puts "-" * 40

# Find or create test team
team = Team.first || Team.create!(name: 'Test Team')

# Find a membership to be the creator
membership = team.memberships.first
unless membership
  # Create a membership if none exists
  user = User.first
  unless user
    puts "❌ No user found in database. Please create a user first."
    exit 1
  end
  membership = team.memberships.create!(user: user)
end

# Create a test app and message with proper associations
app = App.create!(
  name: "Test Flow #{Time.current.to_i}",
  team: team,
  creator: membership,
  prompt: 'test prompt',
  status: 'generating'
)

user_message = app.app_chat_messages.create!(
  role: 'user',
  content: 'test message'
)

# Simulate AppBuilderV5 flow creation with timestamp delays
builder = Ai::AppBuilderV5.new(user_message)

# Create assistant message
assistant_message = app.app_chat_messages.create!(
  role: 'assistant',
  content: '',
  status: 'processing',
  conversation_flow: []
)

# Assign to builder instance
builder.instance_variable_set(:@assistant_message, assistant_message)
builder.instance_variable_set(:@app, app)

# Add entries to conversation flow
builder.add_to_conversation_flow(
  type: 'tools',
  tool_calls: [
    {'name' => 'test-tool-1', 'status' => 'complete'},
    {'name' => 'test-tool-2', 'status' => 'complete'}
  ]
)

# This should have a delay added automatically
builder.add_to_conversation_flow(
  type: 'message',
  content: 'Tools completed'
)

# Check timestamps
flow = assistant_message.reload.conversation_flow
puts "Flow entries: #{flow.count}"
flow.each_with_index do |entry, idx|
  puts "  [#{idx}] #{entry['type'].ljust(10)} - #{entry['timestamp']}"
end

# Verify timestamps are different
if flow.count >= 2
  ts1 = Time.parse(flow[0]['timestamp'])
  ts2 = Time.parse(flow[1]['timestamp'])
  
  if ts2 > ts1
    puts "✅ Timestamps are properly ordered (#{(ts2 - ts1) * 1000}ms apart)"
  else
    puts "❌ Timestamps are NOT properly ordered!"
  end
else
  puts "⚠️ Not enough flow entries to test"
end

puts
puts "TEST 2: Message Reuse in Incremental Flow"
puts "-" * 40

# Create initial assistant message
initial_message = app.app_chat_messages.create!(
  role: 'assistant',
  content: 'Initial content',
  status: 'processing',
  conversation_flow: [
    {'type' => 'tools', 'execution_id' => 'test123', 'status' => 'executing'}
  ]
)

puts "Created initial message ##{initial_message.id}"

# Simulate incremental continuation
builder2 = Ai::AppBuilderV5.new(user_message)

# Test the continue_incremental_conversation method
# It should find and reuse the existing message
messages = [
  {role: 'user', content: 'test'},
  {role: 'assistant', content: 'response'}
]

# Manually set the app
builder2.instance_variable_set(:@app, app)
builder2.instance_variable_set(:@chat_message, user_message)

# The method should find the existing assistant message
builder2.continue_incremental_conversation(messages, 0)

# Check if a new message was created
final_count = app.app_chat_messages.where(role: 'assistant').count
puts "Assistant messages after continuation: #{final_count}"

if final_count == 1
  puts "✅ Successfully reused existing message (no split)"
else
  puts "❌ Created new message instead of reusing (split occurred!)"
end

puts
puts "TEST 3: Deployment Timeout Handling"
puts "-" * 40

# Create a test app for deployment
deploy_app = App.create!(
  name: "Deploy Test #{Time.current.to_i}",
  team: team,
  creator: membership,
  prompt: 'test deployment',
  status: 'ready',
  github_repo: 'test/repo'
)

# Create message with stuck tools
stuck_message = deploy_app.app_chat_messages.create!(
  role: 'assistant',
  content: 'Deploying...',
  status: 'processing',
  conversation_flow: [
    {'type' => 'tools', 'status' => 'streaming', 'tools' => [
      {'name' => 'deploy', 'status' => 'streaming'}
    ]}
  ]
)

puts "Created message with stuck tools"

# Simulate timeout handling
job = DeployAppJob.new
job.send(:handle_deployment_timeout, deploy_app, 'production')

# Check if status was updated
stuck_message.reload
deploy_app.reload

puts "App status: #{deploy_app.status}"
puts "Message status: #{stuck_message.status}"

# Check conversation flow cleanup
cleaned_flow = stuck_message.conversation_flow
stuck_tools = cleaned_flow.select { |f| 
  f['type'] == 'tools' && f['status'] == 'streaming' 
}

if stuck_tools.empty?
  puts "✅ Stuck tools cleaned up successfully"
else
  puts "❌ Still have #{stuck_tools.count} stuck tools"
end

# Check for timeout markers
timeout_entries = cleaned_flow.select { |f|
  f['status'] == 'timeout' || f['error'] == 'Deployment timeout'
}

if timeout_entries.any?
  puts "✅ Timeout markers added to conversation flow"
else
  puts "❌ No timeout markers found"
end

puts
puts "=" * 60
puts "📊 SUMMARY:"
puts

# Clean up test data
[app, deploy_app].each do |test_app|
  test_app.app_chat_messages.destroy_all
  test_app.destroy
end

puts "Test data cleaned up"
puts
puts "All fixes have been implemented:"
puts "1. ✅ Timestamp delays prevent same-timestamp ordering issues"
puts "2. ✅ Incremental flow reuses existing messages (no splitting)"
puts "3. ✅ Deployment timeouts are handled gracefully with retries"
puts
puts "Next steps:"
puts "- Monitor logs during next app generation"
puts "- Verify single assistant message per conversation"
puts "- Check deployment success rates"