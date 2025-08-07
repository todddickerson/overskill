#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Testing GPT-5 Model Variants"
puts "=" * 50

# Test each GPT-5 variant from the docs
variants = {
  'gpt-5' => 'Complex reasoning, broad world knowledge',
  'gpt-5-mini' => 'Cost-optimized reasoning and chat', 
  'gpt-5-nano' => 'High-throughput tasks'
}

gpt5_client = Ai::OpenaiGpt5Client.instance

variants.each do |model_name, description|
  puts "\n🧪 Testing #{model_name}:"
  puts "   Purpose: #{description}"
  
  begin
    response = gpt5_client.chat([
      { role: "user", content: "Say 'Hello from #{model_name}' and nothing else." }
    ], model: model_name, use_chat_api: true)
    
    if response[:success]
      puts "   ✅ SUCCESS: #{response[:content]}"
    else
      puts "   ❌ FAILED: #{response[:error]}"
    end
  rescue => e
    puts "   ❌ EXCEPTION: #{e.message}"
  end
end

# Also test if we need to check model availability first
puts "\n🔍 Testing Model List Endpoint:"
begin
  # Make direct API call to list models
  uri = URI('https://api.openai.com/v1/models')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
  
  response = http.request(request)
  
  if response.code == '200'
    data = JSON.parse(response.body)
    gpt5_models = data['data'].select { |m| m['id'].include?('gpt-5') }
    
    puts "   Available GPT-5 models:"
    if gpt5_models.any?
      gpt5_models.each do |model|
        puts "     - #{model['id']}"
      end
    else
      puts "     No GPT-5 models found"
      puts "     (May need waitlist access or different API key)"
    end
  else
    puts "   ❌ Failed to list models: #{response.code} #{response.message}"
  end
rescue => e
  puts "   ❌ Exception: #{e.message}"
end

puts "\n" + "=" * 50