#!/usr/bin/env ruby

# Test script for app version restore functionality
require_relative 'config/environment'

app = App.find(18)
version_20 = app.app_versions.find_by(version_number: '1.0.20')

puts "=== TESTING APP VERSION RESTORE ==="
puts "App: #{app.name}"
puts "Version to restore: #{version_20.version_number}"
puts

puts "Before restore - Current files:"
app.app_files.each { |f| puts "  #{f.path}: #{f.content.first(50).gsub("\n", ' ')}..." }

# Test the restore logic - use User 2 who is in Team 2
new_version = app.app_versions.build(
  team: app.team,
  user: User.find(2),
  version_number: '1.0.27',
  changelog: "Restored from version #{version_20.version_number}"
)

if new_version.save
  files_restored = 0
  
  if version_20.files_snapshot.present?
    snapshot_files = JSON.parse(version_20.files_snapshot)
    
    puts "\nRestoring from snapshot with #{snapshot_files.size} files:"
    
    snapshot_files.each do |file_data|
      path = file_data['path']
      content = file_data['content']
      
      # Skip non-essential files
      if path.include?('src/') || path.include?('public/') || path.include?('package.json')
        puts "  SKIP: #{path}"
        next
      end
      
      # Find or create the app file
      app_file = app.app_files.find_or_create_by(path: path) do |af|
        af.team = app.team
        af.file_type = case File.extname(path).downcase
          when '.js', '.jsx' then 'javascript'
          when '.css' then 'css'
          when '.html' then 'html'
          when '.json' then 'json'
          else 'other'
        end
        af.is_entry_point = (path == 'index.html')
      end
      
      # Update with restored content
      app_file.update!(
        content: content,
        size_bytes: content.bytesize
      )
      
      files_restored += 1
      puts "  RESTORED: #{path} (#{content.bytesize} bytes)"
    end
  end
  
  puts "\n=== RESTORE COMPLETED ==="
  puts "Files restored: #{files_restored}"
  puts "New version: #{new_version.version_number}"
  
  puts "\nAfter restore - Current files:"
  app.reload.app_files.each { |f| puts "  #{f.path}: #{f.content.first(50).gsub("\n", ' ')}..." }
  
  puts "\n=== VERIFICATION ==="
  # Check if index.html content changed
  restored_index = app.app_files.find_by(path: 'index.html')
  if restored_index&.content&.include?("Jason's Todos")
    puts "✅ SUCCESS: index.html now contains Jason's Todos"
  else
    puts "❌ FAILED: index.html does not contain expected content"
  end
  
else
  puts "❌ FAILED to create new version: #{new_version.errors.full_messages}"
end