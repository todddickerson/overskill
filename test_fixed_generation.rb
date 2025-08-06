#!/usr/bin/env ruby
require_relative 'config/environment'

# Clean up app 35
app = App.find(35)
puts "Cleaning up app ##{app.id}..."

# Delete all messages
app.app_chat_messages.destroy_all

# Delete all files to start fresh
app.app_files.destroy_all

# Create a clean user message
message = app.app_chat_messages.create!(
  role: 'user',
  content: 'Create a simple landing page with a hero section and contact form. Use a blue color scheme.',
  user: User.first
)

puts "✅ Created clean message ##{message.id}"
puts "Content: #{message.content}"

# Now test the generation
puts "\n🚀 Testing generation with fixed services..."

coordinator = Ai::UnifiedAiCoordinator.new(app, message)

begin
  require 'timeout'
  
  Timeout::timeout(60) do
    coordinator.execute!
    puts "✅ Generation complete!"
  end
rescue Timeout::Error
  puts "⏱️ Generation timed out after 60 seconds"
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Check results
app.reload
puts "\n📊 Results:"
puts "  - Status: #{app.status}"
puts "  - Files: #{app.app_files.count}"
app.app_files.each do |f|
  puts "    • #{f.path} (#{f.size_bytes || f.content.length} bytes)"
end
puts "  - Versions: #{app.app_versions.count}"
puts "  - Messages:"
app.app_chat_messages.order(:created_at).each do |msg|
  puts "    • [#{msg.role}] #{msg.content[0..60]}..."
end

# Check recent logs
puts "\n📜 Recent UnifiedAI logs:"
system('tail -n 30 log/development.log | grep UnifiedAI | tail -15')