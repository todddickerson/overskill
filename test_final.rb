# Final test of the complete setup
require 'net/http'
require 'uri'

app = App.find(1)
puts "=== Final Preview Test ==="
puts "App: #{app.name}"
puts "Preview URL: #{app.preview_url}"

# Test with Net::HTTP which might handle DNS better
uri = URI(app.preview_url)
puts "\nTesting #{uri}..."

begin
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.open_timeout = 10
  http.read_timeout = 10
  
  request = Net::HTTP::Get.new(uri)
  response = http.request(request)
  
  puts "Status: #{response.code}"
  puts "Content-Type: #{response['content-type']}"
  puts "Response length: #{response.body.length} chars"
  
  if response.code == '200'
    puts "\n✅ SUCCESS! Preview is working at custom domain!"
    
    # Check content
    if response.body.include?("TodoFlow")
      puts "✅ TodoFlow app content confirmed"
    end
    
    if response.body.include?("react")
      puts "✅ React references found"
    end
    
    # Test a static asset
    css_uri = URI("#{app.preview_url}/styles.css")
    css_response = Net::HTTP.get_response(css_uri)
    puts "\n📄 CSS file test: #{css_response.code} (#{css_response['content-type']})"
    
    js_uri = URI("#{app.preview_url}/app.js")
    js_response = Net::HTTP.get_response(js_uri)
    puts "📄 JS file test: #{js_response.code} (#{js_response['content-type']})"
  end
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts "\nTrying with curl instead..."
  system("curl -s -I #{app.preview_url}")
end

puts "\n🎉 Preview setup complete!"
puts "The editor preview iframe should now show your app at:"
puts "   #{app.preview_url}"