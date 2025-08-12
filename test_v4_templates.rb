#!/usr/bin/env ruby

# Test V4 template generation
require_relative './config/environment'

begin
  puts 'Testing V4 template generation...'
  
  # Find the test app we created
  app = App.find_by(name: 'V4 Test App')
  if app.nil?
    puts 'ERROR: Test app not found. Run test_v4_basic.rb first.'
    exit 1
  end
  
  puts "Using app: #{app.id} (#{app.name})"
  
  # Test SharedTemplateService template generation
  template_service = Ai::SharedTemplateService.new(app)
  
  puts "\nBefore template generation:"
  puts "App has #{app.app_files.count} files"
  
  # Try to generate core files
  puts "\nGenerating core template files..."
  template_service.generate_core_files
  
  puts "\nAfter template generation:"
  app.reload
  puts "App has #{app.app_files.count} files"
  
  # List the files that were created
  puts "\nGenerated files:"
  app.app_files.order(:path).each do |file|
    puts "  #{file.path} (#{file.content.length} chars)"
  end
  
  puts "\nTemplate generation test completed!"
  
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end