#!/usr/bin/env ruby
# Test authentication flow for deployed apps
# Run with: bin/rails runner scripts/test_auth_flow.rb

puts "=" * 80
puts "🔐 TESTING AUTHENTICATION FLOW"
puts "=" * 80

# Test with app 60 which has auth configured
app = App.find(60)
puts "\n📱 Testing App ##{app.id}: #{app.name}"
puts "  Preview URL: #{app.preview_url}"
puts "  Status: #{app.status}"
puts "  Auth Settings: #{app.app_auth_setting ? 'Configured' : 'Not configured'}"

if app.app_auth_setting
  settings = app.app_auth_setting
  puts "\n[Auth Configuration]"
  puts "  Visibility: #{settings.visibility}"
  puts "  Requires Auth: #{settings.requires_authentication?}"
  puts "  Allow Signups: #{settings.allow_signups}"
  puts "  Providers: #{settings.allowed_providers.join(', ')}"
end

# Check if Supabase credentials are being injected
puts "\n🔧 Checking Environment Variables..."
preview_service = Deployment::CloudflarePreviewService.new(app)
env_vars = preview_service.send(:build_env_vars_for_app, :preview)

puts "  SUPABASE_URL: #{env_vars['SUPABASE_URL'] ? '✅ Set' : '❌ Missing'}"
puts "  SUPABASE_ANON_KEY: #{env_vars['SUPABASE_ANON_KEY'] ? '✅ Set' : '❌ Missing'}"
puts "  APP_ID: #{env_vars['APP_ID']}"
puts "  AUTH_VISIBILITY: #{env_vars['AUTH_VISIBILITY']}"
puts "  AUTH_REQUIRES_AUTH: #{env_vars['AUTH_REQUIRES_AUTH']}"

# Check auth-related files
puts "\n📁 Auth Files Check:"
auth_files = [
  'src/lib/supabase.ts',
  'src/pages/auth/Login.tsx',
  'src/pages/auth/SignUp.tsx',
  'src/components/auth/ProtectedRoute.tsx',
  'src/hooks/useAuth.ts'
]

auth_files.each do |path|
  file = app.app_files.find_by(path: path)
  if file
    puts "  ✅ #{path} (#{file.content.length} bytes)"
  else
    puts "  ❌ #{path} (missing)"
  end
end

# Generate test URLs
if app.preview_url
  puts "\n🌐 Test URLs:"
  puts "  Home: #{app.preview_url}"
  puts "  Login: #{app.preview_url}/login"
  puts "  Signup: #{app.preview_url}/signup"
  puts "  Dashboard: #{app.preview_url}/dashboard"
  puts "  Auth Callback: #{app.preview_url}/auth/callback"
  
  puts "\n📋 Manual Test Steps:"
  puts "  1. Visit #{app.preview_url}"
  puts "  2. Should redirect to /login if auth required"
  puts "  3. Open browser console (F12)"
  puts "  4. Check window.ENV has SUPABASE_URL"
  puts "  5. Try signing up with a test email"
  puts "  6. Try social login (GitHub/Google)"
  puts "  7. Verify redirect to dashboard after login"
else
  puts "\n⚠️ App not deployed yet"
end

puts "\n" + "=" * 80
puts "✅ AUTH FLOW TEST COMPLETE"
puts "=" * 80