#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Testing OpenAI API Access"
puts "=" * 40

# Test with known working models
models_to_test = [
  'gpt-4o',
  'gpt-4o-mini', 
  'gpt-4-turbo',
  'gpt-4',
  'gpt-3.5-turbo'
]

gpt5_client = Ai::OpenaiGpt5Client.instance

puts "Testing with known OpenAI models:"
models_to_test.each do |model_name|
  puts "\n🧪 Testing #{model_name}:"
  
  begin
    response = gpt5_client.chat([
      { role: "user", content: "Say 'Working with #{model_name}'" }
    ], model: model_name, use_chat_api: true)
    
    if response[:success]
      puts "   ✅ SUCCESS: #{response[:content]}"
      puts "   Model confirmed working: #{model_name}"
      break # Once we find a working model, we know the API key is good
    else
      puts "   ❌ FAILED: #{response[:error]}"
    end
  rescue => e
    puts "   ❌ EXCEPTION: #{e.message}"
  end
end

# Check what the actual API endpoint is being hit
puts "\n🔍 Checking API Configuration:"
puts "   Base URL: https://api.openai.com/v1"
puts "   API Key present: #{ENV['OPENAI_API_KEY'] ? 'YES' : 'NO'}"
puts "   API Key prefix: #{ENV['OPENAI_API_KEY'] ? ENV['OPENAI_API_KEY'][0..10] + '...' : 'None'}"

puts "\n💡 Recommendation:"
puts "   If GPT-4o works, we can use it as primary model until GPT-5 is available"
puts "   This would allow tool calling to work properly"

puts "\n" + "=" * 40