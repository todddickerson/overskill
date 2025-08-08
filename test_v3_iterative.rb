#!/usr/bin/env ruby

# Load proper environment variables first
require 'dotenv'
Dotenv.load('.env.local', '.env.development.local', '.env.development', '.env')

# Override system dummy key
ENV['OPENAI_API_KEY'] = File.read('.env.local').match(/OPENAI_API_KEY=(.+)$/)[1] rescue nil

require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔄 Test AppUpdateOrchestratorV3 Iterative Updates".colorize(:green)
puts "==" * 30

# Create test setup
team = Team.first || Team.create!(name: "V3 Iterative Test", billing_email: "test@example.com")
user = team.memberships.first&.user || User.create!(
  email: "v3-iterative@overskill.app", 
  first_name: "V3", 
  last_name: "Iterative"
)
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "V3 Iterative Test - #{Time.current.to_i}",
  description: "Test iterative updates",
  prompt: "Simple app",
  app_type: "tool",
  framework: "react", 
  base_price: 0,
  creator: membership
)

puts "📱 Created test app: #{app.name} (ID: #{app.id})".colorize(:blue)

# STEP 1: Create initial app
puts "\n🚀 STEP 1: Creating initial simple app...".colorize(:cyan)

chat_message1 = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple hello world button that shows an alert"
)

start_time = Time.current

begin
  orchestrator = Ai::AppUpdateOrchestratorV3.new(chat_message1)
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
  app.destroy
  exit 1
end

# STEP 2: Test iterative update
puts "\n🔄 STEP 2: Testing iterative update...".colorize(:cyan)

chat_message2 = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Change the button color to blue and add a counter that increments on each click"
)

start_time = Time.current

begin
  # Test with debugging to see where it gets stuck
  orchestrator = Ai::AppUpdateOrchestratorV3.new(chat_message2)
  
  puts "   🔍 Running analysis phase...".colorize(:yellow)
  analysis_result = orchestrator.send(:analyze_app_structure_gpt5)
  
  if analysis_result[:success]
    puts "   ✅ Analysis completed".colorize(:green)
    
    puts "   📝 Running planning phase...".colorize(:yellow)
    plan_result = orchestrator.send(:create_execution_plan_gpt5, analysis_result[:analysis])
    
    if plan_result[:success]
      puts "   ✅ Planning completed".colorize(:green)
      puts "      Plan: #{plan_result[:plan][:summary]}".colorize(:light_blue)
      
      puts "   🔧 Running execution phase...".colorize(:yellow)
      execution_result = orchestrator.send(:execute_with_gpt5_tools, plan_result[:plan])
      
      if execution_result[:success]
        puts "   ✅ Execution completed".colorize(:green)
      else
        puts "   ❌ Execution failed: #{execution_result[:message]}".colorize(:red)
      end
    else
      puts "   ❌ Planning failed: #{plan_result[:message]}".colorize(:red)
    end
  else
    puts "   ❌ Analysis failed: #{analysis_result[:message]}".colorize(:red)
  end
  
  elapsed = Time.current - start_time
  puts "⏱️ Iterative update completed in #{elapsed.round(1)}s".colorize(:blue)
  
  final_files = app.app_files.reload.count
  puts "📊 Files after update: #{final_files} (#{final_files - initial_files > 0 ? '+' : ''}#{final_files - initial_files})".colorize(:blue)
  
  # Check if files were actually modified
  modified_files = app.app_files.where("updated_at > ?", chat_message2.created_at)
  puts "📝 Modified files: #{modified_files.count}".colorize(:green)
  
  modified_files.each do |file|
    puts "     📄 #{file.path} (updated)".colorize(:light_green)
  end
  
rescue => e
  elapsed = Time.current - start_time
  puts "❌ Iterative update failed after #{elapsed.round(1)}s: #{e.message}".colorize(:red)
  puts "   Backtrace:".colorize(:red)
  e.backtrace.first(5).each { |line| puts "     #{line}".colorize(:light_red) }
end

# Clean up
puts "\n🧹 Cleanup...".colorize(:blue)
app.destroy

puts "✨ Iterative test finished".colorize(:green)