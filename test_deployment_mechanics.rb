#!/usr/bin/env ruby
require_relative 'config/environment'

# Test deployment mechanics with existing app
puts "\n=== Testing Deployment Mechanics ==="

# Find an app with files
app = App.joins(:app_files).where.not(app_files: { id: nil }).first

if app.nil?
  puts "Creating test app with minimal files..."
  
  team = Team.first || Team.create!(name: "Test Team")
  membership = team.memberships.first || team.memberships.create!(
    user: User.first || User.create!(email: "test@example.com", password: "password"),
    role_ids: ["admin"]
  )
  
  app = App.create!(
    team: team,
    creator: membership,
    name: "Deployment Test",
    slug: "deployment-test-#{Time.now.to_i}",
    prompt: "Test",
    app_type: "saas",
    framework: "react",
    status: "generated",
    base_price: 0
  )
  
  # Create minimal files
  app.app_files.create!(
    team: team,
    path: "index.html",
    content: "<!DOCTYPE html><html><head><title>Test App</title></head><body><h1>Hello World</h1><script src='/app.js'></script></body></html>",
    file_type: "html"
  )
  
  app.app_files.create!(
    team: team,
    path: "app.js",
    content: "console.log('App loaded'); document.body.innerHTML += '<p>JavaScript works!</p>';",
    file_type: "js"
  )
  
  app.app_files.create!(
    team: team,
    path: "wrangler.toml",
    content: "name = 'app-#{app.id}'\nmain = 'worker.js'\ncompatibility_date = '2024-01-01'",
    file_type: "toml"
  )
end

puts "Using app: #{app.name} (#{app.id})"
puts "Files: #{app.app_files.count}"
app.app_files.each do |file|
  puts "  - #{file.path} (#{file.content.size} bytes)"
end

# Test deployment service
puts "\n📦 Testing CloudflarePreviewService:"
service = Deployment::CloudflarePreviewService.new(app)

# Check if we can generate worker script
puts "\n1. Generating Worker Script..."
begin
  # Access private method via send (for testing only)
  worker_script = service.send(:generate_worker_script)
  puts "  ✅ Worker script generated (#{worker_script.size} bytes)"
  
  # Check if files are embedded
  if worker_script.include?('index.html')
    puts "  ✅ Files embedded in worker script"
  else
    puts "  ❌ Files not embedded properly"
  end
  
  # Check environment variable handling
  if worker_script.include?('getPublicEnvVars')
    puts "  ✅ Environment variable injection configured"
  else
    puts "  ❌ Missing env var handling"
  end
  
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# Check deployment configuration
puts "\n2. Checking Deployment Configuration:"
config_checks = {
  'CLOUDFLARE_ACCOUNT_ID' => ENV['CLOUDFLARE_ACCOUNT_ID'].present?,
  'CLOUDFLARE_API_TOKEN' => ENV['CLOUDFLARE_API_TOKEN'].present?,
  'CLOUDFLARE_ZONE_ID' => ENV['CLOUDFLARE_ZONE_ID'].present?
}

config_checks.each do |key, present|
  if present
    puts "  ✅ #{key} configured"
  else
    puts "  ❌ #{key} missing (required for deployment)"
  end
end

# Test deployment (dry run)
puts "\n3. Testing Deployment (Dry Run):"
if config_checks.values.all?
  puts "  Would deploy to: preview-#{app.id}.overskill.app"
  puts "  Worker name: preview-#{app.id}"
  puts "  Route pattern: preview-#{app.id}.overskill.app/*"
  
  # Actually try to deploy if credentials are present
  puts "\n  Attempting actual deployment..."
  result = service.update_preview!
  
  if result[:success]
    puts "  ✅ Deployment successful!"
    puts "  Preview URL: #{result[:preview_url]}"
    puts "  Custom domain: #{result[:custom_domain_url]}"
  else
    puts "  ❌ Deployment failed: #{result[:error]}"
  end
else
  puts "  ⚠️  Cannot deploy - missing Cloudflare credentials"
  puts "  Set these environment variables:"
  puts "    export CLOUDFLARE_ACCOUNT_ID='your-account-id'"
  puts "    export CLOUDFLARE_API_TOKEN='your-api-token'"
  puts "    export CLOUDFLARE_ZONE_ID='your-zone-id'"
end

puts "\n=== Deployment Test Complete ==="