#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🚀 Final GPT-5 Test"
puts "=" * 30

# API key check
if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'] == 'dummy-key'
  puts "Please set OPENAI_API_KEY environment variable"
  exit 1
end
ENV['VERBOSE_AI_LOGGING'] = 'true'

# Create a fresh OpenRouterClient to get the updated code
client = Ai::OpenRouterClient.new

puts "Testing GPT-5 via OpenRouterClient:"
begin
  response = client.chat([
    { role: "user", content: "Generate a simple counter app. Say 'Counter app ready!'" }
  ], model: :gpt5, temperature: 0.7)  # This should now work
  
  puts "Response: #{response.inspect}"
  puts "Success: #{response[:success] || response[:content] ? 'YES' : 'NO'}"
  puts "Content: #{response[:content]}" if response[:content]
  
rescue => e
  puts "Exception: #{e.message}"
end

puts "\n" + "=" * 30