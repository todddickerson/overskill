#!/usr/bin/env ruby
require 'dotenv'
Dotenv.load('.env.development.local')

require_relative 'config/environment'

puts "API Key status: #{ENV['OPENROUTER_API_KEY'] ? 'Loaded' : 'Missing'}"

if ENV['OPENROUTER_API_KEY'].nil?
  puts "❌ OPENROUTER_API_KEY not found!"
  puts "Please ensure .env.development.local contains OPENROUTER_API_KEY=your_key"
  exit 1
end

# Simple API test
client = Ai::OpenRouterClient.new
puts "\nTesting API connection..."
result = client.chat([{role: 'user', content: 'Say hello'}], model: :claude_4, max_tokens: 50)

if result[:success]
  puts "✅ API working! Response: #{result[:content]}"
else
  puts "❌ API failed: #{result[:error]}"
end