#!/usr/bin/env rails runner

puts "=" * 60
puts "Testing Production Deployment with Unique Subdomains"
puts "=" * 60

# Find a ready app to test with
app = App.where(status: 'ready').where.not(preview_url: nil).last

unless app
  puts "No ready apps found. Creating a test app..."
  
  user = User.first
  team = user&.teams&.first
  membership = team&.memberships&.where(user: user)&.first
  
  unless user && team && membership
    puts "❌ Missing required data"
    exit 1
  end
  
  app = App.create!(
    name: "Production Test App",
    team: team,
    creator: membership,
    prompt: "Test app for production deployment",
    status: 'ready',
    app_type: 'tool'
  )
  
  # Create a simple file
  app.app_files.create!(
    team: team,
    path: "index.html",
    content: "<html><body><h1>Production Test</h1></body></html>"
  )
  
  # Set preview URL manually for testing
  app.update!(preview_url: "https://preview-#{app.id}.overskill.app")
end

puts "\n📱 Using app: #{app.name} (ID: #{app.id})"
puts "   Current status: #{app.status}"
puts "   Preview URL: #{app.preview_url}"
puts "   Slug: #{app.slug}"
puts "   Subdomain: #{app.subdomain || 'Not set'}"

# Test subdomain generation
puts "\n1️⃣ Testing subdomain generation..."
if app.subdomain.nil?
  app.send(:generate_subdomain)
  app.save!
  puts "   ✅ Generated subdomain: #{app.subdomain}"
else
  puts "   ℹ️  Subdomain already set: #{app.subdomain}"
end

# Test can_publish? method
puts "\n2️⃣ Testing publish readiness..."
if app.can_publish?
  puts "   ✅ App can be published"
else
  puts "   ❌ App cannot be published"
  puts "      Status: #{app.status}"
  puts "      Preview URL: #{app.preview_url || 'Missing'}"
  puts "      Files: #{app.app_files.count}"
end

# Test production URL generation
puts "\n3️⃣ Testing production URL..."
puts "   Published URL would be: #{app.published_url}"

# Test subdomain uniqueness
puts "\n4️⃣ Testing subdomain uniqueness..."
test_subdomain = "test-app-#{Time.current.to_i}"
existing = App.where(subdomain: test_subdomain).exists?
puts "   Testing subdomain: #{test_subdomain}"
puts "   Available: #{!existing}"

# Test publishing to production
puts "\n5️⃣ Testing production deployment..."
if app.can_publish?
  puts "   Simulating publish_to_production!..."
  
  begin
    result = app.publish_to_production!
    
    if result[:success]
      puts "   ✅ Deployment successful!"
      puts "      Production URL: #{result[:production_url]}"
      puts "      Worker name: #{result[:worker_name]}"
      puts "      Subdomain: #{result[:subdomain]}"
    else
      puts "   ❌ Deployment failed: #{result[:error]}"
    end
  rescue => e
    puts "   ❌ Error during deployment: #{e.message}"
    puts "      #{e.backtrace.first}"
  end
else
  puts "   ⚠️  Skipping deployment - app not ready"
end

# Check final state
puts "\n6️⃣ Final app state:"
app.reload
puts "   Status: #{app.status}"
puts "   Subdomain: #{app.subdomain}"
puts "   Production URL: #{app.production_url || 'Not set'}"
puts "   Published: #{app.published?}"
puts "   Published at: #{app.published_at || 'Never'}"

# Test subdomain update
puts "\n7️⃣ Testing subdomain update..."
new_subdomain = "updated-#{Time.current.to_i}"
puts "   Attempting to change subdomain to: #{new_subdomain}"

begin
  result = app.update_subdomain!(new_subdomain)
  
  if result[:success]
    puts "   ✅ Subdomain updated successfully"
    puts "      New URL: #{result[:new_url]}"
  else
    puts "   ❌ Failed to update: #{result[:error]}"
  end
rescue => e
  puts "   ❌ Error: #{e.message}"
end

puts "\n" + "=" * 60
puts "Test completed"
puts "=" * 60