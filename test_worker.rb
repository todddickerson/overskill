require 'httparty'

app = App.find(1)
puts "Testing Worker URLs for app ID: #{app.id}"

# First let's check the workers.dev URL which is working
workers_dev_url = "https://preview-1.todd-e03.workers.dev"
puts "\nTesting workers.dev URL: #{workers_dev_url}"
response = HTTParty.get(workers_dev_url)
puts "Status: #{response.code}"
puts "Content type: #{response.headers['content-type']}"
puts "Body length: #{response.body.length} chars"
puts "\nFirst 300 chars:"
puts response.body[0..300]

# Let's test the JavaScript file
puts "\n\nTesting app.js file:"
js_response = HTTParty.get("#{workers_dev_url}/app.js")
puts "Status: #{js_response.code}"
puts "Content type: #{js_response.headers['content-type']}"
puts "First 200 chars of app.js:"
puts js_response.body[0..200]

# Now let's update the preview iframe to use this working URL
puts "\n\nUpdating app preview URL to working workers.dev URL..."
app.update!(preview_url: workers_dev_url)
puts "Preview URL updated to: #{app.preview_url}"