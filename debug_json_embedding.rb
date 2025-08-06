#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 JSON Embedding Debug"
puts "="*40

# Get test app
app = App.last
puts "📱 Test App: #{app.name} (#{app.id})"

# Test the JSON generation
service = Deployment::CloudflarePreviewService.new(app)
json_content = service.send(:app_files_as_json)

puts "\n📄 JSON Content:"
puts "Length: #{json_content.length} characters"

# Check if JSON is valid
begin
  parsed = JSON.parse(json_content)
  puts "✅ JSON is valid"
  puts "Files count: #{parsed.keys.count}"
  
  # Show first few file keys
  puts "Files:"
  parsed.keys.first(5).each do |key|
    content_length = parsed[key]&.length || 0
    puts "  - #{key} (#{content_length} chars)"
  end
  
rescue JSON::ParserError => e
  puts "❌ JSON is invalid: #{e.message}"
  puts "First 1000 characters:"
  puts json_content[0..1000]
end

# Check for problematic characters
problematic_chars = json_content.scan(/[^\x20-\x7E\n\r\t]/)
if problematic_chars.any?
  puts "\n⚠️  Found #{problematic_chars.count} non-ASCII characters"
  puts "Examples: #{problematic_chars.uniq.first(5).join(', ')}"
end

# Test the worker script generation with this JSON
puts "\n🔧 Testing full worker script generation..."
worker_script = service.send(:generate_worker_script)
puts "Worker script length: #{worker_script.length}"

# Look for the JSON embedding point
json_location = worker_script.index('#{app_files_as_json}')
if json_location
  puts "❌ JSON placeholder not replaced at position #{json_location}"
else
  puts "✅ JSON placeholder was replaced"
end

puts "\n✅ Debug complete!"