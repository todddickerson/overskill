#!/usr/bin/env ruby
require_relative 'config/environment'

app_id = ARGV[0] || 148
app = App.find(app_id)

puts "App ##{app.id}: #{app.name}"
puts "="*60

app.app_files.each do |file|
  puts "\nFile: #{file.path} (#{file.content.length} bytes)"
  puts "-"*40
  puts file.content
  puts "-"*40
end