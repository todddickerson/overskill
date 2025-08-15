# Test the line replacement fix
require_relative 'config/environment'

# Find an app with files
app = App.find(844)
file = app.app_files.find_by(path: 'src/components/ui/button.tsx')

if file
  puts "Testing line replacement on #{file.path}"
  puts "Original content lines: #{file.content.lines.size}"
  
  # Test case: Replace lines 10-12
  test_lines = file.content.lines
  if test_lines.size >= 12
    target_content = test_lines[9..11].join  # Lines 10-12 (0-indexed)
    puts "Target content (lines 10-12):"
    puts target_content
    
    # Try the replacement
    result = Ai::LineReplaceService.replace_lines(
      file,
      target_content.strip,
      10,
      12,
      "  // Test replacement\n  const test = true;\n"
    )
    
    puts "\nResult: #{result[:success] ? 'SUCCESS' : 'FAILED'}"
    puts "Message: #{result[:message] || result[:error]}"
    
    if result[:success]
      puts "Stats: #{result[:stats]}"
    end
  else
    puts "File has fewer than 12 lines"
  end
else
  puts "File not found"
end
