#!/usr/bin/env ruby
# Update app 61 with enhanced OAuth
# Run with: bin/rails runner scripts/update_app_61_oauth.rb

app = App.find(61)
callback_file = app.app_files.find_by(path: "src/pages/auth/AuthCallback.tsx")

if callback_file
  callback_file.update!(content: Ai::AuthTemplates.auth_callback_page)
  preview_service = Deployment::CloudflarePreviewService.new(app)
  result = preview_service.update_preview!

  if result[:success]
    puts "✅ App 61 updated successfully: #{result[:preview_url]}"
  else
    puts "❌ Failed: #{result[:error]}"
  end
else
  puts "❌ AuthCallback not found in app 61"
end
