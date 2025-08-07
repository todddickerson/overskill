#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Testing AppUpdateOrchestratorV2 Direct"
puts "=" * 50

# Set API key for GPT-5 to work
# Validate API key
if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'] == 'dummy-key'
  puts "Please set OPENAI_API_KEY environment variable"
  exit 1
end

# Use test app
app = App.find(59)
app.app_files.destroy_all

# Create fresh message
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple counter app with increment and decrement buttons. Use React with useState."
)

puts "App: #{app.name} (#{app.id})"
puts "Message: #{message.content}"

# Test orchestrator with detailed logging
puts "\n🚀 Starting Orchestrator..."
begin
  Rails.logger.level = Logger::DEBUG if ENV['VERBOSE_AI_LOGGING']
  
  orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
  puts "✅ Orchestrator initialized"
  
  # Call execute! and catch any errors
  puts "\n📋 Executing orchestrator..."
  begin
    result = orchestrator.execute!
    puts "✅ Orchestrator completed"
    puts "Result: #{result.inspect}" if result
  rescue => e
    puts "💥 Exception details:"
    puts "Message: #{e.message}"
    puts "Backtrace:"
    puts e.backtrace.first(10).join("\n  ")
  end
  
  # Check results
  files = app.app_files.reload
  puts "\n📁 Generated Files: #{files.count}"
  
  if files.any?
    files.each do |file|
      puts "  - #{file.path} (#{file.size_bytes} bytes)"
    end
    
    # Check for counter functionality
    main_file = files.find { |f| f.path.include?('App') }
    if main_file
      content = main_file.content
      puts "\n🔍 Counter Check:"
      puts "  - useState: #{content.include?('useState') ? '✅' : '❌'}"
      puts "  - increment: #{content.match?(/increment|setCount.*\+/) ? '✅' : '❌'}"
      puts "  - decrement: #{content.match?(/decrement|setCount.*-/) ? '✅' : '❌'}"
    end
  else
    puts "❌ No files generated"
    
    # Check for error messages
    error_messages = app.app_chat_messages.where(role: "assistant", status: "failed")
    if error_messages.any?
      puts "\n🚨 Error Messages:"
      error_messages.each do |msg|
        puts "  - #{msg.content[0..100]}..."
      end
    end
  end

rescue => e
  puts "❌ Exception during orchestration: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n  ")
end

puts "\n" + "=" * 50