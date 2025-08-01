# Set up preview URLs for all apps that don't have them
puts "=== Setting Up Preview URLs for All Apps ==="

apps_without_preview = App.where(preview_url: [nil, ''])
puts "Found #{apps_without_preview.count} apps without preview URLs"

apps_without_preview.each do |app|
  puts "\n📱 App: #{app.name} (ID: #{app.id})"
  
  if app.app_files.count == 0
    puts "  ⚠️  No files - skipping"
    next
  end
  
  puts "  Files: #{app.app_files.count}"
  
  # Deploy to Cloudflare
  service = Deployment::CloudflarePreviewService.new(app)
  result = service.update_preview!
  
  if result[:success]
    app.reload
    puts "  ✅ Preview URL: #{app.preview_url}"
  else
    puts "  ❌ Failed: #{result[:error]}"
  end
  
  # Small delay to avoid rate limiting
  sleep 0.5
end

puts "\n=== Summary ==="
puts "Apps with preview URLs: #{App.where.not(preview_url: [nil, '']).count}"
puts "Apps without preview URLs: #{App.where(preview_url: [nil, '']).count}"

# Show the app you're currently viewing
puts "\n💡 To test the TodoFlow app with working preview:"
app_with_preview = App.find(1)
puts "   Navigate to: /account/apps/#{app_with_preview.id}/editor"
puts "   Preview URL: #{app_with_preview.preview_url}"