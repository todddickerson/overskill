#!/usr/bin/env ruby

# Load proper environment variables first
require 'dotenv'
Dotenv.load('.env.local', '.env.development.local', '.env.development', '.env')

# Override system dummy key
ENV['OPENAI_API_KEY'] = File.read('.env.local').match(/OPENAI_API_KEY=(.+)$/)[1] rescue nil
ENV['VERBOSE_AI_LOGGING'] = 'true'

require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔬 Debug Test for V3Claude Tool Calling".colorize(:green)
puts "==" * 30

# Enable Rails logging to stdout
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = Logger::DEBUG

# Create minimal test setup
team = Team.first || Team.create!(name: "V3 Debug", billing_email: "test@example.com")
user = team.memberships.first&.user || User.first
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "V3 Debug - #{Time.current.to_i}",
  description: "Debug test",
  prompt: "Debug",
  app_type: "tool",
  framework: "react", 
  base_price: 0,
  creator: membership
)

puts "📱 Created test app: #{app.name} (ID: #{app.id})".colorize(:blue)

# Create a simple message
chat_message = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple React component that says Hello World"
)

# Run the orchestrator
puts "\n🚀 Running V3Claude orchestrator...".colorize(:cyan)

begin
  orchestrator = Ai::AppUpdateOrchestratorV3Claude.new(chat_message)
  
  # Manually test tool processing
  puts "\n📝 Testing tool processing directly...".colorize(:yellow)
  
  test_tool_call = {
    id: "test_001",
    type: "function",
    function: {
      name: "write_file",
      arguments: JSON.generate({
        path: "src/TestComponent.jsx",
        content: "export default function TestComponent() {\n  return <div>Test</div>;\n}"
      })
    }
  }
  
  puts "Tool call: #{test_tool_call.inspect}".colorize(:light_gray)
  
  result = orchestrator.send(:process_tool_call, test_tool_call)
  puts "Result: #{result.inspect}".colorize(:light_green)
  
  # Check if file was created
  if file = app.app_files.find_by(path: "src/TestComponent.jsx")
    puts "✅ File created successfully!".colorize(:green)
    puts "   Content: #{file.content[0..50]}...".colorize(:light_blue)
  else
    puts "❌ File was not created".colorize(:red)
  end
  
  # Now run the full orchestrator
  puts "\n🔧 Running full orchestration...".colorize(:cyan)
  orchestrator.execute!
  
  puts "\n📊 Files after orchestration: #{app.app_files.reload.count}".colorize(:blue)
  app.app_files.each do |file|
    puts "   📄 #{file.path} (#{file.size_bytes} bytes)".colorize(:light_blue)
  end
  
rescue => e
  puts "❌ Error: #{e.message}".colorize(:red)
  puts e.backtrace.first(10).join("\n").colorize(:light_red)
end

# Clean up
app.destroy
puts "\n✨ Debug test complete".colorize(:green)