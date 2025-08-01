# Test if the preview iframe is working correctly
app = App.find(1)

puts "=== Preview Iframe Debug ==="
puts "App ID: #{app.id}"
puts "App Name: #{app.name}"
puts "Preview URL: #{app.preview_url}"
puts "Files count: #{app.app_files.count}"

# Test the Worker content
if app.preview_url
  require 'httparty'
  
  puts "\nTesting preview URL content:"
  response = HTTParty.get(app.preview_url)
  puts "Status: #{response.code}"
  puts "Content-Type: #{response.headers['content-type']}"
  
  # Check if it's serving the TodoFlow app
  if response.body.include?("TodoFlow")
    puts "✅ TodoFlow app content found!"
  else
    puts "❌ TodoFlow content not found"
  end
  
  # Check if React is referenced
  if response.body.include?("react")
    puts "✅ React reference found!"
  else
    puts "❌ React reference not found"
  end
end

puts "\n📱 Preview iframe should now be showing the app at:"
puts app.preview_url
puts "\nIf the preview isn't working in the browser, check:"
puts "1. Browser console for errors"
puts "2. Network tab to see if iframe is loading"
puts "3. CORS or CSP policies blocking the iframe"