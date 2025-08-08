#!/usr/bin/env ruby

require 'dotenv'
Dotenv.load('.env.local', '.env.development.local', '.env.development', '.env')

require_relative 'config/environment'
require 'colorize'

puts "🧪 Testing OpenRouter Model Availability".colorize(:cyan)
puts "==" * 30

client = Ai::OpenRouterClient.new

# Test different model configurations
models_to_test = [
  { key: :gpt5, name: "GPT-5 (configured)" },
  { key: "openai/gpt-4o", name: "GPT-4o" },
  { key: "openai/gpt-4o-mini", name: "GPT-4o Mini" },
  { key: "openai/o1-preview", name: "o1 Preview" },
  { key: "openai/o1-mini", name: "o1 Mini" },
  { key: :claude_sonnet_4, name: "Claude Sonnet 4" }
]

messages = [
  {
    role: "system",
    content: "You are a helpful assistant. Answer in one sentence."
  },
  {
    role: "user",
    content: "What is 2+2?"
  }
]

models_to_test.each do |model_config|
  puts "\n📝 Testing #{model_config[:name]} (#{model_config[:key]})...".colorize(:blue)
  
  begin
    start_time = Time.current
    response = client.chat(messages, model: model_config[:key], temperature: 0.7, max_tokens: 100)
    elapsed = Time.current - start_time
    
    if response[:success]
      puts "  ✅ Success in #{elapsed.round(1)}s".colorize(:green)
      puts "     Response: #{response[:content][0..100]}...".colorize(:light_green) if response[:content]
    else
      puts "  ❌ Failed: #{response[:error]}".colorize(:red)
    end
  rescue => e
    puts "  ❌ Exception: #{e.message}".colorize(:red)
  end
end

puts "\n✨ Model test complete".colorize(:green)