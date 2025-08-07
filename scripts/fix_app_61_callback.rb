#!/usr/bin/env ruby
# Fix App 61 OAuth callback
# Run with: bin/rails runner scripts/fix_app_61_callback.rb

app = App.find(61)
puts "Fixing OAuth callback for App ##{app.id}: #{app.name}"

# Update AuthCallback component
auth_callback_file = app.app_files.find_by(path: 'src/pages/auth/AuthCallback.tsx')
if auth_callback_file
  auth_callback_file.update!(content: Ai::AuthTemplates.auth_callback_page)
  puts "✅ Updated AuthCallback.tsx with proper OAuth handling"
  
  # Redeploy
  puts "Redeploying..."
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    puts "✅ Redeployed with OAuth callback fix"
    puts "URL: #{result[:preview_url]}"
    puts ""
    puts "OAuth flow should now work:"
    puts "1. Go to https://preview-61.overskill.app/login"
    puts "2. Click 'Continue with GitHub'"
    puts "3. Authorize the app"
    puts "4. Should redirect back to preview-61.overskill.app/auth/callback"
    puts "5. Should end up at /dashboard"
  else
    puts "❌ Deploy failed: #{result[:error]}"
  end
else
  puts "❌ AuthCallback.tsx not found"
end