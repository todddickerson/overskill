#!/usr/bin/env ruby
# Debug authentication issue for app 69
# Run with: bin/rails runner scripts/debug_auth_issue.rb

require 'net/http'
require 'json'
require 'uri'

puts "=" * 80
puts "🔍 DEBUGGING AUTHENTICATION ISSUE - APP 69"
puts "=" * 80

app = App.find(69)
puts "\n📱 App ##{app.id}: #{app.name}"
puts "  Preview URL: #{app.preview_url}"

# Check Supabase configuration in Rails
puts "\n🔧 Rails Environment Variables:"
puts "  SUPABASE_URL: #{ENV['SUPABASE_URL'] || 'NOT SET'}"
puts "  SUPABASE_ANON_KEY: #{ENV['SUPABASE_ANON_KEY'] ? 'SET (hidden)' : 'NOT SET'}"
puts "  SUPABASE_SERVICE_KEY: #{ENV['SUPABASE_SERVICE_KEY'] ? 'SET (hidden)' : 'NOT SET'}"

# Check what's being injected into the app
preview_service = Deployment::CloudflarePreviewService.new(app)
env_vars = preview_service.send(:build_env_vars_for_app, :preview)

puts "\n📦 Environment Variables Injected into App:"
puts "  SUPABASE_URL: #{env_vars['SUPABASE_URL'] || 'NOT SET'}"
puts "  SUPABASE_ANON_KEY: #{env_vars['SUPABASE_ANON_KEY'] ? 'SET (hidden)' : 'NOT SET'}"

# Test Supabase connection directly
if ENV['SUPABASE_URL'] && ENV['SUPABASE_ANON_KEY']
  puts "\n🔗 Testing Supabase Connection:"
  
  begin
    uri = URI("#{ENV['SUPABASE_URL']}/rest/v1/")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    
    request = Net::HTTP::Get.new(uri)
    request['apikey'] = ENV['SUPABASE_ANON_KEY']
    request['Authorization'] = "Bearer #{ENV['SUPABASE_ANON_KEY']}"
    
    response = http.request(request)
    
    if response.code == '200'
      puts "  ✅ Supabase is reachable"
    else
      puts "  ❌ Supabase returned: #{response.code} #{response.message}"
      puts "  Response: #{response.body[0..200]}"
    end
  rescue => e
    puts "  ❌ Connection error: #{e.message}"
  end
end

# Check the supabase.ts file content
puts "\n📄 Checking src/lib/supabase.ts:"
supabase_file = app.app_files.find_by(path: 'src/lib/supabase.ts')
if supabase_file
  puts "  File exists (#{supabase_file.content.length} bytes)"
  
  # Check if it's using the correct env var names
  content = supabase_file.content
  
  checks = {
    'VITE_SUPABASE_URL' => content.include?('VITE_SUPABASE_URL'),
    'SUPABASE_URL' => content.include?('SUPABASE_URL'),
    'window.ENV' => content.include?('window.ENV'),
    'import.meta.env' => content.include?('import.meta.env'),
    'Error handling' => content.include?('Configuration Error')
  }
  
  checks.each do |check, present|
    puts "  #{present ? '✅' : '❌'} Contains '#{check}'"
  end
else
  puts "  ❌ File not found!"
end

# Check auth settings
puts "\n🔐 Auth Settings:"
if app.app_auth_setting
  settings = app.app_auth_setting
  puts "  Visibility: #{settings.visibility}"
  puts "  Requires Auth: #{settings.requires_authentication?}"
  puts "  Allow Signups: #{settings.allow_signups}"
  puts "  Providers: #{settings.allowed_providers.join(', ')}"
else
  puts "  ❌ No auth settings configured"
end

# Generate a test HTML file to check client-side
puts "\n🧪 Generating Test HTML..."
test_html = <<~HTML
  <!DOCTYPE html>
  <html>
  <head>
    <title>Auth Debug Test</title>
  </head>
  <body>
    <h1>Debugging App 69 Authentication</h1>
    <div id="results"></div>
    
    <script>
      // Check what environment variables are available
      const results = document.getElementById('results');
      
      function addResult(label, value, isGood = null) {
        const div = document.createElement('div');
        const icon = isGood === true ? '✅' : isGood === false ? '❌' : '📋';
        div.innerHTML = icon + ' <strong>' + label + ':</strong> ' + value;
        results.appendChild(div);
      }
      
      // Check window.ENV
      if (window.ENV) {
        addResult('window.ENV exists', 'YES', true);
        addResult('SUPABASE_URL', window.ENV.SUPABASE_URL || 'NOT SET', !!window.ENV.SUPABASE_URL);
        addResult('SUPABASE_ANON_KEY', window.ENV.SUPABASE_ANON_KEY ? 'SET (hidden)' : 'NOT SET', !!window.ENV.SUPABASE_ANON_KEY);
      } else {
        addResult('window.ENV exists', 'NO', false);
      }
      
      // Try to load the app and see what happens
      addResult('Test URL', '#{app.preview_url}');
      
      // Provide instructions
      const instructions = document.createElement('div');
      instructions.style.marginTop = '20px';
      instructions.style.padding = '10px';
      instructions.style.backgroundColor = '#f0f0f0';
      instructions.innerHTML = `
        <h3>Manual Test Steps:</h3>
        <ol>
          <li>Open browser console (F12)</li>
          <li>Visit <a href="#{app.preview_url}" target="_blank">#{app.preview_url}</a></li>
          <li>Check for red error overlay</li>
          <li>In console, type: <code>window.ENV</code></li>
          <li>Look for any Supabase errors</li>
        </ol>
      `;
      document.body.appendChild(instructions);
    </script>
  </body>
  </html>
HTML

File.write('/tmp/auth_debug.html', test_html)
puts "  Test file saved to: /tmp/auth_debug.html"
puts "  Open in browser: file:///tmp/auth_debug.html"

puts "\n📝 Diagnosis Summary:"
puts "  1. Check if Supabase credentials are set in Rails environment"
puts "  2. Verify they're being injected into the Cloudflare Worker"
puts "  3. Confirm the client is checking the right variable names"
puts "  4. Visit #{app.preview_url} and check browser console"

puts "\n" + "=" * 80
puts "Debug script complete"
puts "=" * 80