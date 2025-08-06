#!/usr/bin/env ruby
# Test the Unified AI Generation System

require_relative 'config/environment'

# Find the app
app = App.find_by(id: "bNYLke") || App.friendly.find("bNYLke") rescue nil

if app.nil?
  # Try numeric ID
  numeric_id = "bNYLke".to_i(36) # Convert from base36 if it's encoded
  app = App.find_by(id: numeric_id)
end

if app.nil?
  puts "❌ App not found with ID 'bNYLke'"
  puts "Let's find a recent app to test with:"
  
  recent_apps = App.order(created_at: :desc).limit(5)
  recent_apps.each do |a|
    puts "  - App ##{a.id}: #{a.name} (status: #{a.status})"
  end
  
  # Use the most recent app
  app = recent_apps.first
  if app
    puts "\n✅ Using App ##{app.id}: #{app.name}"
  else
    puts "❌ No apps found. Creating a test app..."
    team = Team.first
    user = User.first
    membership = team.memberships.find_by(user: user)
    
    app = App.create!(
      team: team,
      creator: membership,
      name: "Test Landing Page",
      slug: "test-landing-#{Time.now.to_i}",
      prompt: "Create a modern SaaS landing page with hero section, features, pricing, and testimonials",
      app_type: "landing_page",
      framework: "react",
      status: "draft",
      base_price: 0,
      visibility: "private"
    )
    puts "✅ Created test app ##{app.id}"
  end
end

puts "\n" + "="*60
puts "TESTING UNIFIED AI GENERATION SYSTEM"
puts "="*60
puts "\n📱 App Details:"
puts "  - ID: #{app.id}"
puts "  - Name: #{app.name}"
puts "  - Status: #{app.status}"
puts "  - Framework: #{app.framework}"
puts "  - Type: #{app.app_type}"
puts "  - Prompt: #{app.prompt[0..100]}..."
puts "  - Files: #{app.app_files.count}"
puts "  - Messages: #{app.app_chat_messages.count}"

# Check if we need to create a generation message
if app.app_chat_messages.where(role: "user").empty?
  puts "\n📝 Creating initial generation message..."
  
  user = User.first
  message = app.app_chat_messages.create!(
    role: "user",
    content: app.prompt || "Create a modern landing page with hero section, features, pricing plans, and testimonials",
    user: user
  )
  
  puts "✅ Created message ##{message.id}"
else
  message = app.app_chat_messages.where(role: "user").last
  puts "\n✅ Using existing message ##{message.id}: #{message.content[0..100]}..."
end

puts "\n🚀 Testing Unified AI Coordinator..."
puts "-" * 40

begin
  # Create the coordinator
  coordinator = Ai::UnifiedAiCoordinator.new(app, message)
  
  puts "✅ Coordinator initialized"
  puts "  - App: #{coordinator.app.name}"
  puts "  - Message: #{coordinator.message.id}"
  puts "  - TodoTracker: #{coordinator.todo_tracker.class}"
  puts "  - ProgressBroadcaster: #{coordinator.progress_broadcaster.class}"
  
  # Test the router
  puts "\n🔄 Testing Message Router..."
  router = Ai::Services::MessageRouter.new(message)
  routing = router.route
  metadata = router.extract_metadata
  
  puts "✅ Router analysis:"
  puts "  - Action: #{routing[:action]}"
  puts "  - Confidence: #{routing[:confidence]}"
  puts "  - Reasoning: #{routing[:reasoning]}"
  puts "  - Metadata: #{metadata.inspect}"
  
  # Check if we should generate or update
  if app.app_files.empty?
    puts "\n🎨 App has no files - will GENERATE new app"
  else
    puts "\n✏️ App has #{app.app_files.count} files - will UPDATE existing app"
  end
  
  # Test the execution (dry run)
  puts "\n🧪 Testing execution flow (dry run)..."
  
  # We'll mock the AI calls to avoid actual API usage
  if ENV['RUN_ACTUAL_GENERATION'] == 'true'
    puts "⚡ Running ACTUAL generation (this will use AI API)..."
    coordinator.execute!
    puts "✅ Generation complete!"
  else
    puts "📋 Simulating generation flow (no API calls)..."
    
    # Test TODO tracking
    coordinator.todo_tracker.add("Analyze requirements", type: "analysis")
    coordinator.todo_tracker.add("Create index.html", type: "file_creation", path: "index.html")
    coordinator.todo_tracker.add("Create styles.css", type: "file_creation", path: "styles.css")
    coordinator.todo_tracker.add("Create app.js", type: "file_creation", path: "app.js")
    
    puts "\n📋 TODO List:"
    puts coordinator.todo_tracker.to_markdown
    
    # Simulate progress
    coordinator.todo_tracker.todos.each do |todo|
      coordinator.todo_tracker.start(todo[:id])
      sleep(0.5)
      coordinator.todo_tracker.complete(todo[:id], "Simulated completion")
    end
    
    puts "\n✅ Simulated TODO List:"
    puts coordinator.todo_tracker.to_markdown
  end
  
  puts "\n" + "="*60
  puts "✅ UNIFIED AI SYSTEM TEST COMPLETE"
  puts "="*60
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Show recent logs
puts "\n📜 Recent AI-related logs:"
log_file = Rails.root.join('log', 'development.log')
if File.exist?(log_file)
  recent_logs = `tail -n 50 #{log_file} | grep -E '\\[UnifiedAI\\]|\\[AI\\]|\\[AppGenerator\\]' | tail -n 20`
  puts recent_logs.empty? ? "  (no recent AI logs found)" : recent_logs
end

puts "\n💡 To run actual generation with API calls, use:"
puts "  RUN_ACTUAL_GENERATION=true ruby test_unified_ai_generation.rb"
puts "\n📊 To check Sidekiq jobs:"
puts "  Sidekiq::Queue.new.size => #{Sidekiq::Queue.new.size}"
puts "  Sidekiq::RetrySet.new.size => #{Sidekiq::RetrySet.new.size}"

# Check for any pending jobs for this app
require 'sidekiq/api'
queue = Sidekiq::Queue.new
pending_jobs = queue.select { |job| 
  job.args.any? { |arg| 
    arg.is_a?(Hash) && (arg['app_id'] == app.id || arg['message_id'] == message.id)
  }
}

if pending_jobs.any?
  puts "\n⏳ Pending jobs for this app: #{pending_jobs.size}"
  pending_jobs.each do |job|
    puts "  - #{job.klass} (#{job.jid})"
  end
end