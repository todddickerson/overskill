# Find apps that have app_files
puts "=== Finding Apps with Files ==="

apps_with_files = App.joins(:app_files).distinct.order(:id)
puts "Found #{apps_with_files.count} apps with files:"

apps_with_files.each do |app|
  puts "\nApp ID: #{app.id}"
  puts "Name: #{app.name}"
  puts "Files: #{app.app_files.count}"
  puts "Preview URL: #{app.preview_url || 'none'}"
  
  # List files
  app.app_files.limit(5).each do |file|
    puts "  - #{file.path} (#{file.size_bytes} bytes)"
  end
  
  # If no preview URL, offer to create one
  if app.preview_url.blank? && app.app_files.any?
    puts "  🔧 Setting up preview..."
    service = Deployment::CloudflarePreviewService.new(app)
    result = service.update_preview!
    if result[:success]
      puts "  ✅ Preview URL: #{app.reload.preview_url}"
    else
      puts "  ❌ Failed: #{result[:error]}"
    end
  end
end

# Special check for the app shown in the screenshot
# It has files: index.html, app.js, components.js, styles.css
puts "\n=== Looking for app with specific files ==="
app_with_specific_files = App.joins(:app_files)
  .where(app_files: { path: ['index.html', 'app.js', 'components.js', 'styles.css'] })
  .group('apps.id')
  .having('COUNT(DISTINCT app_files.path) = 4')
  .first

if app_with_specific_files
  puts "Found app matching screenshot: #{app_with_specific_files.name} (ID: #{app_with_specific_files.id})"
  puts "Navigate to: /account/apps/#{app_with_specific_files.id}/editor"
else
  puts "No app found with all 4 files from screenshot"
end