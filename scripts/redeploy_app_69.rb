#!/usr/bin/env ruby
app = App.find(69)
preview_service = Deployment::CloudflarePreviewService.new(app)
result = preview_service.update_preview!
if result[:success]
  puts '✅ Deployment successful!'
  puts 'Preview URL: ' + result[:preview_url]
else
  puts '❌ Deployment failed: ' + result[:error]
end