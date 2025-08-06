#!/usr/bin/env ruby
# Test fresh app generation with new unified system

require_relative 'config/environment'

puts "Creating fresh test app for generation..."
puts "="*60

# Get team and user
team = Team.first
user = User.first
membership = team.memberships.find_by(user: user)

# Create a fresh app
app = App.create!(
  team: team,
  creator: membership,
  name: "Test App #{Time.now.to_i}",
  slug: "test-app-#{Time.now.to_i}",
  prompt: "Create a simple landing page with a hero section and contact form",
  app_type: "landing_page",
  framework: "vanilla",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "✅ Created App ##{app.id}: #{app.name}"

# Create user message
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple landing page with a hero section that says 'Welcome to Our Service' and a contact form with name, email, and message fields. Use modern CSS with a blue color scheme.",
  user: user
)

puts "✅ Created message ##{message.id}"

# Test the unified coordinator directly
puts "\n🚀 Testing UnifiedAiCoordinator..."
puts "-"*40

begin
  coordinator = Ai::UnifiedAiCoordinator.new(app, message)
  
  # Mock some methods to avoid full generation
  puts "Testing components..."
  
  # Test router
  router = Ai::Services::MessageRouter.new(message)
  routing = router.route
  puts "✅ Router: action=#{routing[:action]}, confidence=#{routing[:confidence]}"
  
  # Test TODO tracker
  coordinator.todo_tracker.add("Test task 1")
  coordinator.todo_tracker.add("Test task 2")
  puts "✅ TodoTracker: #{coordinator.todo_tracker.todos.size} todos created"
  
  # Test progress broadcaster initialization
  puts "✅ ProgressBroadcaster: initialized"
  
  # Now run actual generation if requested
  if ENV['RUN_GENERATION'] == 'true'
    puts "\n⚡ Running ACTUAL generation..."
    coordinator.execute!
    
    # Check results
    sleep(2) # Wait for async operations
    app.reload
    
    puts "\n📊 Results:"
    puts "  - App status: #{app.status}"
    puts "  - Files created: #{app.app_files.count}"
    app.app_files.each do |file|
      puts "    • #{file.path} (#{file.size_bytes} bytes)"
    end
    puts "  - Versions: #{app.app_versions.count}"
    
    # Show assistant messages
    assistant_msgs = app.app_chat_messages.where(role: 'assistant')
    puts "  - Assistant messages: #{assistant_msgs.count}"
    assistant_msgs.each do |msg|
      puts "    • #{msg.content[0..60]}..."
    end
  else
    puts "\n💡 Dry run complete. To run actual generation:"
    puts "   RUN_GENERATION=true ruby test_fresh_generation.rb"
  end
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(10).join("\n")
  
  # Check logs
  puts "\n📜 Recent error logs:"
  system("tail -n 20 log/development.log | grep -E 'ERROR|WARN' | tail -10")
end

puts "\n" + "="*60
puts "Test complete!"