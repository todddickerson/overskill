#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(18)
user = User.find(2)

# Update the stuck message to failed
stuck_msg = AppChatMessage.find(68)
stuck_msg.update!(status: "failed", content: "Request failed due to system error. Please try again.")
puts "Updated stuck message to failed status"

puts "\nCreating new test message..."
message = app.app_chat_messages.create!(
  role: "user",
  content: "Simple test - just add a comment to the main file saying 'Updated by AI'",
  user: user
)
puts "User message created with ID: #{message.id}"

puts "Creating AI placeholder..."
ai_response = app.app_chat_messages.create!(
  role: "assistant",
  content: "Analyzing your request and planning the changes...",
  status: "planning"
)
puts "AI placeholder created with ID: #{ai_response.id}"

puts "Enqueuing ProcessAppUpdateJob..."
job = ProcessAppUpdateJob.perform_later(message)
puts "Job enqueued with ID: #{job.job_id}"

puts "\nMonitoring job for 10 seconds..."
10.times do |i|
  sleep 1
  ai_response.reload
  puts "#{i+1}s - Status: #{ai_response.status}"
  break if ai_response.status == "completed" || ai_response.status == "failed"
end

puts "\nFinal status: #{ai_response.status}"
puts "Content: #{ai_response.content[0..100]}..."