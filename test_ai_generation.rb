#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🧪 Testing AI Generation with GPT-5"
puts "=" * 40

# Use existing test app 
app = App.find(59)
app.app_files.destroy_all  # Clear previous test
puts "Using app: #{app.name} (ID: #{app.id})"

# Create a message requesting a counter app
message = app.app_chat_messages.create!(
  role: "user", 
  content: "Create a simple counter app with increment, decrement, and reset buttons. Use React with useState. NO authentication, NO database, NO todos - just a simple local counter with buttons."
)

puts "Created message: #{message.content[0..80]}..."

# Test the working orchestrator
puts "\nTesting AppUpdateOrchestratorV2..."

begin
  orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
  orchestrator.execute!
  
  # Check results
  files = app.app_files.reload
  puts "\nGeneration Results:"
  puts "  Files created: #{files.count}"
  
  files.each do |file|
    puts "    - #{file.path} (#{file.size_bytes} bytes)"
  end
  
  # Analyze the main App file
  main_file = files.find { |f| f.path.include?('App') && (f.path.end_with?('.jsx') || f.path.end_with?('.tsx')) }
  
  if main_file
    content = main_file.content
    puts "\n🔍 Generated App Analysis:"
    puts "    File: #{main_file.path}"
    puts "    useState: #{content.include?('useState') ? '✅' : '❌'}"
    puts "    Counter state: #{content.match?(/useState.*count|count.*useState/i) ? '✅' : '❌'}" 
    puts "    Increment: #{content.match?(/increment|\+\+|setCount.*\+|\+.*setCount/i) ? '✅' : '❌'}"
    puts "    Decrement: #{content.match?(/decrement|--|setCount.*-|-.*setCount/i) ? '✅' : '❌'}"
    puts "    Reset: #{content.match?(/reset|setCount.*0/i) ? '✅' : '❌'}"
    puts "    No Auth: #{!content.include?('Auth') && !content.include?('supabase') ? '✅' : '❌'}"
    puts "    No Todo: #{!content.include?('todo') && !content.include?('Todo') ? '✅' : '❌'}"
    
    puts "\n📝 Generated Content Preview:"
    puts content[0..300] + "..."
  else
    puts "❌ No main app file found"
  end
  
  # Test deployment  
  if files.any?
    puts "\n🚀 Testing Deployment:"
    preview_service = Deployment::FastPreviewService.new(app)
    result = preview_service.deploy_instant_preview!
    
    puts result[:success] ? "✅ Deployed: #{result[:preview_url]}" : "❌ Deploy failed: #{result[:error]}"
  end
  
rescue => e
  puts "❌ Error during generation: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join('\n  ')}"
end

puts "\n" + "=" * 40