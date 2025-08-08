#!/usr/bin/env ruby
# Test script for unified AI generation flow

require_relative 'config/environment'

puts "Testing Unified AI Generation Flow"
puts "=" * 50

# Find or create test user
user = User.find_by(email: 'test@overskill.app') || User.create!(
  email: 'test@overskill.app',
  password: 'test123456',
  first_name: 'Test',
  last_name: 'User'
)

team = user.current_team || user.teams.first
membership = team.memberships.find_by(user: user)

puts "User: #{user.email}"
puts "Team: #{team.name}"
puts "Membership: #{membership.id}"

# Test 1: Create app via controller simulation (like from generator)
puts "\nTest 1: Creating app with prompt (simulating generator_controller)"
puts "-" * 40

app1 = team.apps.create!(
  creator: membership,
  name: "Test Counter App",
  slug: "test-counter-#{SecureRandom.hex(3)}",
  prompt: "Create a simple counter app with increment and decrement buttons",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "✓ App created: #{app1.name} (ID: #{app1.id})"
puts "✓ Status: #{app1.status}"
puts "✓ Chat messages: #{app1.app_chat_messages.count}"

# Check if generation was initiated
if app1.app_chat_messages.any?
  msg = app1.app_chat_messages.first
  puts "✓ Initial message created: #{msg.role} - #{msg.content[0..50]}..."
end

if app1.generating?
  puts "✓ App is generating (status updated correctly)"
else
  puts "✗ App status not updated to 'generating': #{app1.status}"
end

# Test 2: Manual generation trigger (like from app_editors_controller)
puts "\nTest 2: Manual generation trigger"
puts "-" * 40

app2 = team.apps.create!(
  creator: membership,
  name: "Test Todo App",
  slug: "test-todo-#{SecureRandom.hex(3)}",
  prompt: "Placeholder prompt", # Set placeholder, will be overridden by manual message
  app_type: "saas",
  framework: "react",
  status: "generated", # Mark as already generated to prevent auto-generation
  base_price: 0,
  visibility: "private"
)

puts "✓ App created without prompt: #{app2.name}"

# Manually add a message and trigger generation
message = app2.app_chat_messages.create!(
  role: "user",
  content: "Create a todo list app with add, complete, and delete functionality",
  user: user
)

puts "✓ Message created: #{message.content[0..50]}..."

# Manually trigger generation
app2.initiate_generation!

puts "✓ Generation initiated manually"
puts "✓ App status: #{app2.reload.status}"

# Test 3: Check which orchestrator is being used
puts "\nTest 3: Orchestrator Selection"
puts "-" * 40

puts "USE_V3_ORCHESTRATOR env: #{ENV['USE_V3_ORCHESTRATOR']}"
puts "USE_UNIFIED_AI env: #{ENV['USE_UNIFIED_AI']}"
puts "app1.use_v3_orchestrator?: #{app1.use_v3_orchestrator?}"
puts "app2.use_v3_orchestrator?: #{app2.use_v3_orchestrator?}"

# Summary
puts "\n" + "=" * 50
puts "Summary:"
puts "- Apps created: 2"
puts "- App 1 (with prompt): #{app1.status}"
puts "- App 2 (manual): #{app2.status}"
puts "- Both apps should be in 'generating' status"
puts "- Check Sidekiq for queued jobs"

# Check for queued jobs
if defined?(Sidekiq)
  require 'sidekiq/api'
  queue = Sidekiq::Queue.new
  puts "\nSidekiq Queue Size: #{queue.size}"
  queue.each do |job|
    if job.klass.include?('ProcessAppUpdate') || job.klass.include?('UnifiedAi')
      puts "  - #{job.klass}: #{job.args.first}"
    end
  end
end

puts "\n✓ Test complete!"