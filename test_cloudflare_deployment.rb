#!/usr/bin/env ruby

require 'net/http'
require 'uri'
require 'json'

# Load Rails environment
require_relative 'config/environment'

puts "Testing Cloudflare Workers deployment..."

# Get credentials
account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
api_token = ENV['CLOUDFLARE_API_TOKEN']

if account_id.nil? || api_token.nil?
  puts "❌ Missing Cloudflare credentials"
  exit 1
end

puts "✓ Credentials loaded"
puts "  Account ID: #{account_id[0..10]}..."
puts "  API Token: #{api_token[0..10]}..."

# Test deployment with a minimal worker script
worker_name = "test-minimal-worker-#{Time.now.to_i}"
puts "\nDeploying test worker: #{worker_name}"

# Create an absolutely minimal worker script
minimal_script = <<~JS
  addEventListener('fetch', event => {
    event.respondWith(new Response('Hello from test worker!', {
      headers: { 'content-type': 'text/plain' }
    }))
  })
JS

puts "Script size: #{minimal_script.bytesize} bytes"
puts "Script content:"
puts minimal_script

# Deploy the worker
uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true

request = Net::HTTP::Put.new(uri)
request['Authorization'] = "Bearer #{api_token}"
request['Content-Type'] = 'application/javascript'
request.body = minimal_script

puts "\nSending deployment request..."
response = http.request(request)

puts "Response code: #{response.code}"
puts "Response body:"
puts JSON.pretty_generate(JSON.parse(response.body)) rescue puts response.body

if response.code == '200'
  puts "\n✅ Test worker deployed successfully!"
  
  # Clean up - delete the test worker
  puts "\nCleaning up test worker..."
  delete_uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
  delete_request = Net::HTTP::Delete.new(delete_uri)
  delete_request['Authorization'] = "Bearer #{api_token}"
  
  delete_response = http.request(delete_request)
  if delete_response.code == '200'
    puts "✓ Test worker deleted"
  else
    puts "⚠ Failed to delete test worker"
  end
else
  puts "\n❌ Test deployment failed!"
  
  # Try to get more details about the error
  if response.body.include?('errors')
    begin
      parsed = JSON.parse(response.body)
      if parsed['errors'] && parsed['errors'].any?
        puts "\nError details:"
        parsed['errors'].each do |error|
          puts "  - Code: #{error['code']}"
          puts "    Message: #{error['message']}"
          puts "    Details: #{error.inspect}"
        end
      end
    rescue
      # Ignore JSON parse errors
    end
  end
end

# Now test with App.last's actual worker script
puts "\n" + "="*60
puts "Testing with App.last worker script..."

app = App.last
if app
  puts "App ##{app.id}: #{app.name}"
  
  # Get the actual worker script that's failing
  deployer = Deployment::CloudflareWorkersDeployer.new(app)
  
  # Build the worker script as deployer would
  built_code = {}
  app.app_files.each do |file|
    next if file.path.end_with?('.jpg', '.png', '.gif')  # Skip images
    built_code[file.path] = file.content
  end
  
  worker_script = deployer.send(:generate_worker_script, built_code, {})
  
  puts "Worker script size: #{(worker_script.bytesize / 1024.0).round(2)} KB"
  
  # Check for common issues
  puts "\nChecking for common issues..."
  
  # Check for problematic characters
  if worker_script.include?("\u0000")
    puts "⚠ Script contains null bytes!"
  end
  
  if worker_script.include?("\r")
    puts "⚠ Script contains carriage returns (Windows line endings)"
  end
  
  # Check for very long lines
  max_line_length = worker_script.lines.map(&:length).max
  if max_line_length > 10000
    puts "⚠ Script has very long lines (max: #{max_line_length} chars)"
  end
  
  # Check for non-UTF8 characters
  begin
    worker_script.encode('UTF-8')
    puts "✓ Script is valid UTF-8"
  rescue Encoding::UndefinedConversionError => e
    puts "⚠ Script contains non-UTF-8 characters: #{e.message}"
  end
  
  # Try deploying with the actual script
  puts "\nTrying to deploy App ##{app.id}'s worker..."
  worker_name = "test-app-#{app.id}-#{Time.now.to_i}"
  
  uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
  request = Net::HTTP::Put.new(uri)
  request['Authorization'] = "Bearer #{api_token}"
  request['Content-Type'] = 'application/javascript'
  request.body = worker_script
  
  response = http.request(request)
  
  puts "Response code: #{response.code}"
  if response.code != '200'
    puts "Response body:"
    puts JSON.pretty_generate(JSON.parse(response.body)) rescue puts response.body
    
    # Extract first few lines of the worker script for debugging
    puts "\nFirst 10 lines of worker script:"
    puts worker_script.lines[0..9].join
  else
    puts "✅ App's worker deployed successfully as test!"
    
    # Clean up
    delete_uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
    delete_request = Net::HTTP::Delete.new(delete_uri)
    delete_request['Authorization'] = "Bearer #{api_token}"
    delete_response = http.request(delete_request)
    puts "✓ Test worker deleted" if delete_response.code == '200'
  end
else
  puts "No apps found"
end