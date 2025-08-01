# Test the Code tab rendering
app = App.find(13) # Scientific Calculator which has files

puts "=== Testing Code Tab for #{app.name} ==="
puts "Files count: #{app.app_files.count}"

# Check what the controller would set
files = app.app_files.order(:path)
selected_file = files.first

puts "\nFiles:"
files.each do |file|
  puts "  - #{file.path} (#{file.size_bytes} bytes)"
end

puts "\nSelected file: #{selected_file&.path}"
puts "Selected file content preview:"
puts selected_file&.content&.first(200) + "..."

# Check if the code editor would render
if selected_file
  puts "\n✅ Code editor should render with file: #{selected_file.path}"
else
  puts "\n❌ No file selected - code editor would show empty state"
end

# URL to test
puts "\n📱 To test the Code tab:"
puts "1. Navigate to: /account/apps/#{app.id}/editor"
puts "2. Click the 'Code' tab"
puts "3. The file tree should show on the left"
puts "4. The code editor should show on the right with syntax highlighting"
puts "\nOr go directly to: /account/apps/#{app.id}/editor?tab=code"