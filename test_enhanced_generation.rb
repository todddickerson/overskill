#!/usr/bin/env ruby
require_relative 'config/environment'

# Test enhanced StructuredAppGenerator with all requirements
puts "\n=== Testing Enhanced StructuredAppGenerator ==="

generator = Ai::StructuredAppGenerator.new
result = generator.generate(
  "Create a todo list app with add, edit, delete, and complete features",
  framework: "react",
  app_type: "saas"
)

if result[:success]
  puts "✅ Generation successful!"
  puts "\nApp Info:"
  puts "  Name: #{result[:app]['name']}" if result[:app]
  puts "  Description: #{result[:app]['description']}" if result[:app]
  
  puts "\nFiles generated: #{result[:files].size}"
  result[:files].each do |file|
    puts "  - #{file['path']} (#{file['content'].size} bytes)"
  end
  
  # Check for critical files
  puts "\nCritical files check:"
  paths = result[:files].map { |f| f['path'] }
  
  critical_files = [
    'src/lib/supabase.ts',
    'src/lib/analytics.ts',
    'wrangler.toml',
    'package.json',
    'vite.config.ts',
    'tailwind.config.js'
  ]
  
  critical_files.each do |path|
    if paths.include?(path)
      file = result[:files].find { |f| f['path'] == path }
      content_preview = file['content'][0..100] rescue ''
      puts "  ✅ #{path} - #{content_preview.include?('...') ? 'placeholder' : 'has content'}"
    else
      puts "  ❌ #{path} - missing"
    end
  end
  
  # Check Supabase integration
  supabase_file = result[:files].find { |f| f['path'] == 'src/lib/supabase.ts' }
  if supabase_file
    content = supabase_file['content']
    puts "\nSupabase integration check:"
    puts "  #{content.include?('createClient') ? '✅' : '❌'} createClient function"
    puts "  #{content.include?('setRLSContext') ? '✅' : '❌'} setRLSContext function"
    puts "  #{content.include?('VITE_SUPABASE_URL') ? '✅' : '❌'} Environment variables"
  end
  
  # Check analytics
  analytics_file = result[:files].find { |f| f['path'] == 'src/lib/analytics.ts' }
  if analytics_file
    content = analytics_file['content']
    puts "\nAnalytics check:"
    puts "  #{content.include?('OverskillAnalytics') ? '✅' : '❌'} OverskillAnalytics class"
    puts "  #{content.include?('track') ? '✅' : '❌'} track method"
    puts "  #{content.include?('overskill.app/api/v1/analytics') ? '✅' : '❌'} Analytics endpoint"
  end
  
else
  puts "❌ Generation failed: #{result[:error]}"
end

puts "\n=== Test Complete ===="