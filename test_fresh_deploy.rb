#!/usr/bin/env rails runner

puts "Creating a fresh app to test production deployment..."

# Find existing user and team
user = User.first
team = user&.teams&.first
membership = team&.memberships&.where(user: user)&.first

unless user && team && membership
  puts "❌ Missing required data"
  exit 1
end

# Create a new test app
app = App.create!(
  name: "Deploy Test #{Time.current.strftime('%H%M%S')}",
  team: team,
  creator: membership,
  prompt: "Test app for deployment",
  status: 'ready',
  app_type: 'tool'
)

# Create a simple file
app.app_files.create!(
  team: team,
  path: "index.html",
  content: <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Deploy Test</title>
    </head>
    <body>
      <h1>Hello from #{app.name}!</h1>
      <p>This is a test deployment at #{Time.current}</p>
    </body>
    </html>
  HTML
)

# Set preview URL to make it publishable
app.update!(preview_url: "https://preview-#{app.id}.overskill.app")

puts "Created app: #{app.name} (ID: #{app.id})"
puts "Status: #{app.status}"
puts "Can publish?: #{app.can_publish?}"

if app.can_publish?
  puts "\nTesting production deployment..."
  
  begin
    result = app.publish_to_production!
    
    if result[:success]
      puts "✅ Deployment successful!"
      puts "   Production URL: #{result[:production_url]}"
      puts "   Subdomain: #{result[:subdomain]}"
    else
      puts "❌ Deployment failed: #{result[:error]}"
    end
  rescue => e
    puts "❌ Error: #{e.message}"
    puts "   Backtrace: #{e.backtrace.first(3).join("\n")}"
  end
else
  puts "❌ App cannot be published"
end