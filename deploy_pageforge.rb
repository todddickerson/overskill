#!/usr/bin/env ruby
require_relative 'config/environment'

# Find and deploy the Pageforge app
app = App.find(1027)
puts "=" * 80
puts "Deploying: #{app.name} (ID: #{app.id})"
puts "App files count: #{app.app_files.count}"
puts "=" * 80

# Count images
image_files = app.app_files.select { |f| f.path.match?(/\.(jpg|jpeg|png|gif|webp)$/i) }
puts "\nImage files found: #{image_files.count}"
image_files.each do |img|
  size_kb = (img.content.bytesize / 1024.0).round(2)
  puts "  - #{img.path}: #{size_kb} KB"
end

# Trigger deployment
puts "\n" + "=" * 80
puts "Starting deployment with R2 asset offloading..."
puts "=" * 80

service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

puts "\n" + "=" * 80
puts "Deployment Result:"
puts "=" * 80
puts "Success: #{result[:success]}"

if result[:success]
  puts "Preview URL: #{result[:preview_url]}"
  puts "Workers Dev URL: #{result[:workers_dev_url]}" if result[:workers_dev_url]
  puts "Custom Domain URL: #{result[:custom_domain_url]}" if result[:custom_domain_url]
  puts "Note: #{result[:note]}" if result[:note]
  
  puts "\n✅ Deployment successful! Visit: #{result[:preview_url]}"
else
  puts "❌ Error: #{result[:error]}"
  
  # Check logs for more details
  if result[:error].include?("10027") || result[:error].include?("10 MiB")
    puts "\n⚠️  Worker still exceeds size limit. Check if R2 upload succeeded."
  end
end

puts "\n" + "=" * 80