#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'

puts "🔍 Manual HTTP Request (Identical to Curl)"
puts "=" * 50

# Make exactly the same request as the working curl
uri = URI('https://api.openai.com/v1/chat/completions')
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 60
http.open_timeout = 10

request = Net::HTTP::Post.new(uri.path)
request['Content-Type'] = 'application/json'
request['Authorization'] = 'Bearer your-api-key-here'

body = {
  "model": "gpt-4o",
  "messages": [{"role": "user", "content": "Say hello"}],
  "max_tokens": 10
}

request.body = body.to_json

puts "Request details:"
puts "  URI: #{uri}"
puts "  Method: POST"
puts "  Headers: #{request.to_hash}"
puts "  Body: #{request.body}"

puts "\nMaking request..."
begin
  response = http.request(request)
  puts "Response code: #{response.code}"
  puts "Response message: #{response.message}"
  
  if response.code == '200'
    result = JSON.parse(response.body)
    puts "✅ SUCCESS!"
    puts "Content: #{result.dig('choices', 0, 'message', 'content')}"
  else
    puts "❌ FAILED"
    puts "Response body: #{response.body[0..200]}"
  end
rescue => e
  puts "Exception: #{e.message}"
  puts "Backtrace: #{e.backtrace.first(3)}"
end

puts "\n" + "=" * 50