#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🔍 Quick Test AppUpdateOrchestratorV3 API Access".colorize(:cyan)
puts "==" * 30

# Create a simple test setup
team = Team.first || Team.create!(name: "Quick Test Team", billing_email: "test@example.com")
user = team.memberships.first&.user || User.create!(
  email: "quick-test@overskill.app", 
  first_name: "Quick", 
  last_name: "Test"
)
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: [1])

app = team.apps.create!(
  name: "Quick Test App - #{Time.current.to_i}",
  description: "Quick test for V3 orchestrator",
  prompt: "Test app",
  app_type: "tool",
  framework: "react", 
  base_price: 0,
  creator: membership
)

chat_message = app.app_chat_messages.create!(
  user: user,
  role: "user",
  content: "Create a simple hello world button"
)

puts "📱 Created test setup: App #{app.id}, Message #{chat_message.id}".colorize(:blue)

# Test orchestrator initialization
orchestrator = Ai::AppUpdateOrchestratorV3.new(chat_message)
puts "✅ Orchestrator created successfully".colorize(:green)

# Test client access
client = orchestrator.instance_variable_get(:@client)
puts "🤖 Testing basic API connectivity...".colorize(:cyan)

# Simple test without complex prompts
simple_response = client.chat([
  { role: "user", content: "Respond with exactly: API_WORKING" }
], model: :gpt5, temperature: 1.0)

if simple_response[:success]
  puts "✅ API Access Working: #{simple_response[:content]}".colorize(:green)
  
  # Test a slightly more complex request (but not full orchestrator)
  puts "🔧 Testing JSON parsing capability...".colorize(:cyan)
  json_response = client.chat([
    { 
      role: "system",
      content: "You are a helpful assistant. Always respond with valid JSON only."
    },
    { 
      role: "user", 
      content: 'Respond with this exact JSON: {"status": "working", "message": "GPT-5 ready"}'
    }
  ], model: :gpt5, temperature: 1.0)
  
  if json_response[:success]
    begin
      parsed = JSON.parse(json_response[:content])
      puts "✅ JSON Response Working: #{parsed}".colorize(:green)
    rescue JSON::ParserError => e
      puts "⚠️  JSON Parse Issue: #{e.message}".colorize(:yellow)
      puts "   Raw response: #{json_response[:content][0..100]}...".colorize(:light_yellow)
    end
  else
    puts "❌ JSON test failed: #{json_response[:error]}".colorize(:red)
  end
  
else
  puts "❌ API Access Failed: #{simple_response[:error]}".colorize(:red)
end

# Clean up
app.destroy
puts "🧹 Cleanup complete".colorize(:blue)
puts "✨ Quick test finished".colorize(:green)