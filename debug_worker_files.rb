# Debug why Worker shows "nothing here yet"
# Run each section in Rails console

puts "=== Debug Worker Files ==="

# Check if app has files
app = App.find(1)
puts "App: #{app.name} (ID: #{app.id})"
puts "Files count: #{app.app_files.count}"

if app.app_files.any?
  puts "\nFiles in database:"
  app.app_files.each do |file|
    puts "  - #{file.path} (#{file.content.length} chars)"
    puts "    First 50 chars: #{file.content[0..50]}..."
  end
else
  puts "\n❌ No files found! Let's create some test files..."
  
  # Create test files
  app.app_files.create!(
    team: app.team,
    path: "index.html",
    content: <<-HTML,
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>#{app.name}</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <div class="container">
    <h1>Welcome to #{app.name}!</h1>
    <p>This app is running on Cloudflare Workers.</p>
    <button id="counter">Clicks: 0</button>
  </div>
  <script src="app.js"></script>
</body>
</html>
    HTML
    file_type: "html",
    size_bytes: 400
  )
  
  app.app_files.create!(
    team: app.team,
    path: "style.css",
    content: <<-CSS,
body {
  font-family: -apple-system, system-ui, sans-serif;
  margin: 0;
  padding: 0;
  background: #1a1a1a;
  color: #fff;
}
.container {
  max-width: 800px;
  margin: 50px auto;
  padding: 20px;
  text-align: center;
}
h1 {
  color: #60a5fa;
  margin-bottom: 20px;
}
button {
  background: #3b82f6;
  color: white;
  border: none;
  padding: 12px 24px;
  font-size: 16px;
  border-radius: 8px;
  cursor: pointer;
  transition: background 0.2s;
}
button:hover {
  background: #2563eb;
}
    CSS
    file_type: "css",
    size_bytes: 450
  )
  
  app.app_files.create!(
    team: app.team,
    path: "app.js",
    content: <<-JS,
let clicks = 0;
const button = document.getElementById('counter');

button.addEventListener('click', () => {
  clicks++;
  button.textContent = `Clicks: ${clicks}`;
  
  // Add a little animation
  button.style.transform = 'scale(0.95)';
  setTimeout(() => {
    button.style.transform = 'scale(1)';
  }, 100);
});

console.log('OverSkill app loaded successfully!');
    JS
    file_type: "javascript",
    size_bytes: 300
  )
  
  puts "✅ Created #{app.app_files.count} test files"
end

# Now update the preview
puts "\n📤 Updating preview worker..."
service = Deployment::CloudflarePreviewService.new(app)
result = service.update_preview!

if result[:success]
  puts "✅ Preview updated successfully!"
  puts "URL: #{result[:preview_url]}"
  puts "\n🌐 Try visiting: #{result[:preview_url]}"
else
  puts "❌ Update failed: #{result[:error]}"
end