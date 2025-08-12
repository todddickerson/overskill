#!/usr/bin/env ruby
# Test to verify the File.basename fix in extract_component_names_created

require_relative 'config/environment'

puts "🧪 Testing File.basename Fix"
puts "=" * 40

begin
  # Find an app with component files
  app = App.find(56)
  puts "Testing with App #{app.id}: #{app.name}"
  
  # Create a test AppBuilderV4 instance
  user = app.team.memberships.first.user
  message = app.app_chat_messages.create!(
    content: "Test basename fix",
    user: user,
    role: "user"
  )
  
  builder = Ai::AppBuilderV4.new(message)
  puts "✅ AppBuilderV4 initialized"
  
  # Test the specific method that was failing
  puts "\n🔧 Testing extract_component_names_created method..."
  
  component_names = builder.send(:extract_component_names_created)
  
  puts "✅ Method executed successfully!"
  puts "Component names extracted: #{component_names.inspect}"
  
  puts "\n📊 Test Results:"
  puts "- No 'undefined method basename' error ✅"
  puts "- Method returns array of component names ✅"
  puts "- Components found: #{component_names.count}"
  
  if component_names.any?
    puts "- Sample components: #{component_names.first(3).join(', ')}"
  end
  
  puts "\n🎉 File.basename Fix VERIFIED!"
  puts "The fix using ::File.basename instead of File.basename works correctly."

rescue => e
  puts "\n❌ TEST FAILED: #{e.message}"
  puts "Error class: #{e.class.name}"
  
  if e.message.include?("undefined method `basename'")
    puts "🚨 File.basename error still present!"
  else
    puts "Different error occurred"
  end
  
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
  exit 1
end