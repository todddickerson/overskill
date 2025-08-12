#!/usr/bin/env rails runner

puts "Testing V4 Enhanced with Cloudflare credentials..."
puts "=" * 50

# Verify credentials are loaded
if ENV['CLOUDFLARE_ACCOUNT_ID'].present? && ENV['CLOUDFLARE_API_TOKEN'].present?
  puts "✅ Cloudflare credentials loaded:"
  puts "   Account ID: #{ENV['CLOUDFLARE_ACCOUNT_ID'][0..10]}..."
  puts "   API Token: #{ENV['CLOUDFLARE_API_TOKEN'][0..10]}..."
  puts "   Zone ID: #{ENV['CLOUDFLARE_ZONE_ID'][0..10]}..."
else
  puts "❌ Cloudflare credentials missing!"
  exit 1
end

# Find existing user and team
user = User.first
team = user&.teams&.first
membership = team&.memberships&.where(user: user)&.first

unless user && team && membership
  puts "❌ Missing required data"
  exit 1
end

# Create a simple test app
app = App.create!(
  name: "V4 Creds Test #{Time.current.strftime('%H%M%S')}",
  team: team,
  creator: membership,
  prompt: "Create a simple hello world app",
  status: 'generating',
  app_type: 'tool'
)

puts "\nCreated app: #{app.name} (ID: #{app.id})"

# Create a simple HTML file to deploy
app_file = AppFile.create!(
  app: app,
  team: team,
  path: "index.html",
  content: <<~HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Hello from App #{app.id}</title>
    </head>
    <body>
      <h1>Hello World!</h1>
      <p>App #{app.id} deployed at #{Time.current}</p>
      <p>Cloudflare deployment test successful!</p>
    </body>
    </html>
  HTML
)

puts "Created test HTML file"

# Test deployment directly
require_relative 'app/services/deployment/external_vite_builder'
require_relative 'app/services/deployment/cloudflare_workers_deployer'

begin
  # Build the worker code
  builder = Deployment::ExternalViteBuilder.new(app)
  worker_code = builder.send(:wrap_for_worker_deployment_hybrid, app_file.content, [])
  
  puts "\nGenerated worker code (#{worker_code.bytesize} bytes)"
  
  # Deploy to Cloudflare
  deployer = Deployment::CloudflareWorkersDeployer.new(app)
  result = deployer.deploy_with_secrets(
    built_code: worker_code,
    deployment_type: :preview
  )
  
  if result[:success]
    puts "\n✅ Deployment successful!"
    puts "   Worker name: #{result[:worker_name]}"
    puts "   Worker URL: #{result[:worker_url]}"
    puts "\n🔗 Visit: #{result[:worker_url]}"
    
    # Update app with URL
    app.update!(preview_url: result[:worker_url], status: 'ready')
  else
    puts "\n❌ Deployment failed: #{result[:error]}"
  end
  
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n" + "=" * 50
puts "Test completed"