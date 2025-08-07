#!/usr/bin/env ruby

# Rails-based AI Generation Test
puts "🧪 Testing AI Generation within Rails Environment"
puts "Run this with: rails runner test_rails_generation.rb"

if defined?(Rails)
  puts "✅ Rails environment loaded"
  
  # Test OpenRouter Client
  begin
    client = Ai::OpenRouterClient.new
    puts "✅ OpenRouter client created"
    
    # Test simple chat
    messages = [
      { role: "system", content: "You are a helpful assistant." },
      { role: "user", content: "What is React in one sentence?" }
    ]
    
    response = client.chat(messages, model: :gpt5, temperature: 0.7, use_cache: false)
    
    if response[:success]
      puts "✅ GPT-5 chat successful"
      puts "  Response: #{response[:content][0..100]}..."
      puts "  Model: #{response[:model]}"
    else
      puts "❌ Chat failed: #{response[:error]}"
      puts "  Suggestion: #{response[:suggestion]}" if response[:suggestion]
    end
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end
  
else
  puts "❌ Rails environment not loaded"
  puts "Run with: rails runner test_rails_generation.rb"
end