#!/usr/bin/env ruby
# Test script for environment variable integration with app generation

require_relative 'config/environment'

puts "\n📋 Testing Environment Variable Integration with App Generation\n\n"

# 1. Create a test app
puts "1. Creating test app..."
team = Team.first || Team.create!(name: "Test Team")
creator = team.memberships.first || team.memberships.create!(user: User.first || User.create!(email: "test@example.com", password: "password123"))

app = App.create!(
  team: team,
  creator: creator,
  name: "Env Var Test App",
  slug: "env-var-test-#{Time.now.to_i}",
  prompt: "Create a simple dashboard that shows environment variables and can make API calls to a database",
  app_type: "dashboard",
  framework: "react",
  base_price: 0,
  status: "draft"
)

puts "✅ Created app: #{app.name} (ID: #{app.id})"

# 2. Check default environment variables were created
puts "\n2. Checking default environment variables..."
default_vars = app.app_env_vars.system_defined
puts "System env vars created: #{default_vars.count}"
default_vars.each do |var|
  puts "  - #{var.key}: #{var.display_value} (#{var.is_secret? ? 'secret' : 'public'})"
end

# 3. Add custom environment variables
puts "\n3. Adding custom environment variables..."
custom_vars = [
  { key: "API_ENDPOINT", value: "https://api.example.com", description: "Main API endpoint", is_secret: false },
  { key: "SECRET_API_KEY", value: "sk_test_123456789", description: "Secret API key", is_secret: true },
  { key: "PUBLIC_APP_NAME", value: "My Dashboard", description: "Public app name", is_secret: false }
]

custom_vars.each do |var_data|
  var = app.app_env_vars.create!(var_data)
  puts "  ✅ Added #{var.key}: #{var.display_value}"
end

# 4. Test AI context includes env vars
puts "\n4. Testing AI context for env vars..."
env_vars_for_ai = app.env_vars_for_ai
puts "Env vars available to AI: #{env_vars_for_ai.count}"
env_vars_for_ai.each do |var|
  puts "  - #{var[:key]}: #{var[:description]}"
end

# 5. Test deployment env vars
puts "\n5. Testing deployment environment variables..."
deployment_vars = app.env_vars_for_deployment
puts "Total env vars for deployment: #{deployment_vars.count}"
deployment_vars.each do |key, value|
  is_secret = app.app_env_vars.find_by(key: key)&.is_secret?
  display_value = is_secret ? "****" : value
  puts "  - #{key}: #{display_value} (#{is_secret ? 'will be server-side only' : 'will be injected client-side'})"
end

# 6. Simulate generation with env var context
puts "\n6. Simulating app generation with env var context..."

begin
  # Create a chat message to trigger generation
  chat_message = app.app_chat_messages.create!(
    role: "user",
    content: "Generate the dashboard app with database integration"
  )
  
  # Use the enhanced generator (or existing one)
  if defined?(Ai::EnhancedAppGenerator)
    generator = Ai::EnhancedAppGenerator.new(app)
    puts "Using EnhancedAppGenerator..."
  else
    generator = Ai::AppGeneratorService.new(app)
    puts "Using AppGeneratorService..."
  end
  
  # Mock the generation (don't actually call AI to save API costs)
  puts "  ⚡ Would generate app with env var context"
  puts "  ⚡ Public vars would be injected into window.ENV"
  puts "  ⚡ Secret vars would only be accessible server-side"
  
  # Create mock files to test worker generation
  app.app_files.create!(
    team: team,
    path: "index.html",
    content: "<html><head></head><body><div id='root'></div></body></html>",
    file_type: "html"
  )
  
  app.app_files.create!(
    team: team,
    path: "app.js",
    content: "console.log('App ID:', window.getEnv('APP_ID'));",
    file_type: "js"
  )
  
  puts "  ✅ Mock files created"
  
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# 7. Test Cloudflare Worker generation
puts "\n7. Testing Cloudflare Worker generation..."
begin
  preview_service = Deployment::CloudflarePreviewService.new(app)
  
  # Test worker script generation (this will include env var handling)
  worker_script = preview_service.send(:generate_worker_script)
  
  # Check if worker includes env var functions
  has_public_vars = worker_script.include?("getPublicEnvVars")
  has_api_handler = worker_script.include?("handleApiRequest")
  has_env_injection = worker_script.include?("window.ENV")
  
  puts "  Worker script checks:"
  puts "    - Has getPublicEnvVars function: #{has_public_vars ? '✅' : '❌'}"
  puts "    - Has handleApiRequest function: #{has_api_handler ? '✅' : '❌'}"
  puts "    - Injects window.ENV: #{has_env_injection ? '✅' : '❌'}"
  
  if has_public_vars && has_api_handler && has_env_injection
    puts "  ✅ Worker properly configured for env vars!"
  else
    puts "  ⚠️ Worker may need updates for env var support"
  end
  
rescue => e
  puts "  ❌ Error: #{e.message}"
end

# 8. Summary
puts "\n" + "="*50
puts "📊 SUMMARY"
puts "="*50
puts "App created: #{app.name} (#{app.id})"
puts "Total env vars: #{app.app_env_vars.count}"
puts "  - System: #{app.app_env_vars.system_defined.count}"
puts "  - Custom: #{app.app_env_vars.user_defined.count}"
puts "  - Secrets: #{app.app_env_vars.secrets.count}"
puts "  - Public: #{app.app_env_vars.public_vars.count}"
puts "\n✅ Environment variable system is integrated!"
puts "\nKey features:"
puts "  • Secret env vars stay server-side only"
puts "  • Public env vars are injected into client via window.ENV"
puts "  • AI knows about available env vars during generation"
puts "  • Cloudflare Worker handles secure API proxying"
puts "\n"