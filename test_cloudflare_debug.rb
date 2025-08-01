#!/usr/bin/env ruby
# Debug script to check Cloudflare Workers setup
# Run in Rails console: rails c

puts "=== Cloudflare Workers Debug Script ==="
puts

puts "# Step 1: Test Cloudflare API connection"
puts "---"
puts <<-'RUBY'
require 'httparty'

# Test API connection
response = HTTParty.get(
  'https://api.cloudflare.com/client/v4/user',
  headers: {
    'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
    'Content-Type' => 'application/json'
  }
)

puts "API Status: #{response.code}"
if response.code == 200
  user_data = JSON.parse(response.body)
  puts "✅ Connected as: #{user_data.dig('result', 'email')}"
else
  puts "❌ API Error: #{response.body}"
end
RUBY

puts "\n# Step 2: List existing Workers"
puts "---"
puts <<-'RUBY'
# List all workers in the account
response = HTTParty.get(
  "https://api.cloudflare.com/client/v4/accounts/#{ENV['CLOUDFLARE_ACCOUNT_ID']}/workers/scripts",
  headers: {
    'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
    'Content-Type' => 'application/json'
  }
)

if response.code == 200
  workers = JSON.parse(response.body)['result'] || []
  puts "Found #{workers.length} workers:"
  workers.each do |worker|
    puts "  - #{worker['id']} (created: #{worker['created_on']})"
  end
else
  puts "❌ Failed to list workers: #{response.body}"
end
RUBY

puts "\n# Step 3: List routes for overskill.app"
puts "---"
puts <<-'RUBY'
# List all routes for the zone
response = HTTParty.get(
  "https://api.cloudflare.com/client/v4/zones/#{ENV['CLOUDFLARE_ZONE_ID']}/workers/routes",
  headers: {
    'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
    'Content-Type' => 'application/json'
  }
)

if response.code == 200
  routes = JSON.parse(response.body)['result'] || []
  puts "Found #{routes.length} routes:"
  routes.each do |route|
    puts "  - Pattern: #{route['pattern']}"
    puts "    Script: #{route['script']}"
    puts "    ID: #{route['id']}"
  end
else
  puts "❌ Failed to list routes: #{response.body}"
end
RUBY

puts "\n# Step 4: Check specific preview worker"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first
worker_name = "preview-#{app.id}"

# Check if worker exists
response = HTTParty.get(
  "https://api.cloudflare.com/client/v4/accounts/#{ENV['CLOUDFLARE_ACCOUNT_ID']}/workers/scripts/#{worker_name}",
  headers: {
    'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
    'Content-Type' => 'application/json'
  }
)

if response.code == 200
  puts "✅ Worker '#{worker_name}' exists"
  
  # Get worker details
  metadata = JSON.parse(response.body)['result']
  puts "  Size: #{metadata['size']} bytes"
  puts "  Modified: #{metadata['modified_on']}"
else
  puts "❌ Worker '#{worker_name}' not found"
  puts "Response: #{response.body}"
end
RUBY

puts "\n# Step 5: Test worker deployment manually"
puts "---"
puts <<-'RUBY'
# Create a simple test worker
app = App.find_by(id: 'wJGvjb') || App.first
worker_name = "test-preview-#{app.id}"

test_script = <<-JS
addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  return new Response('Hello from OverSkill preview!', {
    headers: { 'content-type': 'text/plain' },
  })
}
JS

puts "Uploading test worker '#{worker_name}'..."

response = HTTParty.put(
  "https://api.cloudflare.com/client/v4/accounts/#{ENV['CLOUDFLARE_ACCOUNT_ID']}/workers/scripts/#{worker_name}",
  headers: {
    'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
    'Content-Type' => 'application/javascript'
  },
  body: test_script
)

if response.code == 200
  puts "✅ Test worker uploaded successfully"
  
  # Now create a route
  route_pattern = "test-#{app.id}.overskill.app/*"
  
  route_response = HTTParty.post(
    "https://api.cloudflare.com/client/v4/zones/#{ENV['CLOUDFLARE_ZONE_ID']}/workers/routes",
    headers: {
      'Authorization' => "Bearer #{ENV['CLOUDFLARE_API_KEY']}",
      'Content-Type' => 'application/json'
    },
    body: JSON.generate({
      pattern: route_pattern,
      script: worker_name
    })
  )
  
  if route_response.code == 200
    puts "✅ Route created: https://#{route_pattern.gsub('/*', '')}"
  else
    puts "❌ Route creation failed: #{route_response.body}"
  end
else
  puts "❌ Worker upload failed: #{response.body}"
end
RUBY

puts "\n# Step 6: Debug the preview service"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first
service = Deployment::CloudflarePreviewService.new(app)

# Check what the service thinks it's doing
puts "Service configuration:"
puts "  Account ID: #{ENV['CLOUDFLARE_ACCOUNT_ID'][0..10]}..."
puts "  API Key: #{ENV['CLOUDFLARE_API_KEY'][0..10]}..."
puts "  Zone ID: #{ENV['CLOUDFLARE_ZONE_ID'][0..10]}..."

# Test worker script generation
script = service.send(:generate_worker_script)
puts "\nGenerated script size: #{script.length} bytes"
puts "Script preview:"
puts script[0..200] + "..."

# Check app files
files_json = service.send(:app_files_as_json)
files = JSON.parse(files_json)
puts "\nApp files to deploy:"
files.each do |path, content|
  puts "  - #{path} (#{content.length} bytes)"
end
RUBY

puts "\n# Troubleshooting"
puts "---"
puts <<-TEXT
Common issues:

1. DNS not configured:
   - Make sure *.overskill.app points to Cloudflare
   - Check Cloudflare DNS settings

2. Worker limits:
   - Free plan: 100,000 requests/day
   - Script size limit: 1MB

3. Route conflicts:
   - Can't have overlapping routes
   - More specific routes take precedence

To test if worker is accessible:
  curl -v https://preview-wJGvjb.overskill.app
TEXT