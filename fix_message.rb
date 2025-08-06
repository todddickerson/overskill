#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(35)
message = app.app_chat_messages.where(role: 'user').last
message.update!(content: 'Create a simple landing page with a hero section and contact form')
puts "✅ Updated message content to: #{message.content}"