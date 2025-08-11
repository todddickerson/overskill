#!/usr/bin/env ruby
# Test script for streaming integration with V3 orchestrator

require_relative 'config/environment'

def test_streaming_integration
  puts "\n" + "="*80
  puts "Testing Streaming Integration with V3 Orchestrator"
  puts "="*80 + "\n"
  
  # Test configuration
  puts "\n📊 Checking Environment:"
  puts "-"*40
  
  # Check streaming settings
  streaming_enabled = ENV['USE_STREAMING'] != 'false'
  puts "USE_STREAMING: #{streaming_enabled ? '✅ Enabled' : '❌ Disabled'}"
  
  # Check API keys
  openai_key = ENV['OPENAI_API_KEY']
  anthropic_key = ENV['ANTHROPIC_API_KEY']
  
  puts "OpenAI API Key: #{openai_key.present? ? '✅ Present' : '❌ Missing'}"
  puts "Anthropic API Key: #{anthropic_key.present? ? '✅ Present' : '❌ Missing'}"
  
  # Test V3 orchestrator initialization
  puts "\n🔧 Testing V3 Orchestrator Initialization:"
  puts "-"*40
  
  team = Team.first
  unless team
    puts "❌ No team found. Please create a team first."
    return
  end
  
  # Create test app
  app = App.create!(
    team: team,
    name: "Streaming Test App #{Time.now.to_i}",
    slug: "streaming-test-#{Time.now.to_i}",
    prompt: "Create a simple counter app",
    creator: team.memberships.first,
    base_price: 0,
    ai_model: 'gpt-5',
    status: 'draft'
  )
  
  puts "✅ Created test app ##{app.id}"
  
  # Create test message
  message = app.app_chat_messages.create!(
    role: 'user',
    content: 'Create a simple counter app with increment and decrement buttons',
    user: team.memberships.first.user
  )
  
  puts "✅ Created test message ##{message.id}"
  
  # Initialize orchestrator
  begin
    orchestrator = Ai::AppUpdateOrchestratorV3.new(message)
    
    # Check streaming configuration
    use_streaming = orchestrator.instance_variable_get(:@use_streaming)
    streaming_buffer = orchestrator.instance_variable_get(:@streaming_buffer)
    supports_streaming = orchestrator.instance_variable_get(:@supports_streaming)
    provider = orchestrator.instance_variable_get(:@provider)
    
    puts "\n📊 Orchestrator Configuration:"
    puts "  Provider: #{provider}"
    puts "  Supports Streaming: #{supports_streaming ? '✅' : '❌'}"
    puts "  Use Streaming: #{use_streaming ? '✅' : '❌'}"
    puts "  Streaming Buffer: #{streaming_buffer ? '✅ Initialized' : '❌ Not initialized'}"
    
    if streaming_buffer
      puts "\n🔄 Testing Streaming Buffer:"
      puts "-"*40
      
      # Test buffer methods
      puts "Testing start_generation..."
      streaming_buffer.start_generation
      puts "✅ start_generation called successfully"
      
      # Test chunk processing
      puts "\nTesting process_chunk..."
      test_chunk = 'data: {"choices":[{"delta":{"content":"Hello"}}]}'
      
      streaming_buffer.process_chunk(test_chunk) do |result|
        puts "✅ Chunk processed, content: #{result[:content]}"
      end
      
      puts "\n✅ Streaming buffer is functional!"
    else
      puts "\n⚠️ Streaming buffer not initialized - streaming may be disabled"
    end
    
    # Test method availability
    puts "\n🔧 Testing Streaming Methods:"
    puts "-"*40
    
    if orchestrator.respond_to?(:execute_with_streaming, true)
      puts "✅ execute_with_streaming method available"
    else
      puts "❌ execute_with_streaming method not found"
    end
    
    if orchestrator.respond_to?(:stream_openai_response, true)
      puts "✅ stream_openai_response method available"
    else
      puts "❌ stream_openai_response method not found"
    end
    
    if orchestrator.respond_to?(:stream_anthropic_response, true)
      puts "✅ stream_anthropic_response method available"
    else
      puts "❌ stream_anthropic_response method not found"
    end
    
  rescue => e
    puts "\n❌ Error initializing orchestrator: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  ensure
    # Clean up
    app.destroy if app
    puts "\n🧹 Cleaned up test app"
  end
  
  puts "\n" + "="*80
  puts "✅ Streaming Integration Testing Complete!"
  puts "="*80 + "\n"
  
  puts "\n💡 To enable streaming, set USE_STREAMING=true in your environment"
  puts "   Current status: #{ENV['USE_STREAMING'] == 'false' ? 'Disabled' : 'Enabled'}"
end

# Run the test
test_streaming_integration