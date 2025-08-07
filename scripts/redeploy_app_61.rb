#!/usr/bin/env ruby
# Redeploy App 61 with React Router fix
# Run with: bin/rails runner scripts/redeploy_app_61.rb

app = App.find(61)
puts "Redeploying App ##{app.id}: #{app.name}"

deploy_service = Deployment::CloudflarePreviewService.new(app)
result = deploy_service.update_preview!

if result[:success]
  puts "✅ Deployed with routing fix"
  puts "URL: #{result[:preview_url]}"
  puts ""
  puts "Test these URLs directly:"
  puts "- Login: https://preview-61.overskill.app/login"
  puts "- SignUp: https://preview-61.overskill.app/signup"
  puts "- Dashboard: https://preview-61.overskill.app/dashboard"
  puts "- Forgot Password: https://preview-61.overskill.app/forgot-password"
else
  puts "❌ Deploy failed: #{result[:error]}"
end