#!/usr/bin/env ruby
# Test script for Cloudflare deployment functionality
# Run this in Rails console: rails c
# Then execute each section step by step

puts "=== Cloudflare Deployment Test Script ==="
puts "Run each section by copying and pasting into Rails console"
puts

puts "# Step 1: Check environment variables"
puts "---"
puts <<-'RUBY'
# Check if Cloudflare credentials are configured
cloudflare_creds = {
  api_token: ENV['CLOUDFLARE_API_TOKEN'],
  account_id: ENV['CLOUDFLARE_ACCOUNT_ID'],
  zone_id: ENV['CLOUDFLARE_ZONE_ID']
}

puts "Cloudflare credentials status:"
cloudflare_creds.each do |key, value|
  status = value.present? ? "✅ Set (#{value[0..5]}...)" : "❌ Missing"
  puts "  #{key}: #{status}"
end

all_present = cloudflare_creds.values.all?(&:present?)
puts "\nAll credentials present: #{all_present ? '✅ Yes' : '❌ No'}"
RUBY

puts "\n# Step 2: Find and inspect the app"
puts "---"
puts <<-'RUBY'
# Find the app
app = App.find_by(id: 'wJGvjb')

if app
  puts "App found: #{app.name} (ID: #{app.id})"
  puts "Team: #{app.team.name}"
  puts "Status: #{app.status}"
  puts "Files count: #{app.app_files.count}"
  puts "Deployment status: #{app.deployment_status || 'never deployed'}"
  puts "Deployment URL: #{app.deployment_url || 'none'}"
  
  if app.app_files.any?
    puts "\nApp files:"
    app.app_files.each do |file|
      puts "  - #{file.path} (#{file.file_type}, #{file.size_bytes} bytes)"
    end
  else
    puts "\n⚠️  No files found! Creating test files..."
    
    # Create some test files if none exist
    app.app_files.create!(
      team: app.team,
      path: "index.html",
      content: <<-HTML,
<!DOCTYPE html>
<html>
<head>
  <title>#{app.name}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <h1>Welcome to #{app.name}</h1>
  <p>Deployed via Cloudflare Workers!</p>
  <button id="counter">Click me: 0</button>
  <script src="app.js"></script>
</body>
</html>
      HTML
      file_type: "html",
      size_bytes: 300
    )
    
    app.app_files.create!(
      team: app.team,
      path: "style.css",
      content: <<-CSS,
body {
  font-family: Arial, sans-serif;
  margin: 40px;
  background-color: #f0f0f0;
}
h1 {
  color: #333;
}
button {
  padding: 10px 20px;
  font-size: 16px;
  cursor: pointer;
}
      CSS
      file_type: "css",
      size_bytes: 150
    )
    
    app.app_files.create!(
      team: app.team,
      path: "app.js",
      content: <<-JS,
let count = 0;
const button = document.getElementById('counter');
button.addEventListener('click', () => {
  count++;
  button.textContent = `Click me: ${count}`;
});
console.log('App loaded successfully!');
      JS
      file_type: "javascript",
      size_bytes: 180
    )
    
    puts "Created #{app.app_files.count} test files"
  end
else
  puts "❌ App not found with ID: wJGvjb"
  puts "Available apps:"
  App.limit(5).each do |a|
    puts "  - #{a.name} (ID: #{a.id})"
  end
end
RUBY

puts "\n# Step 3: Test the deployment service"
puts "---"
puts <<-'RUBY'
# Initialize the deployment service
app = App.find_by(id: 'wJGvjb') || App.first
service = Deployment::CloudflareWorkerService.new(app)

# Test subdomain generation
subdomain = service.send(:generate_subdomain)
puts "Generated subdomain: #{subdomain}"

# Test worker script generation
script = service.send(:generate_worker_script)
puts "\nWorker script preview (first 200 chars):"
puts script[0..200] + "..."

# Test files JSON generation
files_json = service.send(:app_files_as_json)
files_data = JSON.parse(files_json)
puts "\nFiles to be deployed:"
files_data.each do |path, content|
  puts "  - #{path} (#{content.length} chars)"
end
RUBY

puts "\n# Step 4: Perform actual deployment (if credentials are set)"
puts "---"
puts <<-'RUBY'
# Only run this if you have valid Cloudflare credentials!
app = App.find_by(id: 'wJGvjb') || App.first

if ENV['CLOUDFLARE_API_TOKEN'].present?
  puts "🚀 Attempting deployment..."
  
  # Option 1: Direct service call (synchronous)
  service = Deployment::CloudflareWorkerService.new(app)
  result = service.deploy!
  
  if result[:success]
    puts "✅ Deployment successful!"
    puts "URL: #{result[:message]}"
    puts "App deployment URL: #{app.reload.deployment_url}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
  
  # Option 2: Background job (asynchronous)
  # DeployAppJob.perform_now(app.id)
else
  puts "⚠️  Skipping deployment - no Cloudflare credentials found"
  puts "To test deployment, set these environment variables:"
  puts "  - CLOUDFLARE_API_TOKEN"
  puts "  - CLOUDFLARE_ACCOUNT_ID" 
  puts "  - CLOUDFLARE_ZONE_ID"
end
RUBY

puts "\n# Step 5: Test deployment status"
puts "---"
puts <<-'RUBY'
# Check deployment status after running deployment
app = App.find_by(id: 'wJGvjb') || App.first
app.reload

puts "Current deployment status:"
puts "  Status: #{app.deployment_status || 'never deployed'}"
puts "  URL: #{app.deployment_url || 'none'}"
puts "  Deployed at: #{app.deployed_at || 'never'}"

if app.deployment_url.present?
  puts "\n🌐 Your app should be accessible at:"
  puts "  #{app.deployment_url}"
end
RUBY

puts "\n# Step 6: Mock deployment for testing (no actual API calls)"
puts "---"
puts <<-'RUBY'
# This simulates a successful deployment without calling Cloudflare
app = App.find_by(id: 'wJGvjb') || App.first

# Simulate deployment
subdomain = app.name.parameterize + "-" + app.id.to_s
deployment_url = "https://#{subdomain}.overskill.app"

app.update!(
  deployment_status: 'deployed',
  deployment_url: deployment_url,
  deployed_at: Time.current
)

# Create a deployment version
app.app_versions.create!(
  version_number: "1.0.0",
  changelog: "Deployed to #{deployment_url}",
  team: app.team
)

puts "✅ Mock deployment complete!"
puts "URL: #{app.deployment_url}"
puts "You can now test the preview tab with this simulated deployment"
RUBY

puts "\n# Troubleshooting"
puts "---"
puts <<-'RUBY'
# If deployment fails, check these common issues:

# 1. Check HTTParty configuration
puts "HTTParty base_uri: #{Deployment::CloudflareWorkerService.base_uri}"

# 2. Test API connectivity (requires credentials)
if ENV['CLOUDFLARE_API_TOKEN'].present?
  require 'net/http'
  require 'uri'
  
  uri = URI('https://api.cloudflare.com/client/v4/user')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Get.new(uri)
  request['Authorization'] = "Bearer #{ENV['CLOUDFLARE_API_TOKEN']}"
  
  response = http.request(request)
  puts "API test response code: #{response.code}"
  puts "API test response: #{response.body[0..100]}..."
end

# 3. Check for required gems
puts "\nRequired gems:"
['httparty', 'json'].each do |gem_name|
  begin
    require gem_name
    puts "  ✅ #{gem_name}"
  rescue LoadError
    puts "  ❌ #{gem_name} - not loaded"
  end
end
RUBY