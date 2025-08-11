#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 60
puts "Testing V3 Unified Orchestrator"
puts "=" * 60

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Test with each model
models = [
  { name: 'claude-sonnet-4', prompt: 'Create a task manager with categories and due dates' },
  { name: 'claude-opus-4.1', prompt: 'Build a complex SaaS platform with user management, subscription billing, and analytics dashboard' },
  { name: 'gpt-5', prompt: 'Create a simple calculator app with basic operations' }
]

models.each do |model_config|
  puts "\n" + "=" * 60
  puts "Testing with #{model_config[:name]}"
  puts "=" * 60
  
  # Create app
  app = team.apps.create!(
    creator: membership,
    name: "Test #{model_config[:name]} #{Time.current.to_i}",
    slug: "test-#{model_config[:name].gsub('.', '-')}-#{SecureRandom.hex(4)}",
    prompt: model_config[:prompt],
    app_type: "tool",
    framework: "react",
    status: "draft",
    base_price: 0,
    visibility: "private",
    ai_model: model_config[:name]
  )
  
  puts "Created app ##{app.id}: #{app.name}"
  puts "Model: #{app.ai_model}"
  
  # Create message
  message = app.app_chat_messages.create!(
    user: membership.user,
    role: 'user',
    content: model_config[:prompt]
  )
  
  puts "Created message ##{message.id}"
  
  # Test orchestrator
  begin
    orchestrator = Ai::AppUpdateOrchestratorV3Unified.new(message)
    
    # Check model selection
    puts "Selected model: #{orchestrator.instance_variable_get(:@model)}"
    puts "Provider: #{orchestrator.instance_variable_get(:@provider)}"
    
    # Quick execution test (without full generation for speed)
    puts "Orchestrator initialized successfully!"
    
    # Check configuration
    config = orchestrator.instance_variable_get(:@model_config)
    puts "Supports streaming: #{config[:supports_streaming]}"
    puts "Supports caching: #{config[:supports_caching]}" if config[:supports_caching]
    puts "Context window: #{config[:context_window]}" if config[:context_window]
    
  rescue => e
    puts "ERROR: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end

puts "\n" + "=" * 60
puts "Test completed!"
puts "=" * 60