#!/usr/bin/env ruby
# Test enhanced OAuth on existing app 60
# Run with: bin/rails runner scripts/test_app_60_oauth.rb

puts "🧪 Testing enhanced OAuth templates on existing app..."
puts "=" * 60

app = App.find(60)
puts "Testing app: ##{app.id} - #{app.name}"

# Update AuthCallback with the enhanced version
callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')

if callback_file
  callback_file.update!(content: Ai::AuthTemplates.auth_callback_page)
  puts "✅ Updated AuthCallback with enhanced PKCE handling"
  
  # Deploy the updated app
  preview_service = Deployment::CloudflarePreviewService.new(app)
  result = preview_service.update_preview!
  
  if result[:success]
    puts "✅ App deployed with enhanced OAuth!"
    puts "URL: #{result[:preview_url]}"
    puts ""
    puts "📋 Test OAuth on app 60:"
    puts "1. Visit: #{result[:preview_url]}/login"
    puts "2. Try social login (Google/GitHub)"
    puts "3. Should work with enhanced PKCE handling and error messages"
    puts "4. Check console for detailed OAuth flow logging"
    
    puts "\n🔍 Enhanced features:"
    puts "  ✅ Better PKCE session management"
    puts "  ✅ Detailed error messages with troubleshooting steps"
    puts "  ✅ Clear browser data functionality"
    puts "  ✅ Multiple retry strategies"
    
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
else
  puts "❌ AuthCallback file not found in app #{app.id}"
end

puts "\n" + "=" * 60
puts "OAuth enhancement test complete"
puts "=" * 60