#!/usr/bin/env ruby
# Check Supabase logs via API
# Run with: bin/rails runner scripts/check_supabase_logs.rb

require 'net/http'
require 'json'
require 'uri'
require 'time'

puts "=" * 80
puts "📊 CHECKING SUPABASE LOGS"
puts "=" * 80

supabase_url = ENV['SUPABASE_URL']
service_key = ENV['SUPABASE_SERVICE_KEY']

if !supabase_url || !service_key
  puts "❌ Missing Supabase credentials"
  exit 1
end

puts "\n📍 Supabase Project: #{supabase_url}"

# Try different log endpoints
endpoints = [
  '/platform/logs',
  '/logs',
  '/auth/v1/logs',
  '/rest/v1/auth_logs',
  '/analytics/logs'
]

endpoints.each do |endpoint|
  puts "\n🔍 Trying endpoint: #{endpoint}"
  
  begin
    uri = URI("#{supabase_url}#{endpoint}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri)
    request['apikey'] = service_key
    request['Authorization'] = "Bearer #{service_key}"
    request['Content-Type'] = 'application/json'

    response = http.request(request)
    
    puts "  Response Code: #{response.code}"
    
    if response.code == '200'
      begin
        data = JSON.parse(response.body)
        puts "  ✅ Success! Found #{data.is_a?(Array) ? data.length : 'data'}"
        
        if data.is_a?(Array) && data.length > 0
          puts "  Recent entries:"
          data.first(3).each_with_index do |entry, i|
            puts "    #{i+1}. #{entry.inspect[0..100]}..."
          end
        elsif data.is_a?(Hash)
          puts "  Data keys: #{data.keys.join(', ')}"
        end
      rescue JSON::ParserError
        puts "  ✅ Success but not JSON: #{response.body[0..100]}..."
      end
    elsif response.code == '404'
      puts "  ❌ Not found"
    elsif response.code == '403'
      puts "  ❌ Forbidden (might need different permissions)"
    else
      puts "  ❌ Error: #{response.body[0..100]}..."
    end
    
  rescue => e
    puts "  ❌ Request failed: #{e.message}"
  end
end

# Try to check recent auth events via the database
puts "\n🔍 Checking auth schema via REST API..."

begin
  uri = URI("#{supabase_url}/rest/v1/")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request['apikey'] = service_key
  request['Authorization'] = "Bearer #{service_key}"

  response = http.request(request)
  
  if response.code == '200'
    # This should list available tables/schemas
    puts "  ✅ REST API accessible"
    
    # Try to query auth.users table for recent activity
    uri = URI("#{supabase_url}/rest/v1/auth.users?select=*&order=created_at.desc&limit=5")
    request = Net::HTTP::Get.new(uri)
    request['apikey'] = service_key
    request['Authorization'] = "Bearer #{service_key}"

    response = http.request(request)
    
    if response.code == '200'
      users = JSON.parse(response.body)
      puts "  Recent users (#{users.length}):"
      users.each do |user|
        puts "    #{user['email']} - #{user['created_at']} - #{user['last_sign_in_at']}"
      end
    else
      puts "  Could not query users: #{response.code}"
    end
    
  else
    puts "  REST API not accessible: #{response.code}"
  end
rescue => e
  puts "  Request failed: #{e.message}"
end

# Check auth audit logs if available
puts "\n🔍 Checking auth audit logs..."

begin
  uri = URI("#{supabase_url}/rest/v1/auth.audit_log_entries?order=created_at.desc&limit=10")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request['apikey'] = service_key
  request['Authorization'] = "Bearer #{service_key}"

  response = http.request(request)
  
  if response.code == '200'
    audit_logs = JSON.parse(response.body)
    puts "  ✅ Found #{audit_logs.length} recent auth events:"
    
    audit_logs.each do |log|
      timestamp = Time.parse(log['created_at']).strftime('%H:%M:%S')
      puts "    #{timestamp} - #{log['event_type']} - #{log['actor_username'] || log['actor_id']} - #{log['payload']&.dig('error') || 'success'}"
    end
  else
    puts "  Could not access audit logs: #{response.code}"
    puts "  Response: #{response.body[0..200]}"
  end
rescue => e
  puts "  Request failed: #{e.message}"
end

# Test a simple auth operation to generate logs
puts "\n🧪 Testing auth to generate log entry..."

begin
  uri = URI("#{supabase_url}/auth/v1/token?grant_type=password")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request['apikey'] = service_key
  request['Content-Type'] = 'application/json'
  request.body = {
    email: 'nonexistent@example.com',
    password: 'wrongpassword'
  }.to_json

  response = http.request(request)
  
  puts "  Test auth response: #{response.code}"
  if response.code != '200'
    error_data = JSON.parse(response.body) rescue response.body
    puts "  Expected error: #{error_data}"
  end
rescue => e
  puts "  Test failed: #{e.message}"
end

puts "\n💡 Alternative: Check Supabase Dashboard"
puts "Go to: https://supabase.com/dashboard/project/bsbgwixlklvgeoxvjmtb/logs/auth"
puts "This will show real-time auth logs and errors."

puts "\n🎯 For OAuth debugging, look for:"
puts "- 'oauth_callback_error' events"
puts "- 'validation_failed' errors"
puts "- Redirect URL mismatches"

puts "\n" + "=" * 80
puts "Supabase logs check complete"
puts "=" * 80