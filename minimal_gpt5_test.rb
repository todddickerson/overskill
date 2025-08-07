#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔬 Minimal GPT-5 Test"
puts "=" * 25

ENV['OPENAI_API_KEY'] = "your-api-key-here"

# Test direct GPT-5 client with temperature 1.0
puts "Testing GPT-5 client directly..."

begin
  gpt5_client = Ai::OpenaiGpt5Client.instance
  
  response = gpt5_client.chat([
    { role: "user", content: "Say exactly: 'Direct GPT-5 working!' Then explain React useState in 10 words." }
  ], model: "gpt-5", temperature: 1.0)  # Use only supported temperature
  
  puts "Response: #{response}"
  
  if response[:content]&.include?("Direct GPT-5 working!")
    puts "✅ SUCCESS: GPT-5 responded correctly!"
  else
    puts "❌ FAILED: Unexpected response"
  end
  
rescue => e
  puts "❌ ERROR: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3).join("\n")}"
end

puts "\n" + "=" * 25