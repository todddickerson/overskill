#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔥 Test AppUpdateOrchestratorV3 End-to-End".colorize(:green)
puts "==" * 30

# Create a simple test setup
team = Team.first || Team.create!(name: "V3 Test Team", billing_email: "test@example.com")
user = team.memberships.first&.user || User.create!(
  email: "v3-test@overskill.app", 
  first_name: "V3", 
  last_name: "Test"
)
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "V3 End-to-End Test - #{Time.current.to_i}",
  description: "End-to-end test for simplified V3 orchestrator",
  prompt: "Counter app",
  app_type: "tool",
  framework: "react", 
  base_price: 0,
  creator: membership
)

chat_message = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple counter with + and - buttons"
)

puts "📱 Created test: App #{app.id}, Message #{chat_message.id}".colorize(:blue)
puts "💬 Request: #{chat_message.content}".colorize(:yellow)
puts "🚀 Starting AppUpdateOrchestratorV3...".colorize(:cyan)

start_time = Time.current

begin
  # Test the full orchestrator
  orchestrator = Ai::AppUpdateOrchestratorV3.new(chat_message)
  orchestrator.execute!
  
  elapsed = Time.current - start_time
  puts "⏱️ Execution completed in #{elapsed.round(1)}s".colorize(:blue)
  
  # Check results
  assistant_messages = app.app_chat_messages.where(role: "assistant").order(created_at: :desc)
  files_created = app.app_files.count
  
  puts "📊 RESULTS:".colorize(:cyan)
  puts "   Assistant messages: #{assistant_messages.count}".colorize(:blue)
  puts "   Files created: #{files_created}".colorize(:blue)
  
  if assistant_messages.any?
    latest = assistant_messages.first
    puts "   Latest status: #{latest.status || 'nil'}".colorize(:blue)
    puts "   Content: #{latest.content[0..100]}...".colorize(:light_blue)
    
    if latest.status == "completed"
      puts "✅ SUCCESS: AppUpdateOrchestratorV3 completed successfully!".colorize(:green)
    else
      puts "⚠️ PARTIAL: Status #{latest.status}".colorize(:yellow)
    end
  else
    puts "❌ NO RESPONSE: No assistant messages created".colorize(:red)
  end
  
  if files_created > 0
    puts "📄 Files created:".colorize(:green)
    app.app_files.each do |file|
      puts "     #{file.path} (#{file.size_bytes} bytes)".colorize(:light_green)
    end
  end
  
rescue => e
  elapsed = Time.current - start_time
  puts "❌ EXCEPTION after #{elapsed.round(1)}s: #{e.message}".colorize(:red)
  puts "   Backtrace:".colorize(:red)
  e.backtrace.first(5).each { |line| puts "     #{line}".colorize(:light_red) }
end

# Clean up
puts "🧹 Cleanup...".colorize(:blue)
app.destroy

puts "✨ End-to-end test finished".colorize(:green)