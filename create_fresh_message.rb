#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(35)

# Delete corrupted messages
puts "Deleting #{app.app_chat_messages.count} existing messages..."
app.app_chat_messages.destroy_all

# Create fresh message
message = app.app_chat_messages.create!(
  role: 'user',
  content: 'Create a simple landing page with a hero section and contact form',
  user: User.first
)

puts "✅ Created fresh message ##{message.id}"
puts "Content: #{message.content}"