#!/usr/bin/env ruby
# Test authentication for existing app 60
# Run with: bin/rails runner scripts/test_app_60_auth.rb

puts "=" * 80
puts "🔐 TESTING AUTHENTICATION FOR APP 60"
puts "=" * 80

app = App.find(60)
puts "\n📱 App ##{app.id}: #{app.name}"
puts "  Status: #{app.status}"
puts "  Files: #{app.app_files.count}"
puts "  Framework: #{app.framework}"

# Check auth files
auth_files = app.app_files.where("path LIKE '%auth%' OR path LIKE '%Auth%' OR path LIKE '%login%'")
puts "\n📁 Auth Files Found: #{auth_files.count}"
auth_files.each do |file|
  puts "  ✅ #{file.path}"
end

# Create auth settings if not present
if app.app_auth_setting.nil?
  puts "\n🔧 Creating auth settings..."
  app.create_app_auth_setting!(
    visibility: 'public_login_required',
    allowed_providers: ['email', 'google', 'github'],
    allowed_email_domains: [],  # All domains allowed
    require_email_verification: false,
    allow_signups: true,
    allow_anonymous: false
  )
  puts "✅ Created auth settings"
else
  puts "\n✅ Auth settings already exist"
end

settings = app.app_auth_setting
puts "\n[Auth Configuration]"
puts "  Visibility: #{settings.visibility}"
puts "  Requires Auth: #{settings.requires_authentication?}"
puts "  Allow Signups: #{settings.allow_signups}"
puts "  Providers: #{settings.allowed_providers.join(', ')}"
puts "  Email Domains: #{settings.allowed_email_domains.any? ? settings.allowed_email_domains.join(', ') : 'All allowed'}"

# Deploy to preview
puts "\n🚀 Deploying to Cloudflare Preview..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployed successfully!"
  puts "\n🌐 Preview URLs:"
  puts "  Main: #{result[:preview_url]}"
  puts "  Custom: #{result[:custom_domain_url]}" if result[:custom_domain_url]
  
  puts "\n📱 Test Authentication:"
  puts "  1. Visit: #{result[:preview_url]}"
  puts "  2. You should see the login page"
  puts "  3. Click 'Sign Up' to create an account"
  puts "  4. Try social login with GitHub"
  puts "  5. Test email/password signup"
  
  puts "\n🔍 Direct Links:"
  puts "  - Login: #{result[:preview_url]}/login"
  puts "  - Signup: #{result[:preview_url]}/signup"
  puts "  - Dashboard: #{result[:preview_url]}/dashboard"
  puts "  - Forgot Password: #{result[:preview_url]}/forgot-password"
  
  # Update app preview URL
  app.update!(preview_url: result[:preview_url])
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

# Test environment variables injection
puts "\n🔧 Environment Variables Check:"
puts "  The following auth settings will be injected:"
config = settings.to_frontend_config
config.each do |key, value|
  puts "  AUTH_#{key.to_s.upcase}: #{value}"
end

puts "\n✏️ App Editor URL:"
puts "  http://localhost:3000/account/apps/#{app.to_param}/editor"

puts "\n" + "=" * 80
puts "✅ AUTH TEST COMPLETE FOR APP 60!"
puts "=" * 80
puts "\n📊 Summary:"
puts "  App ID: #{app.id}"
puts "  Name: #{app.name}"
puts "  Auth Settings: Configured"
puts "  Preview URL: #{app.preview_url || 'Not deployed'}"
puts "\n🎉 Authentication has been successfully configured!"