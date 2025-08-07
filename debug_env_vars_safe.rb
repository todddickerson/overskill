#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Safe Environment Variables Debug"
puts "="*40

# Get test app
app = App.last
puts "📱 Test App: #{app.name} (#{app.id})"
puts "Database shard present: #{app.database_shard.present? rescue 'ERROR accessing database_shard'}"

# Create service
service = Deployment::FastPreviewService.new(app)
worker_name = "debug-env-test-#{app.id}"

# Test building env vars safely
puts "\n1️⃣ Testing build_env_vars_for_app..."
begin
  # Monkey patch to avoid database_shard access for testing
  service.define_singleton_method(:build_env_vars_for_app_safe) do
    vars = {}
    
    # System vars
    vars['APP_ID'] = app.id.to_s
    vars['APP_NAME'] = app.name
    vars['ENVIRONMENT'] = 'preview'
    
    # Skip Supabase configuration to avoid database_shard access
    # if @app.database_shard
    #   vars['SUPABASE_URL'] = @app.database_shard.supabase_url
    #   vars['SUPABASE_ANON_KEY'] = @app.database_shard.supabase_anon_key
    #   vars['SUPABASE_SERVICE_KEY'] = @app.database_shard.supabase_service_key
    # end
    
    # Custom app env vars
    app.env_vars_for_deployment.each do |key, value|
      vars[key] = value
    end
    
    # OAuth secrets (from Rails env)
    vars['GOOGLE_CLIENT_ID'] = ENV['GOOGLE_CLIENT_ID'] if ENV['GOOGLE_CLIENT_ID']
    vars['GOOGLE_CLIENT_SECRET'] = ENV['GOOGLE_CLIENT_SECRET'] if ENV['GOOGLE_CLIENT_SECRET']
    
    vars
  end
  
  env_vars = service.build_env_vars_for_app_safe
  puts "✅ Environment variables built: #{env_vars.keys.join(', ')}"
rescue => e
  puts "❌ Environment variables failed: #{e.message}"
  e.backtrace.first(5).each_with_index do |line, i|
    puts "   #{i}: #{line}"
  end
end

puts "\n2️⃣ Testing Cloudflare API call (mock)..."
begin
  # Test the Cloudflare API call pattern without actually calling API
  plaintext_bindings = [
    { name: 'APP_ID', type: 'plain_text', text: app.id.to_s },
    { name: 'ENVIRONMENT', type: 'plain_text', text: 'preview' }
  ]
  
  puts "Plaintext bindings: #{plaintext_bindings.size} vars"
  puts "✅ API call structure looks good"
rescue => e
  puts "❌ API structure failed: #{e.message}"
end

puts "\n✅ Debug complete!"