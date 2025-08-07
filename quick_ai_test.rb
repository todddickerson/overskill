#!/usr/bin/env ruby
require_relative 'config/environment'
require 'timeout'

puts "⚡ Quick AI Generation Test"
puts "=" * 30

# Set API key
ENV['OPENAI_API_KEY'] = "your-api-key-here"
ENV['VERBOSE_AI_LOGGING'] = 'true'

app = App.find(59)
app.app_files.destroy_all

puts "🎯 Testing: Simple counter app generation"

start_time = Time.current
success = false

begin
  Timeout::timeout(60) do # 60 second timeout
    message = app.app_chat_messages.create!(
      role: "user",
      content: "Create a minimal counter app with + and - buttons. Just the essential files please."
    )
    
    puts "🚀 Starting orchestrator..."
    orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
    result = orchestrator.execute!
    
    app.reload
    files_generated = app.app_files.count
    
    puts "📁 Files generated: #{files_generated}"
    
    if files_generated > 0
      puts "✅ SUCCESS: Files were generated"
      success = true
      
      app.app_files.each do |file|
        puts "  - #{file.path} (#{file.content.length} chars)"
        
        # Check for React patterns
        if file.content.include?("useState") || file.content.include?("React")
          puts "    ✅ Contains React patterns"
        end
      end
    else
      puts "❌ FAILURE: No files generated"
      
      # Check for errors
      error_messages = app.app_chat_messages.where(status: "failed").order(created_at: :desc).limit(3)
      error_messages.each do |msg|
        puts "❌ Error: #{msg.content[0..100]}..."
      end
    end
  end
  
rescue Timeout::Error
  puts "⏰ TIMEOUT: Test took longer than 60 seconds"
rescue => e
  puts "❌ EXCEPTION: #{e.message}"
end

elapsed = Time.current - start_time
puts "\n📊 Results:"
puts "   Success: #{success ? '✅ YES' : '❌ NO'}"
puts "   Time: #{elapsed.round(2)}s"
puts "   Files: #{app.app_files.count}"

# Check what AI model was used in the logs
recent_logs = `tail -50 log/development.log | grep -E "(GPT-5|Anthropic)" | tail -5`
if recent_logs.include?("GPT-5")
  puts "   AI Model: ✅ GPT-5"
elsif recent_logs.include?("Anthropic")
  puts "   AI Model: 🔄 Anthropic (fallback)"
else
  puts "   AI Model: ❓ Unknown"
end

puts "\n" + "=" * 30