#!/usr/bin/env ruby
# Test preview URL accessibility with retries

require_relative 'config/environment'
require 'net/http'
require 'uri'

app_id = ARGV[0] || App.last.id
app = App.find(app_id)

puts "Testing preview for app ##{app.id}: #{app.name}"
puts "Preview URL: #{app.preview_url}"
puts "-"*60

if app.preview_url.nil?
  puts "❌ No preview URL set"
  exit 1
end

uri = URI.parse(app.preview_url)
max_retries = 5
retry_count = 0
success = false

while retry_count < max_retries && !success
  retry_count += 1
  
  begin
    puts "\nAttempt #{retry_count}/#{max_retries}..."
    response = Net::HTTP.get_response(uri)
    
    puts "  Status: #{response.code}"
    puts "  Size: #{response.body.length} bytes"
    
    if response.code == '200'
      puts "  ✅ SUCCESS - Preview is accessible!"
      
      # Check if it contains expected content
      if response.body.include?('<!DOCTYPE html')
        puts "  ✅ Contains HTML content"
      end
      
      if response.body.include?('React')
        puts "  ✅ Contains React references"
      end
      
      success = true
    elsif response.code == '530'
      puts "  ⚠️ Cloudflare 530 error - Worker may still be deploying"
      if retry_count < max_retries
        puts "  Waiting 3 seconds before retry..."
        sleep 3
      end
    else
      puts "  ⚠️ Unexpected status: #{response.code}"
      puts "  Headers: #{response.to_hash.inspect[0..200]}"
    end
    
  rescue => e
    puts "  ❌ Error: #{e.message}"
  end
end

puts "\n" + "="*60
if success
  puts "✅ Preview deployment verified successfully!"
  puts "URL: #{app.preview_url}"
else
  puts "❌ Preview not accessible after #{max_retries} attempts"
  puts "This could mean:"
  puts "  - Worker is still deploying (try again in 30 seconds)"
  puts "  - Cloudflare configuration issue"
  puts "  - Route not properly configured"
end