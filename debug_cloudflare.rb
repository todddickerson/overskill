#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Cloudflare API Debug Test"
puts "="*40

# Check environment variables
puts "\n📋 Environment Variables:"
puts "CLOUDFLARE_ACCOUNT_ID: #{ENV['CLOUDFLARE_ACCOUNT_ID'] ? '✅ Set' : '❌ Missing'}"
puts "CLOUDFLARE_API_TOKEN: #{ENV['CLOUDFLARE_API_TOKEN'] ? '✅ Set' : '❌ Missing'}"
puts "CLOUDFLARE_ZONE_ID: #{ENV['CLOUDFLARE_ZONE_ID'] ? '✅ Set' : '❌ Missing'}"

# Get test app
app = App.last
if !app
  puts "❌ No apps found"
  exit
end

puts "\n📱 Test App: #{app.name} (#{app.id})"
puts "App files: #{app.app_files.count}"

# Test FastPreviewService credentials
puts "\n🔐 Testing credentials..."
service = Deployment::FastPreviewService.new(app)
puts "Credentials present: #{service.send(:credentials_present?) ? '✅' : '❌'}"

# Test basic API call
puts "\n🌐 Testing Cloudflare API..."
require 'httparty'

headers = {
  'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_TOKEN']}",
  'Content-Type' => 'application/json'
}

begin
  response = HTTParty.get(
    "https://api.cloudflare.com/client/v4/accounts/#{ENV['CLOUDFLARE_ACCOUNT_ID']}/workers/scripts",
    headers: headers
  )
  
  puts "API Response Status: #{response.code}"
  puts "API Response: #{response.body[0..200]}..."
  
  if response.success?
    puts "✅ Cloudflare API connection working"
  else
    puts "❌ Cloudflare API connection failed"
  end
rescue => e
  puts "❌ API Error: #{e.message}"
end

# Test worker upload
puts "\n🚀 Testing Worker Upload..."
begin
  worker_name = "test-preview-#{app.id}"
  simple_script = <<~JS
    addEventListener('fetch', event => {
      event.respondWith(new Response('Hello from OverSkill test worker!', {
        headers: { 'Content-Type': 'text/plain' }
      }))
    })
  JS
  
  upload_response = HTTParty.put(
    "https://api.cloudflare.com/client/v4/accounts/#{ENV['CLOUDFLARE_ACCOUNT_ID']}/workers/scripts/#{worker_name}",
    headers: {
      'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_TOKEN']}",
      'Content-Type' => 'application/javascript'
    },
    body: simple_script
  )
  
  puts "Upload Status: #{upload_response.code}"
  puts "Upload Response: #{upload_response.body}"
  
  if upload_response.success?
    puts "✅ Worker upload successful!"
    puts "Worker URL: https://#{worker_name}.#{ENV['CLOUDFLARE_ACCOUNT_ID'].gsub('_', '-')}.workers.dev"
  else
    puts "❌ Worker upload failed"
  end
rescue => e
  puts "❌ Upload Error: #{e.message}"
end

puts "\n✅ Debug complete!"