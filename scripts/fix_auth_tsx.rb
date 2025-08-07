#!/usr/bin/env ruby
# Fix Auth component to be TypeScript
# Run with: bin/rails runner scripts/fix_auth_tsx.rb

app = App.find(57)
auth_file = app.app_files.find_by(path: "src/components/Auth.jsx")
if auth_file
  auth_file.update!(
    path: "src/components/Auth.tsx", 
    file_type: "tsx"
  )
  puts "✅ Changed Auth.jsx to Auth.tsx"
else
  puts "❌ Auth.jsx not found"
end

# Deploy again
puts "Deploying..."
deploy_service = Deployment::CloudflarePreviewService.new(app)
result = deploy_service.update_preview!

if result[:success]
  puts "✅ Deployment successful!"
  puts "  Preview URL: #{result[:preview_url]}"
else
  puts "❌ Deployment failed: #{result[:error]}"
end