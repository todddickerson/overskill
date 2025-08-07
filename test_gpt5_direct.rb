#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Testing GPT-5 Direct Access"
puts "=" * 40

# Test GPT-5 client initialization
puts "Step 1: GPT-5 Client Initialization"
begin
  gpt5_client = Ai::OpenaiGpt5Client.instance
  puts "✅ GPT-5 client initialized"
rescue => e
  puts "❌ GPT-5 client failed: #{e.message}"
  puts "  This means OPENAI_API_KEY might not be valid for GPT-5"
end

# Test OpenRouterClient initialization
puts "\nStep 2: OpenRouterClient Initialization"
begin
  client = Ai::OpenRouterClient.new
  gpt5_available = client.instance_variable_get(:@gpt5_client)
  puts "✅ OpenRouterClient initialized"
  puts "  GPT-5 client available: #{gpt5_available ? 'YES' : 'NO'}"
rescue => e
  puts "❌ OpenRouterClient failed: #{e.message}"
end

# Test simple GPT-5 call via OpenRouterClient
puts "\nStep 3: GPT-5 Direct Call Test"
begin
  client = Ai::OpenRouterClient.new
  
  # Force GPT-5 model
  response = client.chat([
    { role: "user", content: "Say 'GPT-5 is working' and nothing else." }
  ], model: :gpt5, use_anthropic: false)  # Disable Anthropic fallback
  
  puts "GPT-5 Response: #{response[:success] ? 'SUCCESS' : 'FAILED'}"
  if response[:success]
    puts "  Content: #{response[:content]}"
    puts "  Model used: #{response[:model] || 'Unknown'}"
  else
    puts "  Error: #{response[:error]}"
  end
rescue => e
  puts "❌ GPT-5 call failed: #{e.message}"
  puts "  #{e.backtrace.first(2).join('\n  ')}"
end

# Test tool calling specifically
puts "\nStep 4: GPT-5 Tool Calling Test"
begin
  client = Ai::OpenRouterClient.new
  
  # Simple tool test
  tools = [{
    type: "function",
    function: {
      name: "test_tool",
      description: "A simple test tool",
      parameters: {
        type: "object",
        properties: {
          message: { type: "string", description: "A test message" }
        },
        required: ["message"]
      }
    }
  }]
  
  # Force GPT-5 for tool calling
  response = client.chat_with_tools([
    { role: "user", content: "Use the test_tool with message 'hello'" }
  ], tools, model: :gpt5, use_anthropic: false)
  
  puts "GPT-5 Tool Calling: #{response[:success] ? 'SUCCESS' : 'FAILED'}"
  if response[:success]
    puts "  Response: #{response[:content][0..100]}..."
  else
    puts "  Error: #{response[:error]}"
  end
rescue => e
  puts "❌ GPT-5 tool calling failed: #{e.message}"
  puts "  #{e.backtrace.first(2).join('\n  ')}"
end

puts "\n" + "=" * 40