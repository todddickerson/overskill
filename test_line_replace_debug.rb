#!/usr/bin/env ruby

# Load Rails environment
require_relative 'config/environment'

app = App.last
css_file = app.app_files.find_by(path: 'src/index.css')

puts "Testing LineReplaceService with correct parameters"
puts "File: #{css_file.path}"

# Test 1: Simple single-line replacement
puts "\n=== Test 1: Single line replacement ==="
begin
  # Try to replace the primary color value
  search_text = '    --primary: 214 100% 45%;'
  replacement_text = '    --primary: 214 100% 50%;'
  
  # Find the line number
  lines = css_file.content.lines
  line_num = lines.find_index { |line| line.strip == search_text.strip }
  
  if line_num
    puts "Found target line at line #{line_num + 1}: #{lines[line_num].strip}"
    
    result = Ai::LineReplaceService.replace_lines(
      css_file,
      search_text,
      line_num + 1,  # LineReplaceService uses 1-based indexing
      line_num + 1,
      replacement_text
    )
    
    if result[:success]
      puts "✅ Single line replacement succeeded"
    else
      puts "❌ Single line replacement failed: #{result[:message] || result[:error]}"
      puts "Debug info: #{result.inspect}"
    end
  else
    puts "❌ Could not find target line in file"
    puts "Available lines around primary color:"
    lines.each_with_index do |line, i|
      if line.include?('--primary')
        puts "  Line #{i+1}: #{line.chomp}"
      end
    end
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(3)
end

# Test 2: Multi-line replacement that might be failing
puts "\n=== Test 2: Multi-line CSS block replacement ==="
begin
  lines = css_file.content.lines
  start_line = nil
  
  lines.each_with_index do |line, i|
    if line.include?('.overskill-badge {')
      start_line = i + 1
      break
    end
  end
  
  if start_line
    puts "Found .overskill-badge block starting at line #{start_line}"
    puts "Content around that line:"
    (start_line-1..start_line+5).each do |i|
      next if i < 0 || i >= lines.length
      puts "  #{i+1}: #{lines[i].chomp}"
    end
    
    # Try replacing just the class declaration line
    result = Ai::LineReplaceService.replace_lines(
      css_file,
      lines[start_line-1],  # The actual line content
      start_line,
      start_line,
      lines[start_line-1]   # Same content (no-op replacement)
    )
    
    if result[:success]
      puts "✅ CSS block line replacement succeeded"
    else
      puts "❌ CSS block line replacement failed: #{result[:message] || result[:error]}"
      puts "Debug info: #{result.inspect}"
    end
  else
    puts "❌ Could not find .overskill-badge block"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(3)
end

# Test 3: Check for common line ending issues
puts "\n=== Test 3: Line ending analysis ==="
content = css_file.content
puts "File size: #{content.bytesize} bytes"
puts "Line count: #{content.lines.count}"
puts "Has CRLF: #{content.include?("\r\n")}"
puts "Has CR: #{content.include?("\r")}"
puts "Ends with newline: #{content.end_with?("\n")}"

# Sample a few lines to check for whitespace issues
puts "\nLine samples (showing whitespace):"
content.lines[19..22].each_with_index do |line, i|
  puts "  #{i+20}: #{line.inspect}"
end

# Test 4: Try to reproduce a common failure pattern
puts "\n=== Test 4: Exact whitespace matching test ==="
target_line = lines[19]  # Line 20: --primary: 214 100% 45%;
puts "Testing exact match for line 20:"
puts "  Actual content: #{target_line.inspect}"
puts "  Length: #{target_line.length} chars"

# Try matching with and without trailing whitespace
test_patterns = [
  target_line,  # Exact match
  target_line.rstrip,  # Without trailing whitespace
  target_line.rstrip + "\n"  # With just newline
]

test_patterns.each_with_index do |pattern, i|
  puts "\n  Pattern #{i+1}: #{pattern.inspect}"
  result = Ai::LineReplaceService.replace_lines(
    css_file,
    pattern,
    20,
    20,
    pattern  # No-op replacement
  )
  
  if result[:success]
    puts "    ✅ Pattern #{i+1} matched successfully"
  else
    puts "    ❌ Pattern #{i+1} failed: #{result[:message] || result[:error]}"
  end
end