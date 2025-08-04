#!/usr/bin/env ruby
# Test script to create a new chat message for app 18 and trigger AI orchestration

require_relative '../config/environment'

puts "🧪 Testing Enhanced AI Orchestration with App 18"
puts "=" * 60

begin
  app = App.find(18)
  puts "✅ Found app: #{app.name} (ID: #{app.id})"
  puts "   Team: #{app.team.name}"
  puts "   Current files: #{app.app_files.count}"
  
  # Get user from team
  user = app.team.memberships.first&.user
  if user.nil?
    puts "❌ No user found for team"
    exit 1
  end
  
  puts "   User: #{user.email}"
  
  # Create a sophisticated request that will test our enhanced prompts
  puts "\n📝 Creating new chat message..."
  message = app.app_chat_messages.create!(
    role: "user",
    content: "Transform this into a professional artist portfolio showcase with smooth animations, interactive gallery, and modern design. Use a sophisticated dark theme with gold accents (#d4af37). Include chart visualizations for artwork sales data.",
    user: user
  )
  
  puts "✅ Created message ##{message.id}"
  puts "   Content: #{message.content[0..100]}..."
  puts "   Status: #{message.status || 'pending'}"
  
  # Test provider selection
  puts "\n🤖 Testing provider selection..."
  provider_info = Ai::ProviderSelectorService.select_for_task(:tool_calling, user: user)
  puts "   Selected provider: #{provider_info[:provider]}"
  puts "   Reason: #{provider_info[:reason]}"
  puts "   Cost multiplier: #{provider_info[:cost_multiplier]}x"
  
  # Trigger the orchestration
  puts "\n🚀 Starting AI orchestration..."
  start_time = Time.current
  
  orchestrator = Ai::AppUpdateOrchestrator.new(message)
  orchestrator.execute!
  
  duration = Time.current - start_time
  puts "✅ Orchestration complete! (#{duration.round(2)}s)"
  
  # Check results
  message.reload
  puts "\n📊 Results:"
  puts "   Final message status: #{message.status}"
  puts "   App files after: #{app.app_files.count}"
  
  # Check for new messages
  assistant_messages = app.app_chat_messages.where(role: 'assistant').where('created_at > ?', start_time)
  puts "   Assistant messages created: #{assistant_messages.count}"
  
  assistant_messages.each_with_index do |msg, i|
    puts "   #{i+1}. Status: #{msg.status}, Content length: #{msg.content&.length || 0} chars"
    if msg.content && msg.content.length > 0
      preview = msg.content[0..200].gsub(/\n/, ' ')
      puts "      Preview: #{preview}..."
    end
  end
  
  # Check for app version
  if message.app_version
    puts "   Created app version: #{message.app_version.version_number}"
    puts "   Changed files: #{message.app_version.changed_files}"
  else
    puts "   No app version created"
  end
  
  puts "\n🎉 Test completed successfully!"
  
rescue => e
  puts "❌ Error during test: #{e.message}"
  puts "   Backtrace:"
  e.backtrace.first(10).each do |line|
    puts "     #{line}"
  end
  exit 1
end