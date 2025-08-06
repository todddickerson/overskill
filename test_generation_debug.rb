#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(35)
message = app.app_chat_messages.where(role: "user").last

puts "🚀 Testing generation step by step..."
puts "App: #{app.name} (##{app.id})"
puts "Message: #{message.content[0..50]}..."

puts "\n1️⃣ Creating coordinator..."
coordinator = Ai::UnifiedAiCoordinator.new(app, message)
puts "✅ Coordinator created"

puts "\n2️⃣ Testing router..."
router = Ai::Services::MessageRouter.new(message)
routing = router.route
puts "✅ Routing: #{routing.inspect}"

puts "\n3️⃣ Calling execute! with debug logging..."
Rails.logger.level = Logger::DEBUG

begin
  # Manually call the generate method to see where it fails
  if routing[:action] == :generate
    puts "Calling generate_new_app..."
    metadata = router.extract_metadata
    
    # Call the private method directly
    coordinator.send(:generate_new_app, metadata)
  else
    coordinator.execute!
  end
  
  puts "✅ Execution complete!"
rescue => e
  puts "❌ Error: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(10).join("\n")
end

# Check what happened
app.reload
puts "\n📊 Results:"
puts "  - Files: #{app.app_files.count}"
puts "  - Status: #{app.status}"

# Check the actual log file for any output
puts "\n📜 Recent logs:"
system("tail -n 20 log/development.log | tail -10")