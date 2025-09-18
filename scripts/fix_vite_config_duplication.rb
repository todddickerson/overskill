#!/usr/bin/env ruby
# Fix vite config duplication issue

puts '🔧 FIXING VITE CONFIG DUPLICATION'
puts '=' * 50

app = App.find('jOyYVe')

# Remove the duplicate .js file since .ts is more comprehensive
js_config = app.app_files.find_by(path: 'vite.config.js')
if js_config
  puts "\n❌ Removing duplicate vite.config.js..."
  js_config.destroy!
  puts "✅ Deleted vite.config.js"
else
  puts "\n✅ vite.config.js already removed"
end

# Check remaining files
remaining_configs = app.app_files.where("path LIKE 'vite.config.%'")
puts "\n📊 Remaining Vite configs:"
remaining_configs.each do |config|
  puts "  - #{config.path} (#{config.content.length} chars)"
end

puts "\n🎯 SOLUTION: Keep only vite.config.ts (the comprehensive version)"
puts "This eliminates the conflict and uses our auto-dependency detection for terser"

puts "\n✅ VITE CONFIG DUPLICATION FIXED!"