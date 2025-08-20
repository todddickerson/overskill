#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'

# Load Rails environment
require_relative 'config/environment'

puts "Testing Cloudflare Workers secrets API..."

account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
api_token = ENV['CLOUDFLARE_API_TOKEN']

if account_id.nil? || api_token.nil?
  puts "❌ Missing Cloudflare credentials"
  exit 1
end

# Test worker name
worker_name = "preview-app-1140"

puts "Testing secrets API for worker: #{worker_name}"

# Check current API documentation - the correct endpoint for setting worker environment variables
# should be: PUT /accounts/{account_id}/workers/scripts/{script_name}/settings

# First, let's check what endpoints are available
puts "\n1. Testing current settings endpoint..."
uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}/settings")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request['Authorization'] = "Bearer #{api_token}"

response = http.request(request)
puts "GET /settings - Status: #{response.code}"
puts "Response: #{JSON.pretty_generate(JSON.parse(response.body)) rescue response.body}"

# Test the bindings endpoint (newer API)
puts "\n2. Testing bindings endpoint..."
bindings_uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}/bindings")
bindings_request = Net::HTTP::Get.new(bindings_uri)
bindings_request['Authorization'] = "Bearer #{api_token}"

bindings_response = http.request(bindings_request)
puts "GET /bindings - Status: #{bindings_response.code}"
puts "Response: #{JSON.pretty_generate(JSON.parse(bindings_response.body)) rescue bindings_response.body}"

# Try the correct way to set environment variables - via settings
puts "\n3. Testing environment variables via settings..."
test_env_vars = {
  "APP_ID" => "1140",
  "ENVIRONMENT" => "preview"
}

settings_body = {
  "bindings" => test_env_vars.map do |key, value|
    {
      "name" => key,
      "text" => value,
      "type" => "plain_text"
    }
  end
}

puts "Sending settings update..."
puts "Body: #{JSON.pretty_generate(settings_body)}"

settings_request = Net::HTTP::Patch.new(uri)
settings_request['Authorization'] = "Bearer #{api_token}"
settings_request['Content-Type'] = 'application/json'
settings_request.body = settings_body.to_json

settings_response = http.request(settings_request)
puts "PATCH /settings - Status: #{settings_response.code}"
puts "Response: #{JSON.pretty_generate(JSON.parse(settings_response.body)) rescue settings_response.body}"

# Alternative: try updating the entire worker with environment variables
if settings_response.code != '200'
  puts "\n4. Checking worker script upload with bindings..."
  
  # Get the worker script
  script_uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
  script_request = Net::HTTP::Get.new(script_uri)
  script_request['Authorization'] = "Bearer #{api_token}"
  
  script_response = http.request(script_request)
  puts "GET worker script - Status: #{script_response.code}"
  
  if script_response.code == '200'
    script_data = JSON.parse(script_response.body)
    puts "Worker exists - can be updated with bindings"
    
    # Show the proper multipart upload format for workers with bindings
    puts "\nProper format for worker upload with environment variables:"
    puts "Content-Type: multipart/form-data"
    puts "Fields:"
    puts "  - metadata: JSON with bindings array"
    puts "  - script: JavaScript code"
    
    metadata = {
      "main_module" => "worker.js",
      "bindings" => test_env_vars.map do |key, value|
        {
          "name" => key,
          "text" => value,
          "type" => "plain_text"
        }
      end
    }
    
    puts "Metadata example:"
    puts JSON.pretty_generate(metadata)
  end
end