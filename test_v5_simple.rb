#!/usr/bin/env ruby
# Simple test for V5 without actual Claude API calls

require_relative 'config/environment'

# Monkey patch to bypass Claude API for testing
module Ai
  class AppBuilderV5
    def call_ai_with_context(prompt)
      puts "   🔍 Mock API call with prompt: #{prompt.to_s[0..100]}..."
      
      log_claude_event("MOCK_API_CALL", { prompt: prompt.to_s[0..100] })
      
      # Return a mock response
      {
        content: "Mock response for testing",
        tool_calls: [
          {
            'function' => {
              'name' => 'os-write',
              'arguments' => {
                'file_path' => 'package.json',
                'content' => '{"name": "test-app", "version": "1.0.0"}'
              }.to_json
            }
          }
        ]
      }
    end
  end
end

def test_v5_simple
  puts "\n" + "="*80
  puts "V5 SIMPLE TEST - BYPASSING CLAUDE API"
  puts "="*80
  
  # Setup
  user = User.find_by(email: 'test@overskill.app')
  team = user.teams.first
  membership = team.memberships.first
  
  # Create app
  app = team.apps.create!(
    name: "Simple Test #{Time.current.strftime('%H%M%S')}",
    status: 'planning',
    prompt: 'Test app',
    creator: membership,
    app_type: 'tool'
  )
  
  # Create message
  message = AppChatMessage.create!(
    app: app,
    user: user,
    role: 'user',
    content: 'Create a test app'
  )
  
  # Run builder
  puts "\n🚀 Running V5 Builder with mock API..."
  
  begin
    builder = Ai::AppBuilderV5.new(message)
    builder.execute!
    
    puts "\n✅ Builder completed!"
    
    # Check results
    app.reload
    puts "   App status: #{app.status}"
    puts "   Files created: #{app.app_files.count}"
    
    if app.app_files.any?
      puts "   Files:"
      app.app_files.each do |file|
        puts "     - #{file.path}"
      end
    end
    
  rescue => e
    puts "\n❌ Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
  
  puts "\n" + "="*80
end

# Run test
test_v5_simple