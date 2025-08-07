#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔥 Production Flow Test - Real User Conversations".colorize(:green)
puts "=" * 60

# Ensure OpenAI API key is configured  
unless ENV['OPENAI_API_KEY'] && ENV['OPENAI_API_KEY'] != "dummy-key"
  puts "❌ Please set OPENAI_API_KEY environment variable"
  exit 1
end

def test_production_conversation(conversation_name, user_messages, initial_files = [])
  puts "\n" + "🎯 Testing: #{conversation_name}".colorize(:cyan)
  puts "-" * 40
  
  start_time = Time.current
  
  # Create test team and user
  team = Team.find_by(name: "Test Team") || Team.create!(
    name: "Test Team",
    billing_email: "test@overskill.app"
  )
  
  user = team.memberships.first&.user || User.create!(
    email: "test@overskill.app",
    first_name: "Test",
    last_name: "User"
  )
  
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])
  
  # Create test app with proper creator (Membership, not User)
  unique_name = "Test App - #{conversation_name} - #{Time.current.to_i}"
  app = team.apps.create!(
    name: unique_name,
    description: "Production flow test app",
    prompt: "Create a #{conversation_name.downcase} for testing production flow",
    app_type: "tool",
    framework: "react",
    base_price: 0,
    creator: membership
  )
  
  # Add initial files if provided
  initial_files.each do |file|
    app.app_files.create!(
      team: team,
      path: file[:path],
      content: file[:content],
      file_type: file[:type] || determine_file_type(file[:path]),
      size_bytes: file[:content].bytesize
    )
  end
  
  puts "   📱 Created app: #{app.name} (ID: #{app.id})".colorize(:blue)
  
  results = []
  conversation_quality = {
    professional_features: 0,
    code_quality: 0,
    user_experience: 0,
    total_files: 0,
    total_lines: 0
  }
  
  # Simulate real user conversation
  user_messages.each_with_index do |message_content, index|
    puts "\n   💬 User message #{index + 1}: #{message_content[0..80]}...".colorize(:yellow)
    
    # Create user message (simulating real user input)
    chat_message = app.app_chat_messages.create!(
      user: user,
      role: "user", 
      content: message_content
    )
    
    puts "   🤖 Processing with production AI system...".colorize(:light_blue)
    
    message_start = Time.current
    
    begin
      # Use the NEW AppUpdateOrchestratorV3 (GPT-5 enhanced with V2's planning)
      # This combines V2's sophisticated planning with proven GPT-5 tool calling
      orchestrator = Ai::AppUpdateOrchestratorV3.new(chat_message)
      
      puts "   🎼 Using AppUpdateOrchestratorV3 (GPT-5 enhanced with V2 planning)".colorize(:light_green)
      
      files_before = app.app_files.count
      
      # Execute with new GPT-5 enhanced orchestrator
      orchestrator.execute!
      
      message_time = Time.current - message_start
      files_after = app.app_files.count
      
      # Check if orchestrator created an assistant response
      assistant_message = app.app_chat_messages
        .where(role: "assistant")
        .where("created_at > ?", chat_message.created_at)
        .order(created_at: :desc)
        .first
      
      if assistant_message && assistant_message.status == "completed"
        puts "   ✅ AppUpdateOrchestratorV3 Success (#{message_time.round(1)}s)".colorize(:green)
        puts "   📁 Files: #{files_before} → #{files_after} (+#{files_after - files_before})".colorize(:blue)
        puts "   💬 Response: #{assistant_message.content[0..100]}...".colorize(:light_blue)
        
        # Analyze quality based on actual app changes
        quality = analyze_orchestrator_quality(app, assistant_message, files_before, files_after)
        conversation_quality[:professional_features] += quality[:professional_features]
        conversation_quality[:code_quality] += quality[:code_quality] 
        conversation_quality[:user_experience] += quality[:user_experience]
        
        results << {
          success: true,
          time: message_time,
          files_created: files_after - files_before,
          summary: assistant_message.content.lines.first&.strip || "AppUpdateOrchestratorV2 completed",
          quality: quality
        }
      else
        error_msg = assistant_message ? "AppUpdateOrchestratorV3 failed: #{assistant_message.status}" : "No assistant response created"
        puts "   ❌ #{error_msg}".colorize(:red)
        results << { success: false, error: error_msg, time: message_time }
      end
      
    rescue => e
      message_time = Time.current - message_start
      puts "   ❌ Exception: #{e.message}".colorize(:red)
      results << { success: false, error: e.message, time: message_time }
    end
  end
  
  total_time = Time.current - start_time
  
  # Final app state analysis
  final_files = app.app_files.includes(:team).to_a
  conversation_quality[:total_files] = final_files.length
  conversation_quality[:total_lines] = final_files.sum { |f| f.content.lines.count }
  
  puts "\n" + "📊 PRODUCTION CONVERSATION RESULTS".colorize(:cyan)
  puts "-" * 40
  
  successful_messages = results.count { |r| r[:success] }
  success_rate = (successful_messages.to_f / results.length * 100).round(1)
  avg_response_time = results.select { |r| r[:success] }.sum { |r| r[:time] } / [successful_messages, 1].max
  
  puts "   📈 Success Rate: #{success_rate}% (#{successful_messages}/#{results.length})".colorize(success_rate >= 80 ? :green : :red)
  puts "   ⏱️  Avg Response Time: #{avg_response_time.round(1)}s".colorize(:blue)
  puts "   🗂️  Final Files: #{conversation_quality[:total_files]}".colorize(:blue)
  puts "   📄 Total Lines: #{conversation_quality[:total_lines]}".colorize(:blue)
  puts "   🕒 Total Conversation Time: #{total_time.round(1)}s".colorize(:blue)
  
  # Quality scoring
  avg_professional = conversation_quality[:professional_features] / [results.length, 1].max
  avg_code_quality = conversation_quality[:code_quality] / [results.length, 1].max
  avg_ux = conversation_quality[:user_experience] / [results.length, 1].max
  
  overall_quality = (avg_professional + avg_code_quality + avg_ux) / 3
  
  puts "\n   🎯 PRODUCTION QUALITY ASSESSMENT:".colorize(:yellow)
  puts "   Professional Features: #{avg_professional.round(1)}/10".colorize(:blue)
  puts "   Code Quality: #{avg_code_quality.round(1)}/10".colorize(:blue) 
  puts "   User Experience: #{avg_ux.round(1)}/10".colorize(:blue)
  puts "   📊 Overall Quality: #{overall_quality.round(1)}/10".colorize(overall_quality >= 7 ? :green : :red)
  
  # Show file structure
  if final_files.any?
    puts "\n   📂 Final App Structure:".colorize(:yellow)
    final_files.each do |file|
      size_kb = (file.size_bytes / 1024.0).round(1)
      puts "   │  📄 #{file.path} (#{size_kb}KB)".colorize(:light_blue)
    end
  end
  
  # Clean up test data
  app.destroy
  
  {
    conversation: conversation_name,
    success_rate: success_rate,
    avg_response_time: avg_response_time,
    overall_quality: overall_quality,
    files_created: conversation_quality[:total_files],
    results: results
  }
