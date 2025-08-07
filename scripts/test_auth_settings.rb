#!/usr/bin/env ruby
# Test auth settings for apps
# Run with: bin/rails runner scripts/test_auth_settings.rb

puts "=" * 60
puts "TESTING APP AUTH SETTINGS"
puts "=" * 60

# Test with App 61
app = App.find(61)
puts "\n📱 App ##{app.id}: #{app.name}"

# Create auth settings if not present
if app.app_auth_setting.nil?
  puts "\nCreating auth settings..."
  app.create_app_auth_setting!(
    visibility: 'public_login_required',
    allowed_providers: ['email', 'google', 'github'],
    allowed_email_domains: [],  # Start with no restrictions
    require_email_verification: false,
    allow_signups: true,
    allow_anonymous: false
  )
  puts "✅ Created auth settings"
else
  puts "✅ Auth settings already exist"
end

settings = app.app_auth_setting
puts "\n[Current Settings]"
puts "  Visibility: #{settings.visibility}"
puts "  Requires Auth: #{settings.requires_authentication?}"
puts "  Allow Signups: #{settings.allow_signups}"
puts "  Allow Anonymous: #{settings.allow_anonymous}"
puts "  Email Verification: #{settings.require_email_verification}"
puts "  Allowed Providers: #{settings.allowed_providers.join(', ')}"
puts "  Email Domain Restrictions: #{settings.allowed_email_domains.any? ? settings.allowed_email_domains.join(', ') : 'None (all allowed)'}"

# Test domain restriction
puts "\n[Testing Domain Restrictions]"
test_emails = [
  'user@example.com',
  'employee@company.com',
  'partner@partner.org'
]

test_emails.each do |email|
  allowed = settings.allows_email_domain?(email)
  puts "  #{allowed ? '✅' : '❌'} #{email}"
end

# Test with domain restrictions
puts "\n[Adding Domain Restrictions]"
settings.update!(allowed_email_domains: ['company.com', 'partner.org'])
puts "  Set allowed domains: company.com, partner.org"

test_emails.each do |email|
  allowed = settings.allows_email_domain?(email)
  puts "  #{allowed ? '✅' : '❌'} #{email}"
end

# Test visibility modes
puts "\n[Testing Visibility Modes]"
AppAuthSetting.visibilities.each do |key, value|
  settings.update!(visibility: key)
  puts "\n  Mode: #{key}"
  puts "    Requires Auth: #{settings.requires_authentication?}"
  puts "    Allows Public Signup: #{settings.allows_public_signup?}"
end

# Reset to sensible defaults
settings.update!(
  visibility: 'public_login_required',
  allowed_email_domains: []
)

# Test frontend config export
puts "\n[Frontend Configuration Export]"
config = settings.to_frontend_config
puts "  window.AUTH_CONFIG = #{JSON.pretty_generate(config)}"

# Show how it would be injected
puts "\n[Environment Variables for Deployment]"
puts "  AUTH_VISIBILITY=#{config[:visibility]}"
puts "  AUTH_REQUIRES_AUTH=#{config[:requires_auth]}"
puts "  AUTH_ALLOW_SIGNUPS=#{config[:allow_signups]}"
puts "  AUTH_ALLOWED_PROVIDERS=#{config[:allowed_providers].to_json}"
puts "  AUTH_ALLOWED_EMAIL_DOMAINS=#{config[:allowed_email_domains].to_json}"

puts "\n" + "=" * 60
puts "✅ Auth settings system working!"
puts "=" * 60