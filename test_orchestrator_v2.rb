#!/usr/bin/env ruby
# Test script for the new AI orchestrator with tool calling

require_relative 'config/environment'

def test_orchestrator_v2
  puts "\n🚀 Testing AppUpdateOrchestratorV2 with Tool Calling\n"
  puts "=" * 60
  
  # Find or create a test app
  team = Team.first || Team.create!(name: "Test Team")
  user = User.first || User.create!(email: "test@example.com", password: "password123")
  
  # Ensure user is member of team
  unless team.memberships.exists?(user: user)
    team.memberships.create!(user: user, role_ids: ["admin"])
  end
  
  # Create or find test app
  app = team.apps.find_or_create_by!(name: "Test Todo App") do |a|
    a.prompt = "A simple todo list application"
    a.app_type = "productivity"
    a.framework = "vanilla"
    a.status = "generated"
  end
  
  # Ensure app has base files
  unless app.app_files.exists?
    app.app_files.create!(
      path: "index.html",
      content: "<!DOCTYPE html><html><head><title>Todo App</title></head><body><h1>Todo List</h1></body></html>",
      file_type: "html"
    )
    
    app.app_files.create!(
      path: "app.js",
      content: "console.log('Todo app initialized');",
      file_type: "js"
    )
  end
  
  puts "\n📱 Test App Details:"
  puts "  Name: #{app.name}"
  puts "  ID: #{app.id}"
  puts "  Files: #{app.app_files.count}"
  puts ""
  
  # Test requests
  test_requests = [
    "Add a beautiful task input form with Tailwind CSS styling",
    "Make the todo list fully functional with add, edit, delete, and mark complete features",
    "Add local storage persistence so tasks are saved between sessions",
    "Create a dashboard with statistics showing total tasks, completed tasks, and pending tasks",
    "Add priority levels (high, medium, low) with color coding"
  ]
  
  puts "Select a test request:"
  test_requests.each_with_index do |req, i|
    puts "  #{i + 1}. #{req}"
  end
  puts "  6. Custom request (type your own)"
  print "\nChoice (1-6): "
  
  choice = gets.chomp.to_i
  
  request = if choice == 6
    print "Enter your custom request: "
    gets.chomp
  elsif choice >= 1 && choice <= 5
    test_requests[choice - 1]
  else
    test_requests[0]
  end
  
  puts "\n📝 Creating chat message with request:"
  puts "  \"#{request}\""
  
  # Create chat message
  chat_message = app.app_chat_messages.create!(
    user: user,
    role: "user",
    content: request
  )
  
  puts "\n🔧 Initializing OrchestratorV2..."
  
  # Test the orchestrator directly (synchronously for testing)
  begin
    orchestrator = Ai::AppUpdateOrchestratorV2.new(chat_message)
    
    # Monkey-patch to see real-time output in console
    original_broadcast = orchestrator.method(:broadcast_message_update)
    orchestrator.define_singleton_method(:broadcast_message_update) do |message|
      puts "\n📢 BROADCAST: #{message.content[0..200]}"
      original_broadcast.call(message)
    end
    
    puts "\n⚡ Executing orchestrator..."
    puts "=" * 60
    
    start_time = Time.now
    orchestrator.execute!
    elapsed = Time.now - start_time
    
    puts "\n" + "=" * 60
    puts "✅ Orchestration completed in #{elapsed.round(2)} seconds"
    
    # Show updated files
    puts "\n📁 Updated Files:"
    app.reload.app_files.each do |file|
      puts "  • #{file.path} (#{file.content.length} bytes)"
      if file.updated_at > 1.minute.ago
        puts "    Preview: #{file.content[0..100]}..."
      end
    end
    
    # Show chat messages
    puts "\n💬 Chat Messages:"
    app.app_chat_messages.where("created_at > ?", 5.minutes.ago).order(:created_at).each do |msg|
      role_emoji = msg.role == "user" ? "👤" : "🤖"
      status = msg.status ? " [#{msg.status}]" : ""
      puts "  #{role_emoji} #{msg.role}#{status}: #{msg.content[0..100]}..."
    end
    
  rescue => e
    puts "\n❌ ERROR: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
  
  puts "\n🎯 Test Complete!"
  puts "\nView the app at: http://localhost:3000/account/apps/#{app.id}/editor"
end

# Run the test
if __FILE__ == $0
  test_orchestrator_v2
end