#!/usr/bin/env rails runner

# Debug the worker syntax error
app = App.find(105)  # Use the test app we just created
app_file = app.app_files.first

require_relative 'app/services/deployment/external_vite_builder'
builder = Deployment::ExternalViteBuilder.new(app)

# Generate worker code
worker_code = builder.send(:wrap_for_worker_deployment_hybrid, app_file.content, [])

# Write to file for inspection
File.write('debug_worker.js', worker_code)
puts "Worker code written to debug_worker.js"

# Show line 62 area
lines = worker_code.lines
if lines.length >= 62
  puts "\nLines around line 62:"
  (58..66).each do |i|
    if lines[i-1]
      marker = i == 62 ? " <<<< ERROR HERE" : ""
      puts "#{i}: #{lines[i-1].chomp}#{marker}"
    end
  end
else
  puts "Worker code only has #{lines.length} lines"
end

# Check for common syntax issues
puts "\n\nChecking for syntax issues..."

# Check for unescaped backticks in the HTML content
if worker_code.match(/const HTML_CONTENT = `([^`]*)`/m)
  html_content = $1
  if html_content.include?('`')
    puts "⚠️  Found unescaped backtick in HTML content"
  end
  if html_content.include?('${')
    puts "⚠️  Found template literal expression in HTML content"
  end
end

# Look for the specific character at position 72 of line 62
if lines[61] && lines[61].length >= 72
  char_at_72 = lines[61][71]
  puts "\nCharacter at line 62, position 72: '#{char_at_72}' (ASCII: #{char_at_72.ord})"
  
  # Check surrounding context
  context = lines[61][65..75]
  puts "Context around position 72: '#{context}'"
end