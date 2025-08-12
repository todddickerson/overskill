#!/usr/bin/env ruby
# Simple test of Cloudflare Workers deployment without secrets

require_relative 'config/environment'

puts "🧪 Testing Simple Cloudflare Workers Deployment"
puts "=" * 60

def create_test_worker_script(app_id)
  # Create a minimal Cloudflare Worker script
  <<~JS
    addEventListener('fetch', event => {
      event.respondWith(handleRequest(event.request))
    })

    async function handleRequest(request) {
      const html = `<!DOCTYPE html>
<html>
<head>
  <title>V4 Test Deployment - App #{app_id}</title>
  <style>
    body { font-family: Arial, sans-serif; padding: 40px; max-width: 600px; margin: 0 auto; }
    .success { background: #d4edda; padding: 20px; border-radius: 5px; border-left: 4px solid #28a745; }
    .info { background: #d1ecf1; padding: 15px; border-radius: 5px; margin-top: 20px; }
  </style>
</head>
<body>
  <div class="success">
    <h1>✅ V4 Deployment Successful!</h1>
    <p><strong>App ID:</strong> #{app_id}</p>
    <p><strong>Deployed:</strong> ${new Date().toLocaleString()}</p>
    <p><strong>Worker Runtime:</strong> Cloudflare Workers</p>
  </div>
  
  <div class="info">
    <h3>🚀 Deployment Test Results</h3>
    <ul>
      <li>✅ Cloudflare API credentials working</li>
      <li>✅ Worker deployment successful</li>
      <li>✅ Service Worker format correct</li>
      <li>✅ HTML response working</li>
    </ul>
  </div>
  
  <p><small>This test validates core Cloudflare Workers deployment without environment secrets.</small></p>
</body>
</html>`;
      
      return new Response(html, {
        headers: { 
          'Content-Type': 'text/html',
          'Cache-Control': 'no-cache'
        }
      });
    }
  JS
end

def test_direct_worker_deployment
  puts "1. Testing direct Cloudflare Workers API..."
  
  # Create test app
  user = User.find_by(email: "test@example.com") || User.create!(
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  )
  
  team = user.teams.first || Team.create!(name: "Test Team")
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role: :admin)
  
  app = team.apps.create!(
    name: "Simple Cloudflare Test",
    creator: membership,
    prompt: "Test Cloudflare Workers deployment",
    slug: "simple-cf-test"
  )
  
  puts "   📱 Created test app: #{app.name} (ID: #{app.id})"
  
  # Create worker script
  worker_script = create_test_worker_script(app.id)
  puts "   📝 Generated worker script (#{worker_script.bytesize} bytes)"
  
  # Test direct deployment
  account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
  api_token = ENV['CLOUDFLARE_API_TOKEN']
  worker_name = "simple-test-app-#{app.id}"
  
  puts "   🌐 Deploying to worker: #{worker_name}"
  
  require 'net/http'
  require 'uri'
  require 'json'
  
  uri = URI("https://api.cloudflare.com/client/v4/accounts/#{account_id}/workers/scripts/#{worker_name}")
  
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  
  request = Net::HTTP::Put.new(uri)
  request['Authorization'] = "Bearer #{api_token}"
  request['Content-Type'] = 'application/javascript'
  request.body = worker_script
  
  response = http.request(request)
  
  puts "   📊 Response: HTTP #{response.code}"
  puts "   📄 Response body: #{response.body[0..200]}..."
  
  if response.code == '200'
    response_data = JSON.parse(response.body)
    
    if response_data['success']
      puts "   ✅ Worker deployment successful!"
      
      worker_url = "https://#{worker_name}.#{account_id}.workers.dev"
      puts "   🔗 Worker URL: #{worker_url}"
      
      # Update app with URL
      app.update!(
        preview_url: worker_url,
        status: 'deployed'
      )
      
      return {
        success: true,
        worker_name: worker_name,
        worker_url: worker_url,
        app: app
      }
    else
      puts "   ❌ Deployment failed: #{response_data['errors']}"
      return { success: false, error: response_data['errors'] }
    end
  else
    puts "   ❌ HTTP Error: #{response.code} #{response.message}"
    return { success: false, error: "HTTP #{response.code}" }
  end
rescue => e
  puts "   ❌ Deployment error: #{e.message}"
  puts "   📍 #{e.backtrace&.first}"
  return { success: false, error: e.message }
end

def test_worker_accessibility(result)
  return unless result[:success] && result[:worker_url]
  
  puts "2. Testing worker accessibility..."
  
  begin
    require 'net/http'
    require 'uri'
    
    uri = URI(result[:worker_url])
    puts "   🌐 Testing: #{uri}"
    
    response = Net::HTTP.get_response(uri)
    
    if response.code == '200'
      puts "   ✅ Worker accessible!"
      puts "   📦 Content-Type: #{response['Content-Type']}"
      puts "   📄 Response size: #{response.body.length} bytes"
      puts "   🔍 HTML content detected: #{response.body.include?('V4 Deployment Successful') ? 'Yes' : 'No'}"
      return true
    else
      puts "   ❌ Not accessible: HTTP #{response.code}"
      return false
    end
  rescue => e
    puts "   ⚠️ Accessibility test failed: #{e.message}"
    return false
  end
end

# Main execution
puts "Starting simple Cloudflare deployment test..."
result = test_direct_worker_deployment
accessible = test_worker_accessibility(result) if result[:success]

puts "\n" + "=" * 60
puts "🎯 Simple Cloudflare Deployment Results"
puts "=" * 60

if result[:success]
  puts "✅ **DEPLOYMENT SUCCESSFUL**"
  puts "   🌐 Worker URL: #{result[:worker_url]}"
  puts "   📝 Worker Name: #{result[:worker_name]}"
  puts "   📱 App ID: #{result[:app]&.id}"
  
  if accessible
    puts "   ✅ Worker is accessible via HTTP"
    puts "\n🔗 **Test your deployment**: #{result[:worker_url]}"
  else
    puts "   ⚠️ Worker accessibility unknown - test manually"
  end
  
  puts "\n🎉 **V4 Core Deployment Working!**"
  puts "   Ready to integrate with V4 generation pipeline"
  puts "   Next: Add secrets management and routing"
  
else
  puts "❌ **DEPLOYMENT FAILED**"
  puts "   Error: #{result[:error]}"
  puts "   Check Cloudflare credentials and permissions"
end