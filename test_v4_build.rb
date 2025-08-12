#!/usr/bin/env ruby

# Test V4 build process
require_relative './config/environment'

begin
  puts 'Testing V4 build process...'
  
  # Find the test app we created
  app = App.find_by(name: 'V4 Test App')
  if app.nil?
    puts 'ERROR: Test app not found. Run test_v4_basic.rb first.'
    exit 1
  end
  
  puts "Using app: #{app.id} (#{app.name})"
  puts "App has #{app.app_files.count} files"
  
  # Test ExternalViteBuilder
  puts "\nTesting ExternalViteBuilder..."
  builder = Deployment::ExternalViteBuilder.new(app)
  
  puts "Builder initialized: #{builder.class}"
  
  # Try a preview build (this should be faster)
  puts "\nAttempting fast preview build..."
  build_result = builder.build_for_preview
  
  puts "\nBuild result:"
  build_result.each do |key, value|
    if key == :built_code && value.is_a?(String)
      puts "  #{key}: #{value.length} characters"
    else
      puts "  #{key}: #{value}"
    end
  end
  
  if build_result[:success]
    puts "\n✅ Build succeeded!"
  else
    puts "\n❌ Build failed: #{build_result[:error]}"
  end
  
  puts "\nBuild test completed!"
  
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end