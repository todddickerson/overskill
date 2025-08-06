#!/usr/bin/env ruby
require_relative 'config/environment'
require 'timeout'

app = App.find(35)
message = app.app_chat_messages.where(role: "user").last

puts "🚀 Starting full generation test..."
coordinator = Ai::UnifiedAiCoordinator.new(app, message)

begin
  Timeout::timeout(30) do
    puts "Executing coordinator..."
    coordinator.execute!
    puts "✅ Generation complete!"
  end
rescue Timeout::Error
  puts "⏱️ Generation timed out after 30 seconds"
  puts "Checking what was completed..."
rescue => e
  puts "❌ Error: " + e.message
  puts e.backtrace.first(3).join("\n")
end

# Check results
app.reload
puts ""
puts "📊 Final state:"
puts "  - App status: " + app.status
puts "  - Files created: " + app.app_files.count.to_s
puts "  - Versions: " + app.app_versions.count.to_s
puts "  - Assistant messages: " + app.app_chat_messages.where(role: 'assistant').count.to_s

# Check recent logs
puts ""
puts "📜 Recent UnifiedAI logs:"
system('tail -n 30 log/development.log | grep UnifiedAI | tail -10')