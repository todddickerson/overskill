#!/usr/bin/env ruby
require_relative 'config/environment'

puts "Simple Counter Test - Direct AI Call"
puts "=" * 40

# Use the app we've been testing with
app = App.find(57)
puts "Using app: #{app.name} (ID: #{app.id})"

# Clear existing files to start fresh  
app.app_files.destroy_all
puts "Cleared #{app.app_files.count} files"

# Test direct AI generation  
puts "\nTesting direct AI call..."
begin
  client = Ai::OpenRouterClient.new
  
  # Simple counter request
  prompt = "Create a simple counter app with increment, decrement, and reset buttons. Use React with useState. Style it with Tailwind. No authentication or database needed - just local state."
  
  current_files = []
  app_context = {
    name: app.name,
    type: app.app_type,
    framework: app.framework
  }
  
  response = client.update_app(prompt, current_files, app_context)
  puts "AI Response: #{response[:success] ? 'SUCCESS' : 'FAILED'}"
  
  if response[:success]
    puts "Response content preview: #{response[:content][0..200]}..."
    
    # Try to parse the response
    require 'json'
    begin
      result = JSON.parse(response[:content], symbolize_names: true)
      puts "\nParsed successfully!"
      puts "Files to create: #{result[:files]&.length || 0}"
      
      if result[:files]
        result[:files].each do |file|
          puts "  - #{file[:path]} (#{file[:action]})"
        end
      end
    rescue JSON::ParserError => e
      puts "\nJSON parse error: #{e.message}"
      puts "Raw response: #{response[:content][0..500]}"
    end
  else
    puts "Error: #{response[:error]}"
  end
  
rescue => e
  puts "Exception: #{e.message}"
  puts e.backtrace.first(3)
end