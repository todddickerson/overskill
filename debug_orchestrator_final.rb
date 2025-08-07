#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Debug AppUpdateOrchestratorV2"
puts "=" * 40

# Use test app
app = App.find(59)
message = app.app_chat_messages.last || app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple counter with increment/decrement buttons"
)

puts "Message: #{message.content}"
puts "App: #{app.name} (#{app.id})"

# Debug each step of the orchestrator  
puts "\nStep 1: Initialize Orchestrator"
begin
  orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
  puts "✅ Orchestrator initialized"
  puts "  Client: #{orchestrator.instance_variable_get(:@client).class}"
rescue => e
  puts "❌ Failed to initialize: #{e.message}"
  exit 1
end

puts "\nStep 2: Test Direct AI Client"
begin
  client = orchestrator.instance_variable_get(:@client)
  
  # Test a simple chat call first
  simple_response = client.chat([
    { role: "user", content: "Say 'Hello, this is a test'" }
  ])
  
  puts "✅ Simple chat works: #{simple_response[:success]}"
  if simple_response[:success]
    puts "  Response: #{simple_response[:content][0..100]}..."
  else
    puts "  Error: #{simple_response[:error]}"
  end
rescue => e
  puts "❌ Simple chat failed: #{e.message}"
  puts "  Backtrace: #{e.backtrace.first(3).join('\n  ')}"
end

puts "\nStep 3: Check API Keys"
puts "OPENAI_API_KEY: #{ENV['OPENAI_API_KEY'] ? 'Present' : 'Missing'}"
puts "ANTHROPIC_API_KEY: #{ENV['ANTHROPIC_API_KEY'] ? 'Present' : 'Missing'}"  
puts "OPENROUTER_API_KEY: #{ENV['OPENROUTER_API_KEY'] ? 'Present' : 'Missing'}"

puts "\n" + "=" * 40