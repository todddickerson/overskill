# Find the app being shown in the editor
puts "=== Finding App ==="

# First check if wJGvjb is a valid app ID
puts "\nChecking all apps:"
App.all.each do |app|
  puts "ID: #{app.id} | Name: #{app.name} | Preview URL: #{app.preview_url || 'none'}"
end

# The app in the editor might be the first one we created
app = App.first
if app
  puts "\n=== Checking First App ==="
  puts "App ID: #{app.id}"
  puts "App Name: #{app.name}"
  puts "Preview URL: #{app.preview_url}"
  puts "Files count: #{app.app_files.count}"
  
  if app.preview_url.blank?
    puts "\n🔧 Setting up preview for this app..."
    service = Deployment::CloudflarePreviewService.new(app)
    result = service.update_preview!
    
    if result[:success]
      app.reload
      puts "✅ Preview URL set to: #{app.preview_url}"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end
end

# Check the route being used
puts "\n=== Route Analysis ==="
puts "The editor is using: /account/apps/wJGvjb/preview"
puts "This suggests 'wJGvjb' is the app's ID or slug"

# Try to decode or understand the ID format
if app && app.id.to_s != 'wJGvjb'
  puts "\n⚠️  The app ID in the URL (wJGvjb) doesn't match our test app (#{app.id})"
  puts "You may need to navigate to the correct app in the browser"
  puts "Try: /account/apps/#{app.id}/editor"
end