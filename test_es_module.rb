#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'
require 'securerandom'

# Load Rails environment
require_relative 'config/environment'

account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
api_token = ENV['CLOUDFLARE_API_TOKEN']

# Simple ES module test script
test_script = <<~JS
  // Simple ES Module test
  export default {
    async fetch(request, env, ctx) {
      const envKeys = Object.keys(env);
      return new Response('ES Module works! Environment vars: ' + envKeys.join(', ') + ' | APP_ID=' + env.APP_ID, {
        headers: { 'content-type': 'text/plain' }
      });
    }
  };
JS

puts "Testing ES module with environment variables..."
puts "Script size: #{test_script.bytesize} bytes"

# Test deployment with multipart form data and bindings
worker_name = "test-es-module-#{Time.now.to_i}"

# Create bindings for testing
bindings = [
  { name: 'APP_ID', text: '9999', type: 'plain_text' },
  { name: 'TEST_VAR', text: 'hello world', type: 'plain_text' }
]

metadata = {
  main_module: 'worker.js',
  compatibility_date: '2024-01-01',
  bindings: bindings
}

# Build multipart body
boundary = "----WebKitFormBoundary#{SecureRandom.hex(16)}"
body_parts = []

# Add metadata
body_parts << "--#{boundary}\r\n"
body_parts << "Content-Disposition: form-data; name=\"metadata\"\r\n\r\n"
body_parts << metadata.to_json
body_parts << "\r\n"

# Add worker script
body_parts << "--#{boundary}\r\n"
body_parts << "Content-Disposition: form-data; name=\"worker.js\"; filename=\"worker.js\"\r\n"
body_parts << "Content-Type: application/javascript+module\r\n\r\n"
body_parts << test_script
body_parts << "\r\n"

# Close boundary
body_parts << "--#{boundary}--\r\n"

multipart_body = body_parts.join('')

puts "Multipart body size: #{multipart_body.bytesize} bytes"
puts "Bindings: #{bindings.map { |b| b[:name] }.join(', ')}"

# Deploy
uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Put.new(uri)
request['Authorization'] = "Bearer #{api_token}"
request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
request.body = multipart_body

response = http.request(request)

puts "Response code: #{response.code}"

if response.code == '200'
  puts "✅ ES module with environment variables deployed successfully!"
  
  # Parse response to get worker URL
  response_data = JSON.parse(response.body)
  puts "Worker deployed with ID: #{response_data['result']['id']}"
  
  # Clean up
  puts "\nCleaning up..."
  delete_uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
  delete_request = Net::HTTP::Delete.new(delete_uri)
  delete_request['Authorization'] = "Bearer #{api_token}"
  delete_response = http.request(delete_request)
  puts "✓ Test worker deleted" if delete_response.code == '200'
else
  puts "❌ ES module deployment failed!"
  puts "Response body:"
  puts JSON.pretty_generate(JSON.parse(response.body)) rescue puts response.body
end