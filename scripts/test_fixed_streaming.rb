# Test script to verify all streaming fixes

app = App.find(1560) # Using the existing test app
puts "Using App #{app.id} - #{app.name}"

# Clear any stuck jobs first
require 'sidekiq/api'
Sidekiq::Queue.new('tools').clear
Sidekiq::RetrySet.new.clear
puts "Cleared Sidekiq queues"

msg = app.app_chat_messages.create!(
  user: User.first,
  role: 'user',
  content: "Create a simple header component with the app name and a navigation menu with Home, About, and Contact links"
)

puts "Created message #{msg.id}"
raise "Message not persisted!" unless msg.persisted?
puts "Starting job..."

ProcessAppUpdateJobV5.perform_later(msg.id)

puts "\nMonitor with these commands:"
puts "1. Text streaming: tail -f log/development.log | grep -E 'V5_INCREMENTAL.*Text chunk|Added streaming text'"
puts "2. Tool execution: tail -f log/development.log | grep -E 'INCREMENTAL_DIRECT.*executing|tool.*completed'"
puts "3. Completion: tail -f log/development.log | grep -E 'INCREMENTAL_COMPLETION.*Status|All tools completed'"
puts "\nApp URL: https://dev.overskill.com/account/apps/#{app.id}/editor"