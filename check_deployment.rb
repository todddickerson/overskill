require_relative 'config/environment'

app = App.find(1025)
puts "App: #{app.name} (#{app.subdomain})"

# Check the expected URL based on subdomain
expected_url = "https://preview-#{app.id}.overskill.app"
puts "Expected Preview URL: #{expected_url}"

# Try to fetch the app to verify it's working
require 'net/http'
require 'uri'

begin
  uri = URI.parse(expected_url)
  response = Net::HTTP.get_response(uri)
  puts "\n✅ App is accessible!"
  puts "HTTP Status: #{response.code}"
  puts "Content preview: #{response.body[0..500]}" if response.code == "200"
rescue => e
  puts "\n❌ Error accessing app: #{e.message}"
end

# Update the app with the correct URL
app.update!(preview_url: expected_url)
puts "\nUpdated preview URL in database: #{expected_url}"
