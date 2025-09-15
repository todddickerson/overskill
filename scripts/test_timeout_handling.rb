#!/usr/bin/env ruby
# Test script to verify timeout handling improvements

require 'securerandom'

puts "=" * 80
puts "TESTING TIMEOUT HANDLING IMPROVEMENTS"
puts "=" * 80
puts

# Find or create test user and team
user = User.first || User.create!(
  email: "test@example.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Test User"
)

team = user.teams.first || Team.create!(name: "Test Team")
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user)

# Create a new app with all required fields
app_id = SecureRandom.hex(8)
app = App.create!(
  name: "Timeout Test App #{app_id}",
  subdomain: "timeout-test-#{app_id}",
  creator: membership,
  team: team,
  prompt: "Create a simple React counter app with increment and decrement buttons",
  base_price: 0,
  status: "pending"
)

puts "✅ Created test app: #{app.name} (ID: #{app.id})"
puts

# Create a chat message to trigger app generation
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple React counter app with increment and decrement buttons"
)

puts "✅ Created user message (ID: #{message.id})"
puts

# Create assistant message to be processed
assistant_message = app.app_chat_messages.create!(
  role: "assistant", 
  content: "",
  status: "planning"
)

puts "✅ Created assistant message (ID: #{assistant_message.id})"
puts

# Trigger the app generation job
puts "🚀 Enqueueing ProcessAppUpdateJobV5..."
ProcessAppUpdateJobV5.perform_later(assistant_message.id.to_s)

puts "✅ Job enqueued"
puts

# Monitor the progress
start_time = Time.current
timeout_after = 25.minutes # Give it plenty of time
check_interval = 30.seconds

puts "⏱️  Monitoring progress (timeout after #{timeout_after.to_i / 60} minutes)..."
puts "   Checking every #{check_interval.to_i} seconds"
puts

loop do
  elapsed = Time.current - start_time
  
  # Reload the message to get latest status
  assistant_message.reload
  
  # Check conversation_flow for activity
  last_activity = nil
  if assistant_message.conversation_flow.present? && assistant_message.conversation_flow.is_a?(Array)
    last_activity = assistant_message.conversation_flow.map { |entry| 
      [entry['timestamp'], entry['updated_at'], entry['completed_at']].compact.map { |t| 
        Time.parse(t.to_s) rescue nil 
      }.compact.max
    }.compact.max
  end
  
  # Display status
  puts
  puts "=" * 60
  puts "Elapsed: #{(elapsed / 60).round(1)} minutes"
  puts "Status: #{assistant_message.status}"
  puts "Updated at: #{assistant_message.updated_at}"
  puts "Last activity in flow: #{last_activity}" if last_activity
  puts "Time since last update: #{((Time.current - assistant_message.updated_at) / 60).round(1)} minutes"
  
  # Check if completed
  if assistant_message.status == 'completed'
    puts
    puts "✅ SUCCESS! App generation completed without timeout!"
    puts "   Total time: #{(elapsed / 60).round(1)} minutes"
    
    # Check deployment status
    deployment = app.app_deployments.last
    if deployment
      puts "   Deployment status: #{deployment.status}"
      puts "   Preview URL: #{deployment.preview_url}" if deployment.preview_url
    end
    
    break
  end
  
  # Check if failed
  if assistant_message.status == 'failed'
    puts
    puts "❌ FAILED! Message marked as failed"
    puts "   Content: #{assistant_message.content}"
    puts "   Response: #{assistant_message.response}"
    
    # Check if it was a timeout failure
    if assistant_message.content&.include?("timed out") || assistant_message.response&.include?("timeout")
      puts
      puts "⚠️  This appears to be a timeout failure!"
      puts "   The timeout handling improvements may not be working correctly."
    end
    
    break
  end
  
  # Check if we've exceeded our monitoring timeout
  if elapsed > timeout_after
    puts
    puts "⏰ Monitoring timeout reached (#{timeout_after.to_i / 60} minutes)"
    puts "   Final status: #{assistant_message.status}"
    break
  end
  
  # Check for stuck state (no updates for 20+ minutes)
  time_since_update = (Time.current - assistant_message.updated_at) / 60
  if time_since_update > 20
    puts
    puts "⚠️  WARNING: No updates for #{time_since_update.round(1)} minutes"
    puts "   Message may be stuck or about to be cleaned up"
    
    # Check if CleanupStuckMessagesJob would clean this up
    if time_since_update > 20 && (!last_activity || (Time.current - last_activity) > 15.minutes)
      puts "   🔴 CleanupStuckMessagesJob would mark this as failed!"
    end
  end
  
  # Wait before next check
  sleep check_interval
end

puts
puts "=" * 80
puts "TEST COMPLETE"
puts "=" * 80
puts

# Final summary
puts "App ID: #{app.id}"
puts "Final message status: #{assistant_message.reload.status}"
puts "App files created: #{app.app_files.count}"
puts "Deployments: #{app.app_deployments.count}"

if app.app_deployments.any?
  latest_deployment = app.app_deployments.last
  puts
  puts "Latest deployment:"
  puts "  Status: #{latest_deployment.status}"
  puts "  Environment: #{latest_deployment.environment}"
  puts "  Preview URL: #{latest_deployment.preview_url}"
  puts "  Created: #{latest_deployment.created_at}"
  puts "  Updated: #{latest_deployment.updated_at}"
end