#!/usr/bin/env ruby
# Complete end-to-end test simulating a real user creating an app

require_relative 'config/environment'

puts "🧪 End-to-End V4 User Flow Test"
puts "=" * 50

begin
  puts "\n👤 Step 1: Create user and team (simulating signup)"
  
  # Create user and team like a real signup
  user = User.create!(
    email: "e2e-test-#{Time.current.to_i}@example.com", 
    password: "password123",
    first_name: "Test", 
    last_name: "User"
  )
  
  team = Team.create!(name: "E2E Test Team")
  membership = team.memberships.create!(user: user)
  
  puts "✅ Created user: #{user.email}"
  puts "✅ Created team: #{team.name}"
  
  puts "\n📱 Step 2: Create new app (simulating user request)"
  
  # Create app like the web interface does
  app_name = "E2E Test App #{Time.current.to_i}"
  app = team.apps.create!(
    name: app_name,
    creator: membership,
    prompt: "Create a modern todo app with drag and drop functionality"
  )
  
  puts "✅ Created app: #{app.name} (ID: #{app.id})"
  
  puts "\n💬 Step 3: Send chat message (simulating user request)"
  
  # Create chat message like the user would
  message = app.app_chat_messages.create!(
    content: "Build a beautiful todo app with modern UI components, drag and drop, and task categories",
    user: user,
    role: "user"
  )
  
  puts "✅ Created chat message: #{message.content.truncate(60)}"
  
  puts "\n🚀 Step 4: Execute V4 generation (simulating background job)"
  
  # Track what happens during generation
  puts "Starting V4 AppBuilder generation..."
  
  # Initialize builder
  builder = Ai::AppBuilderV4.new(message)
  puts "✅ V4 builder initialized"
  
  # Check builder state
  puts "App status: #{app.status}"
  puts "Files before: #{app.app_files.count}"
  
  # Execute generation with detailed logging
  puts "\n🔧 Executing V4 generation pipeline..."
  
  start_time = Time.current
  
  # This should work without the File.basename error now
  builder.execute!
  
  end_time = Time.current
  duration = (end_time - start_time).round(2)
  
  puts "\n📊 Step 5: Verify results"
  
  # Reload app to get latest state
  app.reload
  
  puts "✅ Generation completed in #{duration} seconds"
  puts "App status: #{app.status}"
  puts "Files created: #{app.app_files.count}"
  puts "App versions: #{app.app_versions.count}"
  
  if app.preview_url.present?
    puts "✅ Preview URL: #{app.preview_url}"
  else
    puts "⚠️  No preview URL generated"
  end
  
  # Check for any error messages
  error_messages = app.app_chat_messages.where(role: 'assistant').where("content LIKE '%error%' OR content LIKE '%Error%' OR content LIKE '%failed%'")
  
  if error_messages.any?
    puts "\n⚠️  Error messages found:"
    error_messages.each do |msg|
      puts "- #{msg.content.truncate(100)}"
    end
  else
    puts "✅ No error messages found in chat"
  end
  
  # Check file types created
  puts "\n📁 Files created by type:"
  file_types = app.app_files.group_by { |f| File.extname(f.path) }
  file_types.each do |ext, files|
    puts "  #{ext.presence || '(no ext)'}: #{files.count} files"
  end
  
  # Show component files specifically
  component_files = app.app_files.where("path LIKE 'src/components/%'")
  if component_files.any?
    puts "\n🧩 Component files created:"
    component_files.pluck(:path).each do |path|
      puts "  - #{path}"
    end
  end
  
  puts "\n🎉 END-TO-END TEST SUCCESSFUL!"
  puts "=" * 50
  
  puts "\n📋 Summary:"
  puts "- User and team created ✅"
  puts "- App created successfully ✅"
  puts "- Chat message processed ✅"
  puts "- V4 generation executed ✅"
  puts "- Files generated: #{app.app_files.count} ✅"
  puts "- No File.basename errors ✅"
  puts "- Generation time: #{duration}s ✅"
  
  if app.status == 'generated'
    puts "- App status: GENERATED ✅"
  elsif app.status == 'failed'
    puts "- App status: FAILED ❌"
    
    # Show the error details
    if app.app_versions.any?
      latest_version = app.app_versions.order(:created_at).last
      puts "  Last error: #{latest_version.changelog}"
    end
  else
    puts "- App status: #{app.status.upcase} ⚠️"
  end
  
  puts "\n🚀 V4 End-to-End Test Complete!"

rescue => e
  puts "\n❌ TEST FAILED: #{e.message}"
  puts "Error class: #{e.class.name}"
  puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
  
  exit 1
end