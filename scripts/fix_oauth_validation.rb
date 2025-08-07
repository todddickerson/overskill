#!/usr/bin/env ruby
# Fix OAuth validation_failed error by checking redirect URLs
# Run with: bin/rails runner scripts/fix_oauth_validation.rb

puts "=" * 80
puts "🔧 FIXING OAUTH VALIDATION_FAILED ERROR"
puts "=" * 80

puts "\n📍 The error 'validation_failed' means the redirect URL is not configured in Supabase."
puts "We need to add the preview app URLs to Supabase's allowed redirect URLs."

puts "\n🔍 Current app URLs that need to be configured:"

# Get all preview apps
preview_apps = App.where("preview_url IS NOT NULL AND preview_url != ''").order(:id)

puts "\nActive preview apps:"
preview_apps.each do |app|
  callback_url = "#{app.preview_url}/auth/callback"
  puts "  #{app.id}: #{callback_url}"
end

puts "\n📋 REQUIRED ACTIONS:"
puts "1. Go to Supabase Dashboard: https://supabase.com/dashboard"
puts "2. Select your project"
puts "3. Go to Authentication > URL Configuration"
puts "4. Add these URLs to 'Redirect URLs':"

puts "\n🔗 Specific URLs to add:"
preview_apps.each do |app|
  puts "   #{app.preview_url}/auth/callback"
end

puts "\n🌟 RECOMMENDED: Add wildcard patterns instead:"
puts "   https://preview-*.overskill.app/auth/callback"
puts "   https://preview-*.overskill.app/**"
puts "   (This will work for all current and future preview apps)"

puts "\n⚠️ IMPORTANT NOTES:"
puts "- Without these URLs, OAuth will fail with 'validation_failed'"
puts "- The wildcard pattern is more scalable"
puts "- Changes take effect immediately after saving"

# Create a test script that users can run to verify OAuth works
puts "\n🧪 After adding URLs, test with this script:"

test_script = <<~RUBY
#!/usr/bin/env ruby
# Test OAuth validation
require 'net/http'
require 'json'

# Test if our URLs would be accepted
puts "Testing OAuth redirect validation..."

supabase_url = "#{ENV['SUPABASE_URL']}"
test_urls = [
#{preview_apps.map { |app| "  \"#{app.preview_url}/auth/callback\"" }.join(",\n")}
]

test_urls.each do |url|
  puts "  Testing: \#{url}"
  # In reality, Supabase validates this on the OAuth initiation, not via API
  # The real test is to try OAuth login and see if it works
end

puts ""
puts "Real test: Visit any app and try social login!"
preview_apps.each do |app|
  puts "  \#{app.name}: \#{app.preview_url}/login"
end
RUBY

File.write('/tmp/test_oauth_validation.rb', test_script)
puts "Test script saved to: /tmp/test_oauth_validation.rb"

# Update our SocialButtons component to show the exact error
puts "\n📝 Updating SocialButtons to show validation_failed specifically..."

App.where("preview_url IS NOT NULL").find_each do |app|
  social_file = app.app_files.find_by(path: 'src/components/auth/SocialButtons.tsx')
  next unless social_file
  
  content = social_file.content
  
  # Add specific handling for validation_failed
  if content.include?('error.message.includes(\'redirect\')')
    # Replace the generic redirect error with specific validation_failed handling
    enhanced_content = content.gsub(
      /if \(error\.message\.includes\('redirect'\)\) \{\s*setError\(`OAuth redirect not configured for \$\{provider\}\. Please contact support\.`\)\s*\}/m,
      <<~JS.strip
        if (error.code === 'validation_failed') {
              setError(`OAuth redirect URL not configured for ${provider}. The app owner needs to add this URL to Supabase: ${window.location.origin}/auth/callback`)
            } else if (error.message.includes('redirect')) {
              setError(`OAuth redirect not configured for ${provider}. Please contact support.`)
            }
      JS
    )
    
    if enhanced_content != content
      social_file.update!(content: enhanced_content)
      puts "  ✅ Updated #{app.name} (App ##{app.id})"
    end
  end
end

puts "\n🚀 Next steps:"
puts "1. Add the redirect URLs to Supabase (required)"
puts "2. Test OAuth login on any preview app"
puts "3. If still failing, check Supabase project settings"

puts "\n📖 Supabase Documentation:"
puts "https://supabase.com/docs/guides/auth/redirect-urls"

puts "\n" + "=" * 80
puts "OAuth validation fix guide complete"
puts "=" * 80