#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Deployment Step Debug"
puts "="*40

# Get test app
app = App.last
puts "📱 Test App: #{app.name} (#{app.id})"

# Test each step individually
service = Deployment::FastPreviewService.new(app)

puts "\n1️⃣ Testing worker script generation..."
begin
  worker_script = service.send(:generate_fast_preview_worker)
  puts "✅ Worker script generated (#{worker_script.length} chars)"
rescue => e
  puts "❌ Worker script error: #{e.message}"
  exit
end

puts "\n2️⃣ Testing worker upload..."
worker_name = "debug-preview-#{app.id}"
begin
  upload_response = service.send(:upload_worker, worker_name, worker_script)
  puts "✅ Worker upload: #{upload_response['success'] ? 'Success' : 'Failed'}"
  puts "   Response: #{upload_response}"
rescue => e
  puts "❌ Worker upload error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
  exit
end

puts "\n3️⃣ Testing environment variables setup..."
begin
  service.send(:set_worker_env_vars, worker_name)
  puts "✅ Environment variables set"
rescue => e
  puts "❌ Environment variables error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(5).join("\n   ")}"
end

puts "\n4️⃣ Testing route setup..."
begin
  subdomain = "debug-preview-#{app.id}"
  service.send(:ensure_preview_route, subdomain, worker_name)
  puts "✅ Route configured"
rescue => e
  puts "❌ Route setup error: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
end

puts "\n✅ Debug complete!"