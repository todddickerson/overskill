#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔍 Debug AppUpdateOrchestratorV2 - Critical Production Issue".colorize(:red)
puts "=" * 60

# Ensure OpenAI API key is configured  
unless ENV['OPENAI_API_KEY'] && ENV['OPENAI_API_KEY'] != "dummy-key"
  puts "❌ Please set OPENAI_API_KEY environment variable"
  exit 1
end

puts "✅ OpenAI API Key: #{ENV['OPENAI_API_KEY'][0..15]}...".colorize(:green)

# Use existing team
team = Team.first || Team.create!(name: "Debug Team")

user = team.memberships.first&.user || User.create!(
  email: "debug@overskill.app",
  first_name: "Debug",
  last_name: "User"
)

membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "Debug Test App",
  description: "Debugging AppUpdateOrchestratorV2",
  prompt: "Create a simple test app for debugging",
  app_type: "tool",
  framework: "react",
  base_price: 0,
  creator: membership
)

puts "📱 Created debug app: #{app.name} (ID: #{app.id})".colorize(:blue)

# Create test message
chat_message = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple counter with + and - buttons"
)

puts "💬 Created test message: #{chat_message.content}".colorize(:blue)

# Debug step by step
puts "\n🔬 DEBUGGING ORCHESTRATOR V2".colorize(:yellow)
puts "-" * 40

begin
  puts "Step 1: Initialize orchestrator...".colorize(:cyan)
  orchestrator = Ai::AppUpdateOrchestratorV2.new(chat_message)
  puts "✅ Orchestrator created successfully".colorize(:green)
  
  puts "Step 2: Check orchestrator attributes...".colorize(:cyan)
  puts "   App: #{orchestrator.app&.name || 'nil'}".colorize(:blue)
  puts "   User: #{orchestrator.user&.email || 'nil'}".colorize(:blue)
  puts "   Chat Message: #{orchestrator.chat_message&.id || 'nil'}".colorize(:blue)
  
  puts "Step 3: Check client initialization...".colorize(:cyan)
  client = orchestrator.instance_variable_get(:@client)
  puts "   Client: #{client.class.name}".colorize(:blue)
  
  # Test client directly
  puts "Step 4: Test OpenRouterClient directly...".colorize(:cyan)
  test_response = client.chat([
    { role: "user", content: "Hello, are you working?" }
  ], model: :gpt5, temperature: 1.0)
  
  if test_response[:success]
    puts "✅ OpenRouterClient working: #{test_response[:content][0..50]}...".colorize(:green)
  else
    puts "❌ OpenRouterClient failed: #{test_response[:error]}".colorize(:red)
  end
  
  puts "Step 5: Execute orchestrator with detailed logging...".colorize(:cyan)
  
  # Enable debug logging
  Rails.logger.level = Logger::DEBUG
  
  start_time = Time.current
  
  # Wrap execution with error catching
  begin
    orchestrator.execute!
    execution_time = Time.current - start_time
    puts "✅ Orchestrator execute! completed in #{execution_time.round(2)}s".colorize(:green)
  rescue => e
    execution_time = Time.current - start_time
    puts "❌ Orchestrator execute! failed in #{execution_time.round(2)}s".colorize(:red)
    puts "   Error: #{e.message}".colorize(:red)
    puts "   Backtrace:".colorize(:red)
    e.backtrace.first(10).each { |line| puts "     #{line}".colorize(:light_red) }
  end
  
  puts "Step 6: Check results...".colorize(:cyan)
  
  # Check for assistant messages
  assistant_messages = app.app_chat_messages.where(role: "assistant").order(created_at: :desc)
  puts "   Assistant messages: #{assistant_messages.count}".colorize(:blue)
  
  assistant_messages.each_with_index do |msg, i|
    puts "   Message #{i+1}: Status=#{msg.status || 'nil'}, Content=#{msg.content[0..100]}...".colorize(:light_blue)
  end
  
  # Check for created files
  files_count = app.app_files.count
  puts "   App files: #{files_count}".colorize(:blue)
  
  if files_count > 0
    app.app_files.each do |file|
      puts "     📄 #{file.path} (#{file.size_bytes} bytes)".colorize(:light_green)
    end
  end
  
rescue => e
  puts "❌ Debug failed: #{e.message}".colorize(:red)
  puts "Backtrace:".colorize(:red)
  e.backtrace.first(10).each { |line| puts "  #{line}".colorize(:light_red) }
end

puts "\n🔧 DIAGNOSIS".colorize(:yellow)
puts "-" * 40

# Check environment variables available to orchestrator
puts "Environment Check:".colorize(:cyan)
puts "  OPENAI_API_KEY: #{ENV['OPENAI_API_KEY'] ? 'SET' : 'NOT SET'}".colorize(:blue)
puts "  OPENROUTER_API_KEY: #{ENV['OPENROUTER_API_KEY'] ? 'SET' : 'NOT SET'}".colorize(:blue)
puts "  ANTHROPIC_API_KEY: #{ENV['ANTHROPIC_API_KEY'] ? 'SET' : 'NOT SET'}".colorize(:blue)

# Check Rails environment
puts "Rails Environment:".colorize(:cyan)
puts "  Environment: #{Rails.env}".colorize(:blue)
puts "  Logger level: #{Rails.logger.level}".colorize(:blue)

# Check database
puts "Database Check:".colorize(:cyan)
puts "  Teams: #{Team.count}".colorize(:blue)
puts "  Apps: #{App.count}".colorize(:blue)
puts "  Users: #{User.count}".colorize(:blue)

# Final recommendation
latest_assistant_message = app.app_chat_messages.where(role: "assistant").order(created_at: :desc).first

puts "\n💡 DIAGNOSIS RESULT".colorize(:yellow)
if latest_assistant_message&.status == "completed"
  puts "✅ AppUpdateOrchestratorV2 is working correctly".colorize(:green)
  puts "   The production test may have environment issues".colorize(:blue)
elsif latest_assistant_message&.status == "failed" 
  puts "❌ AppUpdateOrchestratorV2 is failing in execute! method".colorize(:red)
  puts "   Error: #{latest_assistant_message.content}".colorize(:red)
  puts "   🔧 Fix needed in orchestrator implementation".colorize(:yellow)
else
  puts "⚠️  AppUpdateOrchestratorV2 completed but status unclear".colorize(:yellow)
  puts "   Status: #{latest_assistant_message&.status || 'No assistant message created'}".colorize(:blue)
  puts "   🔧 May need timeout or error handling fixes".colorize(:yellow)
end

# Clean up
puts "\n🧹 Cleanup...".colorize(:blue)
app.destroy
puts "✅ Debug complete".colorize(:green)