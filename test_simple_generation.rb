#!/usr/bin/env ruby
require_relative 'config/environment'

# Quick test of StructuredAppGenerator
puts "\n=== Testing Direct StructuredAppGenerator ==="

generator = Ai::StructuredAppGenerator.new
result = generator.generate(
  "Create a simple counter app with React",
  framework: "react",
  app_type: "saas"
)

if result[:success]
  puts "✅ Generation successful!"
  puts "Files: #{result[:files].size}"
  result[:files].each do |file|
    puts "  - #{file['path']}"
  end
else
  puts "❌ Generation failed: #{result[:error]}"
end