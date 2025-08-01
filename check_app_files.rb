# Check what files app ID 1 has
app = App.find(1)
puts "App: #{app.name}"
puts "Files count: #{app.app_files.count}"
puts "\nFiles:"
app.app_files.each do |file|
  puts "  Path: #{file.path}"
  puts "  Type: #{file.file_type}"
  puts "  Size: #{file.size_bytes} bytes"
  puts "  First 100 chars: #{file.content[0..100]}..."
  puts "  ---"
end

# Let's also check if the referenced files exist
missing_files = ["styles.css", "components.js", "app.js"]
missing_files.each do |path|
  if app.app_files.exists?(path: path)
    puts "✅ #{path} exists"
  else
    puts "❌ #{path} is missing"
  end
end