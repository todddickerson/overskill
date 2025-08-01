# Check which app is having the require issue
puts "=== Checking Apps with 'require' in their code ==="

App.joins(:app_files).where("app_files.content LIKE ?", "%require%").distinct.each do |app|
  puts "\nApp: #{app.name} (ID: #{app.id})"
  puts "Preview URL: #{app.preview_url}"
  
  app.app_files.where("content LIKE ?", "%require%").each do |file|
    puts "\n  File: #{file.path}"
    # Find lines with require
    file.content.lines.each_with_index do |line, i|
      if line.include?("require")
        puts "    Line #{i+1}: #{line.strip}"
      end
    end
  end
end

# Let's also check for import statements
puts "\n\n=== Checking Apps with ES6 'import' statements ==="
App.joins(:app_files).where("app_files.content LIKE ?", "%import%").distinct.each do |app|
  puts "\nApp: #{app.name} (ID: #{app.id})"
  puts "Preview URL: #{app.preview_url}"
  
  app.app_files.where("content LIKE ?", "%import%").each do |file|
    puts "\n  File: #{file.path}"
    # Show first few import lines
    file.content.lines.first(5).each_with_index do |line, i|
      if line.include?("import")
        puts "    Line #{i+1}: #{line.strip}"
      end
    end
  end
end