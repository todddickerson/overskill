#!/usr/bin/env ruby
# Simple AI Generation Testing Script - Direct Rails Integration
# Run with: bin/rails runner scripts/simple_ai_test.rb

puts "=" * 80
puts "🤖 SIMPLE AI GENERATION TEST"
puts "=" * 80

# Setup test environment
puts "\n[SETUP] Preparing test environment..."
team = Team.find_by(name: "AI Test Team") || Team.create!(name: "AI Test Team")
user = User.find_by(email: "ai-test@overskill.app") || User.create!(
  email: "ai-test@overskill.app",
  password: "test123456",
  first_name: "AI",
  last_name: "Tester"
)
membership = team.memberships.find_by(user: user) || team.memberships.create!(
  user: user,
  role_ids: ["admin"]
)

puts "✅ Test team: #{team.name} (ID: #{team.id})"
puts "✅ Test user: #{user.email} (ID: #{user.id})"

# Create app
app_name = "Simple Test App #{Time.current.to_i}"
prompt = "Create a simple React todo app with user authentication using Supabase. Include:
- Login and signup pages
- Todo CRUD operations (add, edit, delete, mark complete)
- User-scoped data (each user sees only their todos)
- Modern UI with Tailwind CSS
- TypeScript for type safety"

app = team.apps.create!(
  name: app_name,
  prompt: prompt,
  status: 'generating',
  app_type: 'tool',
  framework: 'react',
  creator: membership
)

puts "\n[GENERATION] Created app: #{app.name} (ID: #{app.id})"
puts "Generating with AI..."

# Generate with AI using background job (like the real system)
begin
  AppGenerationJob.perform_now(app.id)
  app.reload
  
  puts "✅ Generation completed"
  puts "   Status: #{app.status}"
  puts "   Files: #{app.app_files.count}"
  
  # Show key files
  puts "\n📁 Key Files Created:"
  key_files = [
    "package.json",
    "src/App.tsx", 
    "src/main.tsx",
    "index.html"
  ]
  
  key_files.each do |path|
    file = app.app_files.find_by(path: path)
    status = file ? "✅" : "❌"
    puts "   #{status} #{path}"
  end
  
  # Deploy
  puts "\n🚀 Deploying app..."
  if app.status == 'generated' || app.status == 'published'
    begin
      deploy_service = Deployment::CloudflarePreviewService.new(app)
      result = deploy_service.update_preview!
      
      if result[:success]
        puts "✅ Deployment successful: #{result[:preview_url]}"
        app.update!(preview_url: result[:preview_url], status: 'published')
      else
        puts "❌ Deployment failed: #{result[:error]}"
      end
    rescue => e
      puts "❌ Deploy error: #{e.message}"
    end
  else
    puts "⚠️  App not ready for deployment (status: #{app.status})"
  end
  
  # Test chat update
  puts "\n💬 Testing chat-based update..."
  update_prompt = "Add a priority field to todos with High/Medium/Low options. Update the UI to show priority with color coding (red/yellow/green)."
  
  message = app.app_chat_messages.create!(
    user: user,
    role: 'user',
    content: update_prompt
  )
  
  puts "📝 Created update message ##{message.id}"
  
  # Process with orchestrator
  begin
    orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
    orchestrator.execute!
    
    app.reload
    puts "✅ Update processing completed"
    puts "   Files after update: #{app.app_files.count}"
    
    # Redeploy
    if app.preview_url
      puts "\n🔄 Redeploying with updates..."
      deploy_service = Deployment::CloudflarePreviewService.new(app)
      result = deploy_service.update_preview!
      puts result[:success] ? "✅ Redeploy successful" : "❌ Redeploy failed"
    end
    
  rescue => e
    puts "❌ Update error: #{e.message}"
    puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
  end
  
rescue => e
  puts "❌ Generation error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
  app.update!(status: 'failed')
end

# Final summary
puts "\n" + "=" * 80
puts "📊 TEST SUMMARY"
puts "=" * 80
puts "App ID: #{app.id}"
puts "Name: #{app.name}"
puts "Status: #{app.status}"
puts "Files: #{app.app_files.count}"
puts "Messages: #{app.app_chat_messages.count}"
puts "URL: #{app.preview_url || 'Not deployed'}"

if app.preview_url
  puts "\n🌐 REVIEW YOUR APP: #{app.preview_url}"
  puts "\n✅ Test completed successfully! The app is live and ready for review."
else
  puts "\n⚠️  App was created but deployment failed. Check the logs for details."
end

puts "\n" + "=" * 80