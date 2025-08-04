#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(18)
user = User.find(2)

puts "Creating user message..."
message = app.app_chat_messages.create!(
  role: "user",
  content: "Test message from console - change the app name to Console Test App",
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

puts "\nDone! Check the logs for job execution."