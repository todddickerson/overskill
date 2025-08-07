#!/usr/bin/env ruby
# Check what was created in the final test
# Run with: bin/rails runner check_final_results.rb

app = App.find(81)
puts "Final test results for: #{app.name}"
puts "Status: #{app.status}"
puts "Files created: #{app.app_files.count}"

if app.app_files.any?
  puts "\nFiles created:"
  app.app_files.order(:created_at).each do |f|
    puts "  📄 #{f.path}"
    puts "    Size: #{f.content.length} chars"
    puts "    Type: #{f.file_type}"
    puts "    Preview: #{f.content[0..100]}..."
    puts
  end
else
  puts "No files created"
end

puts "\nRecent messages:"
app.app_chat_messages.order(created_at: :desc).limit(5).each do |msg|
  puts "#{msg.id}: #{msg.role} [#{msg.status || 'no status'}] - #{msg.content[0..60]}..."
end