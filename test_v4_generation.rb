#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🚀 Testing V4 End-to-End Generation"
puts "==================================="

# Create test user and app
user = User.find_or_create_by(email: 'v4_test@example.com') do |u|
  u.password = 'SecureP@ssw0rd!2024'
end

team = user.teams.first || Team.create!(name: 'V4 Test Team')
team.memberships.create!(user: user, role_ids: ['admin']) unless team.memberships.where(user: user).exists?

app = App.create!(
  name: 'V4 Generation Test App',
  slug: "v4-gen-test-#{Time.now.to_i}",
  team: team,
  creator: team.memberships.first,
  prompt: 'Create a simple todo app with add, complete, and delete functionality'
)

puts "✅ Created test app: #{app.id}"

# Create initial chat message
initial_message = AppChatMessage.create!(
  app: app,
  content: 'Create a simple todo app with add, complete, and delete functionality',
  user: user,
  role: 'user'
)

puts "✅ Created initial chat message"

# Test V4 Generation
puts "\n🔄 Starting V4 Generation..."
start_time = Time.current

begin
  builder = Ai::AppBuilderV4.new(initial_message)
  builder.execute!
  
  end_time = Time.current
  generation_time = (end_time - start_time).round(2)
  
  puts "✅ V4 Generation completed in #{generation_time}s"
  
  # Check results
  app.reload
  
  puts "\n📊 Generation Results:"
  puts "   📁 Files created: #{app.app_files.count}"
  puts "   📝 App status: #{app.status}"
  
  # List some key files
  key_files = ['package.json', 'src/App.tsx', 'src/components/TodoList.tsx', 'src/pages/Dashboard.tsx']
  key_files.each do |file_path|
    file = app.app_files.find_by(path: file_path)
    if file
      puts "   ✅ #{file_path}: #{file.content.size} bytes"
    else
      puts "   ❌ #{file_path}: missing"
    end
  end
  
  # Test build if we have files
  if app.app_files.count > 5
    puts "\n🔨 Testing Build Process..."
    build_start = Time.current
    
    begin
      builder_service = Deployment::ExternalViteBuilder.new(app)
      build_result = builder_service.build_for_preview
      
      build_time = (Time.current - build_start).round(2)
      
      if build_result[:success]
        puts "✅ Build completed in #{build_time}s"
        puts "   📦 Output size: #{build_result[:size]} bytes"
        puts "   🔗 Worker created: #{build_result[:worker_size]} bytes"
      else
        puts "❌ Build failed: #{build_result[:error]}"
      end
      
    rescue => e
      puts "❌ Build error: #{e.message}"
    end
  end
  
  puts "\n🎯 V4 Generation Summary:"
  puts "   ⏱️  Total time: #{generation_time}s"
  puts "   📄 Files: #{app.app_files.count}"
  puts "   📊 Status: #{app.status}"
  puts "   🔗 Preview URL: #{app.preview_url || 'not set'}"
  
  if app.status == 'generated' && app.app_files.count >= 10
    puts "\n🎉 SUCCESS: V4 generation pipeline is working!"
  else
    puts "\n⚠️  PARTIAL SUCCESS: Generation completed but may need refinement"
  end
  
rescue => e
  puts "❌ V4 Generation failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  
  # Show any partial results
  app.reload if app
  if app && app.app_files.any?
    puts "\n📋 Partial files created: #{app.app_files.count}"
  end
end

puts "\n" + "="*50
puts "V4 End-to-End Test Complete"