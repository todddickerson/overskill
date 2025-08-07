#!/usr/bin/env ruby
# Check the error message details
# Run with: bin/rails runner check_error_message.rb

app = App.find(80)
puts "App: #{app.name}"

# Find the failed message
failed_msg = app.app_chat_messages.where(status: 'failed').last
if failed_msg
  puts "Failed message ID: #{failed_msg.id}"
  puts "Content: #{failed_msg.content}"
  puts "Response: #{failed_msg.response}" if failed_msg.response
else
  puts "No failed messages found"
end

puts "\nAll recent messages:"
app.app_chat_messages.order(created_at: :desc).limit(5).each do |msg|
  puts "#{msg.id}: #{msg.role} [#{msg.status}]"
  puts "  Content: #{msg.content[0..100]}..."
  puts "  Response: #{msg.response[0..100] if msg.response}..."
  puts
end