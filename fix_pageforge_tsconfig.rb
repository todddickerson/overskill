#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(1027)
puts "Fixing TypeScript configuration for #{app.name}..."

# Fix tsconfig.json to add paths
tsconfig = app.app_files.find_by(path: 'tsconfig.json')
if tsconfig
  config = JSON.parse(tsconfig.content)
  config['compilerOptions'] ||= {}
  config['compilerOptions']['baseUrl'] = '.'
  config['compilerOptions']['paths'] = {
    '@/*' => ['./src/*']
  }
  
  tsconfig.content = JSON.pretty_generate(config)
  tsconfig.save!
  puts "✅ Fixed tsconfig.json with TypeScript paths"
end

# Also ensure tsconfig.node.json has composite: true
tsconfig_node = app.app_files.find_by(path: 'tsconfig.node.json')
if tsconfig_node
  config = JSON.parse(tsconfig_node.content)
  config['compilerOptions'] ||= {}
  config['compilerOptions']['composite'] = true
  config['compilerOptions']['noEmit'] = false
  
  tsconfig_node.content = JSON.pretty_generate(config)
  tsconfig_node.save!
  puts "✅ Fixed tsconfig.node.json with composite setting"
end

puts "\nConfiguration fixed. Ready to deploy!"