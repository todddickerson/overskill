#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🔍 Debug HTTP Request Formation"
puts "=" * 40

# Test the exact request that's being made
gpt5_client = Ai::OpenaiGpt5Client.instance

# Mock the methods to see what's happening
puts "Testing prepare_chat_request method:"
messages = [{ role: "user", content: "Hello" }]

# Call the private method to see the request body
request_body = gpt5_client.send(:prepare_chat_request, 
  messages: messages,
  model: "gpt-4o", 
  temperature: 0.7,
  max_tokens: 10,
  reasoning_level: :medium,
  verbosity: :medium,
  tools: nil
)

puts "Request body prepared:"
puts JSON.pretty_generate(request_body)

# Test the make_request method
puts "\nTesting make_request method with actual HTTP client:"

# Get the internal HTTP client
http_client = gpt5_client.instance_variable_get(:@http_client)
puts "HTTP client host: #{http_client.address}:#{http_client.port}"
puts "HTTP client SSL: #{http_client.use_ssl?}"

# Test manual request
endpoint = '/chat/completions'
api_key = ENV['OPENAI_API_KEY'] || "your-api-key-here"

request = Net::HTTP::Post.new(endpoint)
request['Authorization'] = "Bearer #{api_key}"
request['Content-Type'] = 'application/json'  
request.body = request_body.to_json

puts "\nActual request details:"
puts "  Method: POST"
puts "  Path: #{endpoint}"
puts "  Host: #{http_client.address}"
puts "  Headers:"
puts "    Authorization: Bearer #{api_key[0..15]}..."
puts "    Content-Type: #{request['Content-Type']}"
puts "  Body size: #{request.body.length} bytes"

# Make the actual request
puts "\nMaking HTTP request..."
begin
  response = http_client.request(request)
  puts "Response code: #{response.code}"
  puts "Response message: #{response.message}"
  puts "Response body (first 200 chars): #{response.body[0..200]}"
rescue => e
  puts "Exception during HTTP request: #{e.message}"
end

puts "\n" + "=" * 40