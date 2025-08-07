#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Debug OpenRouterClient GPT-5"
puts "=" * 35

ENV['OPENAI_API_KEY'] = "your-api-key-here"
ENV['VERBOSE_AI_LOGGING'] = 'true'

client = Ai::OpenRouterClient.new

# Check if GPT-5 client is available
gpt5_client = client.instance_variable_get(:@gpt5_client)
puts "GPT-5 client available: #{gpt5_client ? 'YES' : 'NO'}"

# Test with explicit model specification
puts "\nTesting OpenRouterClient with model :gpt5..."

begin
  response = client.chat([
    { role: "user", content: "Say 'OpenRouter GPT-5 success!' and stop." }
  ], model: :gpt5, temperature: 1.0)  # Use correct temperature
  
  puts "Success: #{response[:success]}"
  puts "Content: #{response[:content]}"
  puts "Model: #{response[:model]}"
  
  if response[:content]&.include?("OpenRouter GPT-5 success!")
    puts "✅ OpenRouterClient -> GPT-5 WORKING!"
  else
    puts "❌ OpenRouterClient still using fallback"
  end
  
rescue => e
  puts "❌ Exception: #{e.message}"
end

puts "\n" + "=" * 35