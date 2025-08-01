#!/usr/bin/env ruby
# Quick script to check which Cloudflare auth method works
# Run in Rails console

puts "Testing Cloudflare Authentication Methods..."
puts

# Method 1: API Key (Global)
puts "1. Testing Global API Key:"
puts <<-'RUBY'
require 'httparty'

# Need both API Key and Email for global key auth
email = "your-email@example.com" # UPDATE THIS
api_key = ENV['CLOUDFLARE_API_KEY']

response = HTTParty.get(
  'https://api.cloudflare.com/client/v4/user',
  headers: {
    'X-Auth-Email' => email,
    'X-Auth-Key' => api_key,
    'Content-Type' => 'application/json'
  }
)

puts "Global API Key Status: #{response.code}"
puts response.body[0..200] if response.code != 200
RUBY

puts "\n2. Testing API Token (Scoped):"
puts <<-'RUBY'
# API Token uses Bearer auth
api_token = ENV['CLOUDFLARE_API_TOKEN'] || ENV['CLOUDFLARE_API_KEY']

response = HTTParty.get(
  'https://api.cloudflare.com/client/v4/user/tokens/verify',
  headers: {
    'Authorization' => "Bearer #{api_token}",
    'Content-Type' => 'application/json'
  }
)

puts "API Token Status: #{response.code}"
if response.code == 200
  result = JSON.parse(response.body)
  puts "✅ Token is valid: #{result.dig('result', 'status')}"
else
  puts "❌ Token invalid: #{response.body}"
end
RUBY

puts "\n3. Which method to use?"
puts <<-TEXT
If you have:
- Global API Key: Need to use X-Auth-Email + X-Auth-Key headers
- API Token: Use Authorization: Bearer header

To create an API Token:
1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Create token with these permissions:
   - Account: Workers Scripts:Edit
   - Zone: Workers Routes:Edit
   - Zone: Zone:Read
TEXT