end

def analyze_orchestrator_quality(app, assistant_message, files_before, files_after)
  # Quality analysis for AppUpdateOrchestratorV2 results
  all_files = app.app_files.to_a
  all_content = all_files.map(&:content).join(" ").downcase
  response_content = assistant_message.content.downcase
  
  # Professional features (0-10)
  professional_score = 0
  professional_score += 2 if all_content.include?('tailwind') || all_content.include?('class=')
  professional_score += 1 if all_content.include?('lucide') || all_content.include?('icon')
  professional_score += 2 if all_content.include?('loading') || all_content.include?('spinner')
  professional_score += 1 if all_content.include?('error') && all_content.include?('handle')
  professional_score += 2 if all_content.include?('aria-') || all_content.include?('role=')
  professional_score += 1 if response_content.include?('professional') || response_content.include?('modern')
  professional_score += 1 if all_content.include?('responsive') || all_content.include?('mobile')
  
  # Code quality (0-10)
  code_score = 0
  has_components = all_files.any? { |f| f.path.include?('components/') }
  has_proper_structure = all_files.any? { |f| f.path.include?('src/') }
  has_styles = all_files.any? { |f| f.path.include?('.css') }
  has_main_files = all_files.any? { |f| f.path.include?('main.jsx') || f.path.include?('App.jsx') }
  
  code_score += 3 if has_proper_structure
  code_score += 2 if has_components
  code_score += 2 if has_styles
  code_score += 2 if has_main_files
  code_score += 1 if all_content.include?('usestate') || all_content.include?('react')
  
  # User experience (0-10) 
  ux_score = 0
  files_created = files_after - files_before
  ux_score += 2 if files_created >= 3  # Multi-file architecture
  ux_score += 2 if response_content.include?('updated') || response_content.include?('added')
  ux_score += 2 if all_content.include?('transition') || all_content.include?('animate')
  ux_score += 2 if all_content.include?('focus') || all_content.include?('hover')
  ux_score += 1 if all_content.include?('button') && all_content.include?('click')
  ux_score += 1 if response_content.length > 100  # Detailed response
  
  {
    professional_features: [professional_score, 10].min,
    code_quality: [code_score, 10].min,
    user_experience: [ux_score, 10].min
  }
