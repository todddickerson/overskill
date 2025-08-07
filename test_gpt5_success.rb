#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🧪 Test GPT-5 Success"
puts "=" * 30

# Test with real API key
# Check for valid API key
if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'] == 'dummy-key'
  puts "Please set OPENAI_API_KEY environment variable"
  exit 1
end

begin
  gpt5_client = Ai::OpenaiGpt5Client.instance
  
  response = gpt5_client.chat([
    { role: "user", content: "Say 'GPT-5 is working'" }
  ], model: "gpt-4o")
  
  puts "Response success: #{response[:success]}"
  puts "Response content: #{response[:content]}" if response[:success]
  puts "Response error: #{response[:error]}" if response[:error]
  puts "Full response: #{response.inspect}"
  
rescue => e
  puts "Exception: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3)}"
end

puts "\n" + "=" * 30