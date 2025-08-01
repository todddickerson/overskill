#!/usr/bin/env ruby
# Test if the deployed worker is accessible
# Run in Rails console

puts "=== Testing Live Worker ==="
puts

puts <<-'RUBY'
require 'httparty'

# Test the worker URLs
app = App.find_by(id: 1) || App.first
urls = [
  "https://preview-#{app.id}.overskill.app",
  "https://preview-#{app.id}.todd-e03.workers.dev"
]

urls.each do |url|
  puts "\nTesting: #{url}"
  begin
    response = HTTParty.get(url, timeout: 5)
    puts "Status: #{response.code}"
    puts "Response preview:"
    puts response.body[0..200]
  rescue => e
    puts "Error: #{e.message}"
  end
end

# Also check what files the worker should be serving
puts "\n\nApp files that should be available:"
app.app_files.each do |file|
  puts "  - #{file.path} (#{file.size_bytes} bytes)"
end

# Check the preview URL saved in the database
puts "\nApp preview URL in database: #{app.preview_url}"
RUBY