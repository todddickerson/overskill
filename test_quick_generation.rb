#!/usr/bin/env ruby
# Quick test of improved AI generation
# Run with: bin/rails runner test_quick_generation.rb

ENV["VERBOSE_AI_LOGGING"] = "true"

puts "=" * 60
puts "🚀 QUICK AI GENERATION TEST"
puts "=" * 60

begin
  # Use existing test setup
  team = Team.find_by(name: "AI Test Team")
  user = team&.memberships&.first&.user
  
  if !team || !user
    puts "❌ No test team found. Creating new test setup..."
    team = Team.create!(name: "AI Test Team")
    user = User.create!(
      email: "ai-test@overskill.app",
      password: "test123456",
      first_name: "AI",
      last_name: "Tester"
    )
    team.memberships.create!(user: user, role_ids: ["admin"])
  end
  
  # Create test app
  app = team.apps.create!(
    name: "Quick Test #{Time.current.to_i}",
    prompt: "Create a simple React counter app with TypeScript",
    status: 'generating',
    app_type: 'tool', 
    framework: 'react',
    creator: team.memberships.first
  )
  
  puts "✅ Created app: #{app.name} (ID: #{app.id})"
  
  # Create message and test orchestrator
  message = app.app_chat_messages.create!(
    user: user,
    role: 'user',
    content: "Create a simple React counter app with TypeScript and Tailwind CSS. Include increment, decrement, and reset buttons."
  )
  
  puts "✅ Created message: #{message.id}"
  puts "🤖 Testing AI generation with improved token allocation..."
  
  start_time = Time.current
  
  begin
    Timeout.timeout(120) do
      orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
      orchestrator.execute!
    end
    
    duration = Time.current - start_time
    app.reload
    
    puts "✅ Generation completed in #{duration.round(1)}s"
    puts "   App status: #{app.status}"
    puts "   Files created: #{app.app_files.count}"
    
    if app.app_files.any?
      puts "   Files:"
      app.app_files.limit(10).each { |f| puts "     - #{f.path}" }
    end
    
    # Check recent messages for status
    recent_messages = app.app_chat_messages.order(created_at: :desc).limit(5)
    puts "   Recent messages:"
    recent_messages.each do |msg|
      response_preview = msg.response ? msg.response[0..100] + "..." : "No response"
      puts "     #{msg.id}: #{msg.role} [#{msg.status}] - #{response_preview}"
    end
    
  rescue Timeout::Error
    puts "❌ Generation timed out after 2 minutes"
  rescue => e
    puts "❌ Generation error: #{e.message}"
  end
  
rescue => e
  puts "❌ Test error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 60
puts "Quick test completed"