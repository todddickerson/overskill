#!/usr/bin/env ruby
# Test script for dual model support (GPT-5 vs Claude Sonnet 4)
# This script tests both models with identical prompts for A/B comparison

require_relative 'config/environment'

def test_model_selection
  puts "\n" + "="*80
  puts "Testing Dual Model Support: GPT-5 vs Claude Sonnet 4"
  puts "="*80 + "\n"
  
  # Test prompt for both models
  test_prompt = "Create a simple todo app with add, delete, and mark complete functionality. Use a modern purple theme."
  
  # Test with GPT-5
  puts "\n📊 Testing GPT-5..."
  puts "-"*40
  
  test_with_model('gpt-5', test_prompt)
  
  # Test with Claude Sonnet 4
  puts "\n🧠 Testing Claude Sonnet 4..."
  puts "-"*40
  
  test_with_model('claude-sonnet-4', test_prompt)
  
  puts "\n" + "="*80
  puts "✅ Model Selection Testing Complete!"
  puts "="*80 + "\n"
end

def test_with_model(model_preference, prompt)
  begin
    # 1. Test ModelClientFactory
    puts "1. Testing ModelClientFactory..."
    client_info = Ai::ModelClientFactory.create_client(model_preference)
    puts "   ✓ Created client: #{client_info[:provider]} (#{client_info[:model]})"
    
    # 2. Test simple chat
    puts "2. Testing simple chat..."
    messages = [
      { role: 'system', content: 'You are a helpful assistant.' },
      { role: 'user', content: 'Say hello and tell me what model you are.' }
    ]
    
    response = Ai::ModelClientFactory.chat_with_model(model_preference, messages)
    if response[:success]
      puts "   ✓ Chat successful!"
      puts "   Response preview: #{response[:content][0..100]}..."
    else
      puts "   ✗ Chat failed: #{response[:error]}"
    end
    
    # 3. Test app creation simulation
    puts "3. Simulating app creation..."
    team = Team.first
    
    if team
      app = App.new(
        team: team,
        name: "Test App #{model_preference}",
        slug: "test-app-#{model_preference.gsub('_', '-')}-#{Time.now.to_i}",
        prompt: prompt,
        creator: team.memberships.first,
        base_price: 0,
        ai_model: model_preference,
        status: 'draft'
      )
      
      if app.valid?
        puts "   ✓ App validation passed with model: #{app.ai_model_name}"
        puts "   Model helpers: using_gpt5? = #{app.using_gpt5?}, using_claude? = #{app.using_claude?}"
      else
        puts "   ✗ App validation failed: #{app.errors.full_messages.join(', ')}"
      end
    else
      puts "   ⚠ No team found for testing"
    end
    
    # 4. Test V3 orchestrator integration
    puts "4. Testing V3 orchestrator integration..."
    if app && app.valid?
      app.save!
      
      # Create test message
      message = app.app_chat_messages.create!(
        role: 'user',
        content: prompt,
        user: team.memberships.first.user
      )
      
      # Initialize orchestrator
      orchestrator = Ai::AppUpdateOrchestratorV3.new(message)
      puts "   ✓ V3 orchestrator initialized with #{model_preference}"
      puts "   Provider: #{orchestrator.instance_variable_get(:@provider)}"
      puts "   Model: #{orchestrator.instance_variable_get(:@model)}"
      
      # Clean up test app
      app.destroy
    end
    
    puts "\n✅ #{model_preference} testing complete!"
    
  rescue => e
    puts "\n❌ Error testing #{model_preference}: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}"
  end
end

# Run the test
test_model_selection