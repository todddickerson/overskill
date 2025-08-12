#!/usr/bin/env ruby
# Test Cloudflare credentials configuration

require_relative 'config/environment'

puts "🔍 Testing Cloudflare Credentials Configuration"
puts "=" * 60

# Check environment variables
required_env_vars = [
  'CLOUDFLARE_ACCOUNT_ID',
  'CLOUDFLARE_ZONE_ID', 
  'CLOUDFLARE_API_TOKEN',
  'CLOUDFLARE_EMAIL',
  'CLOUDFLARE_R2_BUCKET',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_KEY'
]

puts "1. Checking environment variables..."
missing_vars = []
required_env_vars.each do |var|
  if ENV[var].present?
    puts "   ✅ #{var}: #{ENV[var][0..20]}..." if ENV[var].length > 20
    puts "   ✅ #{var}: #{ENV[var]}" if ENV[var].length <= 20
  else
    missing_vars << var
    puts "   ❌ #{var}: NOT SET"
  end
end

if missing_vars.any?
  puts "\n⚠️ Missing environment variables: #{missing_vars.join(', ')}"
  puts "Check your .env.local file"
  exit 1
end

puts "\n2. Testing Cloudflare service initialization..."

begin
  # Create test app
  user = User.find_by(email: "test@example.com") || User.create!(
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  )
  
  team = user.teams.first || Team.create!(name: "Test Team")
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role: :admin)
  
  app = team.apps.first || team.apps.create!(
    name: "Test Cloudflare App",
    creator: membership,
    prompt: "Test app for Cloudflare integration"
  )
  
  puts "   📱 Using app: #{app.name} (ID: #{app.id})"
  
  # Test CloudflareApiClient
  puts "\n   Testing CloudflareApiClient..."
  api_client = Deployment::CloudflareApiClient.new(app)
  puts "   ✅ CloudflareApiClient initialized successfully"
  
  # Test CloudflareWorkersDeployer
  puts "\n   Testing CloudflareWorkersDeployer..."
  workers_deployer = Deployment::CloudflareWorkersDeployer.new(app)
  puts "   ✅ CloudflareWorkersDeployer initialized successfully"
  
  # Test NodejsBuildExecutor
  puts "\n   Testing NodejsBuildExecutor..."
  build_executor = Deployment::NodejsBuildExecutor.new(app)
  puts "   ✅ NodejsBuildExecutor initialized successfully"
  
  puts "\n🎉 All Cloudflare services initialized successfully!"
  puts "\n✅ Credentials Configuration Summary:"
  puts "   • Cloudflare Account ID: #{ENV['CLOUDFLARE_ACCOUNT_ID']}"
  puts "   • Cloudflare Zone ID: #{ENV['CLOUDFLARE_ZONE_ID']}"
  puts "   • Cloudflare Email: #{ENV['CLOUDFLARE_EMAIL']}"
  puts "   • R2 Bucket: #{ENV['CLOUDFLARE_R2_BUCKET']}"
  puts "   • Supabase Project: #{ENV['SUPABASE_URL'].split('.').first.split('//').last if ENV['SUPABASE_URL']}"
  
  puts "\n🚀 Ready for V4 deployment testing!"
  puts "   Next step: Test actual deployment with V4 generation"
  
rescue => e
  puts "   ❌ Initialization failed: #{e.message}"
  puts "   Error class: #{e.class.name}"
  puts "   Backtrace: #{e.backtrace&.first(3)&.join("\n   ")}"
  exit 1
end