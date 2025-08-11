#!/usr/bin/env ruby
# Debug preview URL error

require_relative 'config/environment'
require 'net/http'
require 'uri'

app_id = ARGV[0] || App.last.id
app = App.find(app_id)

puts "Debugging preview for app ##{app.id}: #{app.name}"
puts "Preview URL: #{app.preview_url}"
puts "-"*60

if app.preview_url.nil?
  puts "❌ No preview URL set"
  exit 1
end

uri = URI.parse(app.preview_url)

begin
  response = Net::HTTP.get_response(uri)
  
  puts "\nHTTP Status: #{response.code}"
  puts "\nResponse Headers:"
  response.each_header do |key, value|
    puts "  #{key}: #{value}"
  end
  
  puts "\nResponse Body (first 2000 chars):"
  puts "-"*40
  puts response.body[0..2000]
  puts "-"*40
  
  # Try to identify the error
  if response.body.include?('Error 1101')
    puts "\n⚠️ Cloudflare Error 1101: Worker threw a JavaScript exception"
    puts "This usually means there's an error in the worker code"
  elsif response.body.include?('Error 522')
    puts "\n⚠️ Cloudflare Error 522: Connection timed out"
  elsif response.body.include?('Error 530')
    puts "\n⚠️ Cloudflare Error 530: Origin DNS error"
  end
  
  # Check app files for potential issues
  puts "\n📁 App Files:"
  app.app_files.each do |file|
    puts "  #{file.path}: #{file.content.length} bytes"
    
    # Check for common issues
    if file.path == 'index.html'
      if !file.content.include?('<!DOCTYPE html')
        puts "    ⚠️ Missing DOCTYPE declaration"
      end
      if !file.content.include?('<div id="root">')
        puts "    ⚠️ Missing root div"
      end
    elsif file.path.end_with?('.jsx')
      if file.content.include?('export default')
        puts "    ⚠️ Uses ES module export (CDN React doesn't support this)"
      end
    end
  end
  
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end