#!/usr/bin/env ruby

# Test script for real-time progress messaging during AI generation
require_relative 'config/environment'

puts "=== TESTING PROGRESS MESSAGING SYSTEM ==="

# Find an existing app to test with
app = App.find(18)
puts "Testing with app: #{app.name}"

# Create a test generation record
generation = app.app_generations.create!(
  team: app.team,
  prompt: "Test progress messaging system",
  status: "pending",
  started_at: Time.current
)

puts "Created test generation: #{generation.id}"

# Test the progress messaging
service = Ai::AppGeneratorService.new(app, generation)

# Test progress message creation
puts "Creating initial progress message..."
progress_msg = service.send(:create_progress_message, "Starting test...", 0)
puts "Created message ID: #{progress_msg.id}"

# Test progress updates
[25, 50, 75, 100].each do |progress|
  sleep(1) # Simulate work
  message = "Testing progress update #{progress}%..."
  puts "Updating to: #{message}"
  service.send(:update_progress_message, progress_msg, message, progress)
end

puts "Progress messaging test complete!"
puts "Check the chat interface to see real-time updates"

# Clean up test data
generation.destroy
puts "Cleaned up test generation"