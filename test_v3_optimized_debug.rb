#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Testing V3 Optimized with detailed debugging..."

# Get team 8
team = Team.find(8)
membership = team.memberships.first

# Create a simple test app
app = team.apps.create!(
  creator: membership,
  name: "Debug Test #{Time.current.to_i}",
  slug: "debug-test-#{SecureRandom.hex(6)}",
  prompt: "Create a simple counter app with increment and decrement buttons",
  app_type: "tool",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "Created app ##{app.id}: #{app.name}"

# Create a chat message to trigger generation
message = app.chat_messages.create!(
  user: membership.user,
  role: 'user',
  content: "Create a counter app with increment, decrement, and reset buttons. Include a nice UI with Tailwind CSS."
)

puts "Created message ##{message.id}"

# Execute orchestrator directly with debugging
orchestrator = Ai::AppUpdateOrchestratorV3Optimized.new(message)

# Enable detailed logging
Rails.logger.level = Logger::DEBUG

puts "\n=== STARTING ORCHESTRATOR EXECUTION ==="
begin
  orchestrator.execute!
  puts "\n=== EXECUTION COMPLETED ==="
rescue => e
  puts "\n=== ERROR DURING EXECUTION ==="
  puts e.message
  puts e.backtrace.first(5).join("\n")
end

# Check what files were created
puts "\n=== FILES CREATED ==="
app.reload
app.app_files.each do |file|
  puts "  #{file.path} (#{file.content.length} bytes)"
end

if app.app_files.empty?
  puts "  NO FILES CREATED!"
end

puts "\n=== CHECKING LOGS ==="
recent_logs = `tail -n 100 log/development.log | grep -E "\\[V3-Optimized\\]" | tail -20`
puts recent_logs