end

def determine_file_type(path)
  ext = File.extname(path).downcase.delete(".")
  case ext
  when "html", "htm" then "html"
  when "js", "jsx" then "javascript" 
  when "css", "scss" then "css"
  when "json" then "json"
  else "text"
  end
end


# Run production conversation tests
puts "🎬 Simulating Real User Conversations".colorize(:yellow)
puts "=" * 60

test_results = []

# Test 1: New user creates their first app 
result1 = test_production_conversation(
  "First-time User - Counter App",
  [
    "I want to create a simple counter app with plus and minus buttons. Make it look professional and modern."
  ]
)
test_results << result1

# Test 2: User iterates on an app
result2 = test_production_conversation(
  "Iterative Development - Todo App",
  [
    "Create a todo list app where I can add and remove items",
    "Make it look more professional with better styling",
    "Add the ability to mark items as complete with checkboxes"
  ]
)
test_results << result2

# Test 3: Complex conversation with specific requirements
result3 = test_production_conversation(
  "Advanced User - Dashboard",
  [
    "I need a dashboard for my business with charts showing sales data",
    "Add a sidebar navigation with different sections", 
    "Make it responsive so it works on mobile devices"
  ]
)
test_results << result3

# Final production quality report
puts "\n" + "=" * 60
puts "🏆 PRODUCTION SYSTEM QUALITY REPORT".colorize(:green)
puts "=" * 60

successful_conversations = test_results.count { |r| r[:success_rate] > 0 }
avg_success_rate = test_results.sum { |r| r[:success_rate] } / test_results.length
avg_quality = test_results.sum { |r| r[:overall_quality] } / test_results.length
avg_response_time = test_results.sum { |r| r[:avg_response_time] } / test_results.length
total_files = test_results.sum { |r| r[:files_created] }

puts "📊 OVERALL METRICS:".colorize(:cyan)
puts "   Successful Conversations: #{successful_conversations}/#{test_results.length} (#{(successful_conversations.to_f/test_results.length*100).round(1)}%)".colorize(:blue)
puts "   Average Success Rate: #{avg_success_rate.round(1)}%".colorize(avg_success_rate >= 80 ? :green : :red)
puts "   Average Quality Score: #{avg_quality.round(1)}/10".colorize(avg_quality >= 7 ? :green : :red)
puts "   Average Response Time: #{avg_response_time.round(1)}s".colorize(:blue)
puts "   Total Files Created: #{total_files}".colorize(:blue)

puts "\n🎯 CONVERSATION BREAKDOWN:".colorize(:yellow)
test_results.each do |result|
  status = result[:success_rate] >= 80 ? "✅" : "⚠️"
  quality_status = result[:overall_quality] >= 7 ? "🏆" : "📈"
  
  puts "   #{status} #{result[:conversation]}".colorize(:blue)
  puts "      Success: #{result[:success_rate]}% | Quality: #{result[:overall_quality].round(1)}/10 | Time: #{result[:avg_response_time].round(1)}s #{quality_status}".colorize(:light_blue)
end

# Production recommendations
puts "\n💡 PRODUCTION RECOMMENDATIONS:".colorize(:yellow)

if avg_quality < 7
  puts "   🔧 Code Quality: Focus on improving professional features and architecture".colorize(:red)
end

if avg_response_time > 45
  puts "   ⚡ Performance: Response times over 45s may impact user experience".colorize(:yellow)
end

if avg_success_rate < 90
  puts "   🛠️ Reliability: Success rate below 90% indicates system instability".colorize(:red)
end

final_grade = case avg_quality
when 9..10 then "A+ 🏆"
when 8..8.9 then "A ✅"
when 7..7.9 then "B+ 📈" 
when 6..6.9 then "B ⚠️"
else "C 🔧"
end

puts "\n🎓 PRODUCTION SYSTEM GRADE: #{final_grade}".colorize(:green)
puts "=" * 60