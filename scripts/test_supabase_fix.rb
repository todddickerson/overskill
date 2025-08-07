#!/usr/bin/env ruby
# Test that Supabase configuration is properly injected into apps
# Run with: bin/rails runner scripts/test_supabase_fix.rb

puts "=" * 80
puts "🔧 TESTING SUPABASE CONFIGURATION FIX"
puts "=" * 80

# Find an app with auth files
app = App.find(60)  # Using app 60 which we already fixed
puts "\n📱 Testing with App ##{app.id}: #{app.name}"

# Update the supabase.ts file to use our new template
require_relative '../app/services/ai/supabase_client_template'
supabase_file = app.app_files.find_by(path: 'src/lib/supabase.ts')

if supabase_file
  puts "📝 Updating src/lib/supabase.ts with new template..."
  supabase_file.update!(content: Ai::SupabaseClientTemplate.generate)
  puts "✅ Updated with robust error handling"
else
  puts "❌ src/lib/supabase.ts not found - creating it..."
  app.app_files.create!(
    path: 'src/lib/supabase.ts',
    content: Ai::SupabaseClientTemplate.generate,
    team: app.team
  )
  puts "✅ Created src/lib/supabase.ts"
end

# Deploy the app
puts "\n🚀 Deploying to test environment variable injection..."
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  puts "\n🌐 Preview URL: #{result[:preview_url]}"
  
  puts "\n📋 Test Instructions:"
  puts "1. Visit: #{result[:preview_url]}"
  puts "2. Open browser console (F12)"
  puts "3. Check for any Supabase errors"
  puts "4. Type: window.ENV"
  puts "5. Verify SUPABASE_URL and SUPABASE_ANON_KEY are present"
  
  puts "\n🔍 Expected in console:"
  puts "  window.ENV.SUPABASE_URL = 'https://...supabase.co'"
  puts "  window.ENV.SUPABASE_ANON_KEY = 'eyJ...'"
  
  puts "\n⚠️ If you see a red error overlay:"
  puts "  - The environment variables are NOT being injected properly"
  puts "  - Check Cloudflare Worker configuration"
  
  puts "\n✅ If the app loads normally:"
  puts "  - Environment variables are working!"
  puts "  - Try logging in to test auth flow"
  
else
  puts "❌ Deployment failed: #{result[:error]}"
end

puts "\n" + "=" * 80
puts "TEST COMPLETE"
puts "=" * 80