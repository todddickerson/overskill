#!/usr/bin/env ruby
# Test Supabase authentication directly
# Run with: bin/rails runner scripts/test_supabase_auth.rb

require 'net/http'
require 'json'
require 'uri'

puts "=" * 80
puts "🔐 TESTING SUPABASE AUTHENTICATION DIRECTLY"
puts "=" * 80

# Test authentication with Supabase
supabase_url = ENV['SUPABASE_URL']
supabase_anon_key = ENV['SUPABASE_ANON_KEY']

if !supabase_url || !supabase_anon_key
  puts "❌ Supabase credentials not found in environment"
  exit 1
end

puts "\n📍 Supabase Project: #{supabase_url}"
puts "🔑 Anon Key: #{supabase_anon_key[0..20]}..."

# Test creating a test user
puts "\n🧪 Testing User Creation via Supabase API:"

test_email = "test_#{Time.now.to_i}@example.com"
test_password = "TestPassword123!"

uri = URI("#{supabase_url}/auth/v1/signup")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Post.new(uri)
request['apikey'] = supabase_anon_key
request['Content-Type'] = 'application/json'
request.body = {
  email: test_email,
  password: test_password
}.to_json

puts "  Creating user: #{test_email}"

begin
  response = http.request(request)
  
  puts "  Response Code: #{response.code}"
  
  if response.code == '200'
    data = JSON.parse(response.body)
    if data['user']
      puts "  ✅ User created successfully!"
      puts "  User ID: #{data['user']['id']}"
      puts "  Email: #{data['user']['email']}"
    else
      puts "  ⚠️ Unexpected response format"
    end
  else
    puts "  ❌ Failed to create user"
    puts "  Response: #{response.body}"
    
    # Parse error
    begin
      error_data = JSON.parse(response.body)
      if error_data['error']
        puts "  Error: #{error_data['error']}"
        puts "  Message: #{error_data['error_description'] || error_data['msg']}"
      end
    rescue
      # Not JSON
    end
  end
rescue => e
  puts "  ❌ Request failed: #{e.message}"
end

# Check OAuth providers configuration
puts "\n🔗 OAuth Providers Status:"
puts "  Note: OAuth providers must be configured in Supabase dashboard"
puts "  Expected redirect URLs for preview apps:"
puts "    - https://preview-*.overskill.app/auth/callback"
puts "    - https://preview-**.overskill.app/**"

# Test the auth settings endpoint
puts "\n📊 Auth Settings via Supabase:"
uri = URI("#{supabase_url}/auth/v1/settings")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Get.new(uri)
request['apikey'] = supabase_anon_key

begin
  response = http.request(request)
  
  if response.code == '200'
    settings = JSON.parse(response.body)
    puts "  ✅ Retrieved auth settings"
    
    if settings['external']
      puts "\n  External Providers Enabled:"
      settings['external'].each do |provider, enabled|
        status = enabled ? '✅' : '❌'
        puts "    #{status} #{provider}"
      end
    end
    
    if settings['email']
      puts "\n  Email Settings:"
      puts "    Confirmations: #{settings['email']['confirmations'] ? 'Required' : 'Not required'}"
    end
  else
    puts "  ❌ Could not retrieve auth settings"
  end
rescue => e
  puts "  ❌ Request failed: #{e.message}"
end

puts "\n💡 Common Issues:"
puts "  1. OAuth redirect URL not configured in Supabase"
puts "  2. Email confirmations required but not handled"
puts "  3. OAuth provider (Google/GitHub) not configured with credentials"
puts "  4. CORS issues with preview domain"

puts "\n🔍 To Fix OAuth:"
puts "  1. Go to Supabase dashboard > Authentication > URL Configuration"
puts "  2. Add to Redirect URLs: https://preview-**.overskill.app/**"
puts "  3. Save changes"

puts "\n" + "=" * 80
puts "Test complete"
puts "=" * 80