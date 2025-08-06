#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Worker Script Debug"
puts "="*40

# Get test app
app = App.last
puts "📱 Test App: #{app.name} (#{app.id})"
puts "App files: #{app.app_files.count}"

# Generate worker script
service = Deployment::FastPreviewService.new(app)
worker_script = service.send(:generate_fast_preview_worker)

puts "\n📝 Worker Script Length: #{worker_script.length} characters"

# Check for common JavaScript syntax issues
syntax_issues = []

# Check for unbalanced braces
open_braces = worker_script.count('{')
close_braces = worker_script.count('}')
if open_braces != close_braces
  syntax_issues << "Unbalanced braces: #{open_braces} open, #{close_braces} close"
end

# Check for unbalanced parentheses
open_parens = worker_script.count('(')
close_parens = worker_script.count(')')
if open_parens != close_parens
  syntax_issues << "Unbalanced parentheses: #{open_parens} open, #{close_parens} close"
end

# Check for proper JSON embedding
if worker_script.include?('#{app_files_as_json}')
  syntax_issues << "JSON placeholder not replaced"
end

if syntax_issues.any?
  puts "\n❌ Potential Syntax Issues:"
  syntax_issues.each { |issue| puts "  - #{issue}" }
else
  puts "\n✅ No obvious syntax issues detected"
end

# Show first 500 and last 500 characters
puts "\n📄 Script Preview:"
puts "First 500 characters:"
puts worker_script[0..500]
puts "\n..."
puts "Last 500 characters:"
puts worker_script[-500..-1]

# Try to validate with Node.js if available
puts "\n🔍 Attempting JavaScript validation..."
require 'tempfile'

Tempfile.create(['worker', '.js']) do |temp_file|
  temp_file.write(worker_script)
  temp_file.close
  
  # Try node --check for syntax validation
  result = `node --check #{temp_file.path} 2>&1`
  if $?.success?
    puts "✅ JavaScript syntax is valid"
  else
    puts "❌ JavaScript syntax error:"
    puts result
  end
end

puts "\n✅ Debug complete!"