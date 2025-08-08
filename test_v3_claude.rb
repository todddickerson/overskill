#!/usr/bin/env ruby

# Load proper environment variables first
require 'dotenv'
Dotenv.load('.env.local', '.env.development.local', '.env.development', '.env')

# Override system dummy key
ENV['OPENAI_API_KEY'] = File.read('.env.local').match(/OPENAI_API_KEY=(.+)$/)[1] rescue nil

require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔄 Test AppUpdateOrchestratorV3Claude (Claude Sonnet Variant)".colorize(:green)
puts "==" * 30

# Create test setup
team = Team.first || Team.create!(name: "V3 Claude Test", billing_email: "test@example.com")
user = team.memberships.first&.user || User.create!(
  email: "v3-claude@overskill.app", 
  first_name: "V3", 
  last_name: "Claude"
)
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "V3 Claude Test - #{Time.current.to_i}",
  description: "Test with Claude Sonnet",
  prompt: "Simple app",
  app_type: "tool",
  framework: "react", 
  base_price: 0,
  creator: membership
)

puts "📱 Created test app: #{app.name} (ID: #{app.id})".colorize(:blue)

# STEP 1: Create initial app
puts "\n🚀 STEP 1: Creating initial simple app with Claude...".colorize(:cyan)

chat_message1 = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple counter app with increment and decrement buttons"
)

start_time = Time.current

begin
  orchestrator = Ai::AppUpdateOrchestratorV3Claude.new(chat_message1)
  orchestrator.execute!
  
  elapsed = Time.current - start_time
  puts "✅ Initial app created in #{elapsed.round(1)}s".colorize(:green)
  
  initial_files = app.app_files.reload.count
  puts "   Files created: #{initial_files}".colorize(:blue)
  
  app.app_files.each do |file|
    puts "     📄 #{file.path} (#{file.size_bytes} bytes)".colorize(:light_blue)
  end
  
rescue => e
  elapsed = Time.current - start_time
  puts "❌ Initial creation failed after #{elapsed.round(1)}s: #{e.message}".colorize(:red)
  puts "   Backtrace:".colorize(:red)
  e.backtrace.first(3).each { |line| puts "     #{line}".colorize(:light_red) }
  app.destroy
  exit 1
end

# STEP 2: Test iterative update
puts "\n🔄 STEP 2: Testing iterative update with Claude...".colorize(:cyan)

chat_message2 = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Add a reset button that sets the counter back to zero, and make the buttons blue"
)

start_time = Time.current

begin
  orchestrator = Ai::AppUpdateOrchestratorV3Claude.new(chat_message2)
  orchestrator.execute!
  
  elapsed = Time.current - start_time
  puts "✅ Iterative update completed in #{elapsed.round(1)}s".colorize(:green)
  
  final_files = app.app_files.reload.count
  puts "📊 Files after update: #{final_files} (#{final_files - initial_files > 0 ? '+' : ''}#{final_files - initial_files})".colorize(:blue)
  
  # Check if files were actually modified
  modified_files = app.app_files.where("updated_at > ?", chat_message2.created_at)
  puts "📝 Modified files: #{modified_files.count}".colorize(:green)
  
  modified_files.each do |file|
    puts "     📄 #{file.path} (updated)".colorize(:light_green)
  end
  
  # Show a snippet of the updated content
  if main_file = app.app_files.find_by(path: "src/App.jsx")
    puts "\n📋 App.jsx snippet:".colorize(:yellow)
    puts main_file.content.lines[0..15].join.colorize(:light_gray)
  end
  
rescue => e
  elapsed = Time.current - start_time
  puts "❌ Iterative update failed after #{elapsed.round(1)}s: #{e.message}".colorize(:red)
  puts "   Backtrace:".colorize(:red)
  e.backtrace.first(5).each { |line| puts "     #{line}".colorize(:light_red) }
end

# STEP 3: Deploy preview to verify it works
puts "\n🚀 STEP 3: Deploying preview...".colorize(:cyan)

begin
  preview_service = Deployment::FastPreviewService.new(app)
  result = preview_service.deploy_instant_preview!
  
  if result[:success]
    puts "✅ Preview deployed: #{result[:preview_url]}".colorize(:green)
  else
    puts "❌ Preview deployment failed: #{result[:error]}".colorize(:red)
  end
rescue => e
  puts "❌ Preview deployment error: #{e.message}".colorize(:red)
end

# Clean up
puts "\n🧹 Cleanup...".colorize(:blue)
app.destroy

puts "✨ Claude variant test finished".colorize(:green)