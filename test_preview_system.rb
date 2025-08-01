#!/usr/bin/env ruby
# Test script for the new preview system with auto-preview URLs
# Run in Rails console: rails c

puts "=== OverSkill Preview System Test ==="
puts
puts "Preview URL Structure:"
puts "  1. Auto-preview: preview-{app-id}.overskill.app (always latest)"
puts "  2. Staging: preview--{app-name}.overskill.app"
puts "  3. Production: {app-name}.overskill.app"
puts

puts "# Step 1: Check environment variables"
puts "---"
puts <<-'RUBY'
# Check required environment variables
env_vars = {
  api_token: ENV['CLOUDFLARE_API_TOKEN'] || ENV['CLOUDFLARE_API_KEY'],
  account_id: ENV['CLOUDFLARE_ACCOUNT_ID'],
  zone_id: ENV['CLOUDFLARE_ZONE_ID'] || ENV['CLOUDFLARE_ZONE']
}

puts "Environment status:"
env_vars.each do |key, value|
  status = value.present? ? "✅ Set" : "❌ Missing"
  puts "  #{key}: #{status}"
end

missing = env_vars.select { |k,v| v.blank? }.keys
if missing.any?
  puts "\n⚠️  Missing: #{missing.join(', ')}"
  puts "Add CLOUDFLARE_ZONE_ID to your .env for the overskill.app zone"
end
RUBY

puts "\n# Step 2: Find app and check preview URLs"
puts "---"
puts <<-'RUBY'
# Find the app
app = App.find_by(id: 'wJGvjb') || App.first

if app
  puts "App: #{app.name} (ID: #{app.id})"
  puts "\nCurrent URLs:"
  puts "  Auto-preview: #{app.preview_url || 'not set'}"
  puts "  Staging: #{app.staging_url || 'not deployed'}"
  puts "  Production: #{app.deployment_url || 'not deployed'}"
  puts "\nExpected URLs:"
  puts "  Auto-preview: https://preview-#{app.id}.overskill.app"
  puts "  Staging: https://preview--#{app.name.parameterize}.overskill.app"
  puts "  Production: https://#{app.name.parameterize}.overskill.app"
end
RUBY

puts "\n# Step 3: Test preview service without API calls"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first
service = Deployment::CloudflarePreviewService.new(app)

# Test subdomain generation
subdomain = service.send(:generate_app_subdomain)
puts "App subdomain: #{subdomain}"

# Check worker script
script = service.send(:generate_worker_script)
puts "\nWorker script includes:"
puts "  - CORS headers: #{script.include?('Access-Control-Allow-Origin') ? '✅' : '❌'}"
puts "  - No-cache headers: #{script.include?('no-cache') ? '✅' : '❌'}"
puts "  - File serving: #{script.include?('serveFile') ? '✅' : '❌'}"
RUBY

puts "\n# Step 4: Update auto-preview (if credentials present)"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first

if ENV['CLOUDFLARE_API_TOKEN'].present?
  puts "🔄 Updating auto-preview..."
  
  service = Deployment::CloudflarePreviewService.new(app)
  result = service.update_preview!
  
  if result[:success]
    puts "✅ Auto-preview updated!"
    puts "URL: #{result[:preview_url]}"
    app.reload
    puts "Preview URL saved: #{app.preview_url}"
  else
    puts "❌ Update failed: #{result[:error]}"
  end
else
  puts "⚠️  Skipping - no Cloudflare credentials"
end
RUBY

puts "\n# Step 5: Test deployment to staging"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first

if ENV['CLOUDFLARE_API_TOKEN'].present?
  puts "🚀 Deploying to staging..."
  
  service = Deployment::CloudflarePreviewService.new(app)
  result = service.deploy_staging!
  
  if result[:success]
    puts "✅ Staging deployment successful!"
    puts "URL: #{result[:deployment_url]}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
else
  puts "⚠️  Skipping - no Cloudflare credentials"
end
RUBY

puts "\n# Step 6: Simulate preview URLs (for testing without Cloudflare)"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first

# Simulate all three URLs
app.update!(
  preview_url: "https://preview-#{app.id}.overskill.app",
  staging_url: "https://preview--#{app.name.parameterize}.overskill.app",
  deployment_url: "https://#{app.name.parameterize}.overskill.app",
  deployment_status: 'deployed',
  deployed_at: Time.current,
  staging_deployed_at: Time.current,
  preview_updated_at: Time.current
)

puts "✅ Simulated URLs set!"
puts "  Auto-preview: #{app.preview_url}"
puts "  Staging: #{app.staging_url}"
puts "  Production: #{app.deployment_url}"
puts "\nThe preview tab should now use: #{app.preview_url}"
RUBY

puts "\n# Step 7: Test file update triggers preview update"
puts "---"
puts <<-'RUBY'
app = App.find_by(id: 'wJGvjb') || App.first

# Update a file to trigger preview update
file = app.app_files.first
if file
  old_content = file.content
  new_content = old_content + "\n// Updated at #{Time.current}"
  
  file.update!(content: new_content)
  puts "✅ Updated #{file.path}"
  
  # This should have queued UpdatePreviewJob
  puts "Preview update job should be queued"
  
  # Check Sidekiq queues
  require 'sidekiq/api'
  queues = Sidekiq::Queue.all.map { |q| "#{q.name}: #{q.size}" }
  puts "Sidekiq queues: #{queues.join(', ')}"
end
RUBY

puts "\n# Testing in the browser"
puts "---"
puts <<-TEXT
1. Visit: http://localhost:3000/account/apps/wJGvjb/editor
2. The preview should show the auto-preview URL if set
3. Try editing a file - it should queue a preview update
4. The Deploy button deploys to production by default
5. Future: Add staging deploy button

If using simulated URLs (Step 6), the preview will still use Rails
preview but shows the correct URL structure.
TEXT