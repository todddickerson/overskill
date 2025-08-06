#!/usr/bin/env ruby
require_relative 'config/environment'

# Debug test of generation
puts "\n=== Debug Test ==="

puts "1. Creating client..."
client = Ai::OpenRouterClient.new

puts "2. Testing simple message..."
result = client.chat(
  [{role: "user", content: "Say hello"}],
  model: :kimi_k2,
  max_tokens: 10
)
puts "Result: #{result[:success] ? 'Success' : 'Failed'}"

puts "\n3. Testing with JSON request..."
prompt = "Return this JSON: {\"test\": \"hello\"}"
result = client.chat(
  [{role: "user", content: prompt}],
  model: :kimi_k2,
  max_tokens: 100
)
puts "Result: #{result[:success] ? 'Success' : 'Failed'}"
puts "Content: #{result[:content]}"

puts "\n4. Loading standards file..."
standards_path = Rails.root.join('AI_GENERATED_APP_STANDARDS.md')
if File.exist?(standards_path)
  standards = File.read(standards_path)
  puts "Standards loaded: #{standards.size} bytes"
else
  puts "Standards file not found!"
end

puts "\nDone!"