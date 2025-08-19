#!/usr/bin/env ruby
require_relative 'config/environment'

# Find the latest app
latest_app = App.joins(:app_files).order(created_at: :desc).first

if latest_app.nil?
  puts "No apps found with files"
  exit
end

puts "=" * 80
puts "App ID: #{latest_app.id}"
puts "App Name: #{latest_app.name}"
puts "Created: #{latest_app.created_at}"
puts "Total Files: #{latest_app.app_files.count}"
puts "=" * 80

# Analyze file sizes
total_size = 0
file_details = []

latest_app.app_files.each do |file|
  size = file.content.to_s.bytesize
  total_size += size
  file_details << {
    path: file.path,
    size: size,
    size_kb: (size / 1024.0).round(2),
    size_mb: (size / 1024.0 / 1024.0).round(3)
  }
end

puts "\nTotal Size: #{(total_size / 1024.0 / 1024.0).round(2)} MB (#{total_size} bytes)"
puts "\nFile Breakdown by Size (largest first):"
puts "-" * 80

file_details.sort_by { |f| -f[:size] }.each do |file|
  if file[:size_mb] > 0.1
    puts "  #{file[:path].ljust(50)} #{file[:size_mb].to_s.rjust(8)} MB"
  elsif file[:size_kb] > 10
    puts "  #{file[:path].ljust(50)} #{file[:size_kb].to_s.rjust(8)} KB"
  end
end

# File type analysis
puts "\n" + "=" * 80
puts "File Type Analysis:"
puts "-" * 80

file_types = Hash.new { |h, k| h[k] = { count: 0, total_size: 0, files: [] } }

latest_app.app_files.each do |file|
  ext = File.extname(file.path).downcase
  ext = "(no extension)" if ext.empty?
  size = file.content.to_s.bytesize
  
  file_types[ext][:count] += 1
  file_types[ext][:total_size] += size
  file_types[ext][:files] << { path: file.path, size: size }
end

file_types.sort_by { |_, info| -info[:total_size] }.each do |ext, info|
  size_mb = (info[:total_size] / 1024.0 / 1024.0).round(3)
  size_kb = (info[:total_size] / 1024.0).round(2)
  
  if size_mb > 0.1
    puts "  #{ext.ljust(20)} #{info[:count].to_s.rjust(5)} files, #{size_mb.to_s.rjust(10)} MB total"
  else
    puts "  #{ext.ljust(20)} #{info[:count].to_s.rjust(5)} files, #{size_kb.to_s.rjust(10)} KB total"
  end
  
  # Show largest files of this type if significant
  if info[:total_size] > 100_000 # > 100KB
    info[:files].sort_by { |f| -f[:size] }.first(3).each do |file|
      size_kb = (file[:size] / 1024.0).round(2)
      puts "    - #{file[:path].ljust(45)} #{size_kb.to_s.rjust(10)} KB"
    end
  end
end

# Check for potential issues
puts "\n" + "=" * 80
puts "Potential Issues:"
puts "-" * 80

# Check for images
image_extensions = %w[.png .jpg .jpeg .gif .webp .svg .ico]
image_files = latest_app.app_files.select { |f| image_extensions.include?(File.extname(f.path).downcase) }
if image_files.any?
  total_image_size = image_files.sum { |f| f.content.to_s.bytesize }
  puts "⚠️  Found #{image_files.count} image files totaling #{(total_image_size / 1024.0).round(2)} KB"
  image_files.each do |file|
    size_kb = (file.content.to_s.bytesize / 1024.0).round(2)
    puts "    - #{file.path}: #{size_kb} KB"
  end
end

# Check for large dependencies in package.json
package_json_file = latest_app.app_files.find_by(path: 'package.json')
if package_json_file
  begin
    package_json = JSON.parse(package_json_file.content)
    deps = (package_json['dependencies'] || {}).merge(package_json['devDependencies'] || {})
    
    # Known large dependencies
    large_deps = {
      'moment' => '~290KB',
      'lodash' => '~70KB', 
      'axios' => '~400KB',
      '@mui/material' => '~2.5MB',
      'antd' => '~2MB',
      'chart.js' => '~200KB',
      'three' => '~600KB',
      'd3' => '~350KB'
    }
    
    found_large_deps = deps.keys & large_deps.keys
    if found_large_deps.any?
      puts "\n⚠️  Large dependencies detected in package.json:"
      found_large_deps.each do |dep|
        puts "    - #{dep}: #{large_deps[dep]}"
      end
    end
  rescue JSON::ParserError
    puts "  Could not parse package.json"
  end
end

# Check for duplicate or unnecessary files
puts "\n" + "=" * 80
puts "Recommendations:"
puts "-" * 80

if total_size > 5_000_000 # > 5MB
  puts "🚨 Total size exceeds 5MB - will need optimization for Cloudflare Workers"
  puts "   Current: #{(total_size / 1024.0 / 1024.0).round(2)} MB"
  puts "   Target: < 10MB (hard limit)"
  puts "   Recommended: < 5MB for performance"
end

if image_files.any?
  puts "\n📦 Move images to R2 storage instead of embedding in Worker"
end

# Check for font files
font_files = latest_app.app_files.select { |f| %w[.woff .woff2 .ttf .otf .eot].include?(File.extname(f.path).downcase) }
if font_files.any?
  total_font_size = font_files.sum { |f| f.content.to_s.bytesize }
  puts "\n📦 Move #{font_files.count} font files (#{(total_font_size / 1024.0).round(2)} KB) to R2 storage"
end

puts "\n" + "=" * 80