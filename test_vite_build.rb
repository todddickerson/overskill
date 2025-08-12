#!/usr/bin/env ruby
require_relative 'config/environment'

# Enable detailed logging
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = Logger::DEBUG

app_id = ARGV[0] || 238
app = App.find(app_id)

puts "Testing build for app ##{app.id}: #{app.name}"
puts "Files in app: #{app.app_files.count}"

begin
  builder = Deployment::ExternalViteBuilder.new(app)
  
  puts "\nStarting preview build..."
  result = builder.build_for_preview
  
  if result[:success]
    puts "\n✅ Build successful!"
    puts "Build time: #{result[:build_time]}s"
    puts "Output size: #{result[:built_code]&.size || 0} bytes"
  else
    puts "\n❌ Build failed!"
    puts "Error: #{result[:error]}"
  end
  
rescue => e
  puts "\n❌ Build error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end