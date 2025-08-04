#!/usr/bin/env ruby

# Test function calling with full generation pipeline
require_relative 'config/environment'

puts "=== TESTING FUNCTION CALLING IN PRODUCTION ==="

app = App.find(18)
puts "Using app: #{app.name}"

# Create test generation
generation = app.app_generations.create!(
  team: app.team,
  prompt: "Create a simple weather app with location search and current conditions display",
  status: "pending",
  started_at: Time.current
)

puts "Created test generation: #{generation.id}"
puts "Testing function calling with full pipeline..."

# Enable verbose logging
ENV["VERBOSE_AI_LOGGING"] = "true"

begin
  # Test the full generation service
  service = Ai::AppGeneratorService.new(app, generation)
  result = service.generate!
  
  puts "\n=== GENERATION RESULT ==="
  puts "Success: #{result[:success]}"
  
  if result[:success]
    puts "✅ Function calling generation successful!"
    
    # Check the generation record
    generation.reload
    puts "Generation status: #{generation.status}"
    puts "Files created: #{app.app_files.count}"
    puts "App status: #{app.status}"
    
    # List the files
    puts "\nFiles created:"
    app.app_files.each do |file|
      puts "  - #{file.path} (#{file.size_bytes} bytes)"
    end
    
  else
    puts "❌ Generation failed: #{result[:error]}"
    
    generation.reload
    puts "Generation status: #{generation.status}"
    puts "Error message: #{generation.error_message}"
  end
  
rescue => e
  puts "❌ Exception during generation: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n=== TEST COMPLETE ==="