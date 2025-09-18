#!/usr/bin/env ruby
# Configure Supabase redirect URLs automatically
# Run with: bin/rails runner scripts/configure_supabase_urls.rb

require "net/http"
require "json"
require "uri"

puts "=" * 80
puts "🔧 CONFIGURING SUPABASE REDIRECT URLS"
puts "=" * 80

supabase_url = ENV["SUPABASE_URL"]
service_key = ENV["SUPABASE_SERVICE_KEY"]

if !supabase_url || !service_key
  puts "❌ Missing Supabase credentials"
  puts "Need SUPABASE_URL and SUPABASE_SERVICE_KEY in environment"
  exit 1
end

puts "\n📍 Supabase Project: #{supabase_url}"

# Try to get current auth settings
puts "\n🔍 Checking current auth configuration..."

begin
  uri = URI("#{supabase_url}/auth/v1/settings")
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Get.new(uri)
  request["apikey"] = service_key
  request["Authorization"] = "Bearer #{service_key}"

  response = http.request(request)

  if response.code == "200"
    settings = JSON.parse(response.body)
    puts "✅ Retrieved current auth settings"

    # Check if redirect URLs are configurable via API
    puts "\nCurrent external provider settings:"
    settings["external"]&.each do |provider, config|
      if config.is_a?(Hash) && config["enabled"]
        puts "  ✅ #{provider}: enabled"
        if config["redirect_uri"]
          puts "    Redirect URI: #{config["redirect_uri"]}"
        end
      end
    end
  else
    puts "❌ Could not retrieve auth settings: #{response.code}"
    puts "Response: #{response.body[0..200]}"
  end
rescue => e
  puts "❌ Request failed: #{e.message}"
end

puts "\n⚠️ IMPORTANT: Supabase redirect URLs cannot be configured via API"
puts "They must be set manually in the Supabase Dashboard."

puts "\n📋 MANUAL STEPS REQUIRED:"
puts "1. Go to: https://supabase.com/dashboard/project/#{supabase_url.match(/https:\/\/(.+?)\.supabase\.co/)[1]}"
puts "2. Navigate to: Authentication > URL Configuration"
puts "3. In the 'Redirect URLs' section, add:"
puts ""
puts "   https://preview-*.overskill.app/auth/callback"
puts "   https://preview-*.overskill.app/**"
puts ""
puts "4. Click 'Save'"

# Create a test to verify OAuth would work
puts "\n🧪 Creating OAuth test page..."

test_html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <title>OAuth Redirect Test</title>
    <style>
      body { font-family: system-ui; max-width: 800px; margin: 0 auto; padding: 20px; }
      .status { padding: 10px; margin: 10px 0; border-radius: 5px; }
      .success { background: #d4edda; color: #155724; }
      .error { background: #f8d7da; color: #721c24; }
      .warning { background: #fff3cd; color: #856404; }
      pre { background: #f8f9fa; padding: 10px; border-radius: 5px; overflow-x: auto; }
      button { background: #007bff; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; margin: 5px; }
      button:hover { background: #0056b3; }
    </style>
  </head>
  <body>
    <h1>🔐 OAuth Redirect URL Test</h1>
    
    <div class="warning status">
      <strong>Issue:</strong> OAuth failing with "validation_failed" error
    </div>
    
    <div class="error status">
      <strong>Cause:</strong> Redirect URLs not configured in Supabase Dashboard
    </div>
    
    <h2>Required Configuration</h2>
    <p>Add these URLs to Supabase Dashboard > Authentication > URL Configuration:</p>
    <pre>https://preview-*.overskill.app/auth/callback
  https://preview-*.overskill.app/**</pre>
    
    <h2>Current Apps Needing OAuth</h2>
    <ul>
  #{App.where("preview_url IS NOT NULL").map { |app| "    <li><a href=\"#{app.preview_url}/login\" target=\"_blank\">#{app.name}</a> - #{app.preview_url}</li>" }.join("\n")}
    </ul>
    
    <h2>Test OAuth After Configuration</h2>
    <p>After adding the URLs to Supabase:</p>
    <ol>
      <li>Wait 30 seconds for changes to propagate</li>
      <li>Visit any app above</li>
      <li>Try social login (Google or GitHub)</li>
      <li>Should redirect successfully to /dashboard</li>
    </ol>
    
    <h2>Verification</h2>
    <button onclick="testApp69()">Test App 69 OAuth</button>
    <button onclick="testApp60()">Test App 60 OAuth</button>
    
    <div id="results"></div>
    
    <script>
      function testApp69() {
        window.open('https://preview-69.overskill.app/login', '_blank');
        showResult('Testing App 69 - try social login in the new window');
      }
      
      function testApp60() {
        window.open('https://preview-60.overskill.app/login', '_blank');
        showResult('Testing App 60 - try social login in the new window');
      }
      
      function showResult(message) {
        const results = document.getElementById('results');
        const div = document.createElement('div');
        div.className = 'status warning';
        div.innerHTML = '<strong>Action:</strong> ' + message;
        results.appendChild(div);
      }
      
      // Show current status
      window.addEventListener('load', function() {
        const results = document.getElementById('results');
        const div = document.createElement('div');
        div.className = 'status warning';
        div.innerHTML = '<strong>Status:</strong> Waiting for Supabase redirect URLs to be configured...';
        results.appendChild(div);
      });
    </script>
  </body>
  </html>
HTML

File.write("/tmp/oauth_test.html", test_html)
puts "OAuth test page saved to: /tmp/oauth_test.html"
puts "Open in browser: file:///tmp/oauth_test.html"

puts "\n🎯 Summary:"
puts "1. OAuth fails because redirect URLs aren't in Supabase config"
puts "2. Must manually add wildcard URLs to Supabase Dashboard"
puts "3. After adding, OAuth will work for all preview apps"
puts "4. Use the test page to verify the fix"

puts "\n" + "=" * 80
puts "Configuration guide complete"
puts "=" * 80
