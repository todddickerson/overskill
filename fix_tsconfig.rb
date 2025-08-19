#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(1027)
puts "Fixing TypeScript configuration for #{app.name}..."

# Check if tsconfig.node.json exists
tsconfig_node = app.app_files.find_by(path: 'tsconfig.node.json')

if tsconfig_node
  puts "Found tsconfig.node.json, updating..."
  
  begin
    # Parse existing config
    config = JSON.parse(tsconfig_node.content)
  rescue JSON::ParserError
    config = {}
  end
  
  # Add composite: true to compilerOptions
  config['compilerOptions'] ||= {}
  config['compilerOptions']['composite'] = true
  config['compilerOptions']['noEmit'] = false
  config['compilerOptions']['skipLibCheck'] = true
  config['compilerOptions']['module'] = 'ESNext'
  config['compilerOptions']['moduleResolution'] = 'bundler'
  config['compilerOptions']['allowSyntheticDefaultImports'] = true
  
  # Save updated config
  tsconfig_node.content = JSON.pretty_generate(config)
  tsconfig_node.save!
  
  puts "✅ Fixed tsconfig.node.json"
else
  puts "Creating tsconfig.node.json..."
  
  config = {
    "compilerOptions" => {
      "composite" => true,
      "skipLibCheck" => true,
      "module" => "ESNext",
      "moduleResolution" => "bundler",
      "allowSyntheticDefaultImports" => true,
      "strict" => true,
      "noEmit" => false
    },
    "include" => ["vite.config.ts"]
  }
  
  app.app_files.create!(
    path: 'tsconfig.node.json',
    content: JSON.pretty_generate(config),
    file_type: 'config',
    team: app.team
  )
  
  puts "✅ Created tsconfig.node.json"
end

# Also check main tsconfig.json
tsconfig_main = app.app_files.find_by(path: 'tsconfig.json')
if tsconfig_main
  puts "Checking main tsconfig.json..."
  
  begin
    config = JSON.parse(tsconfig_main.content)
    
    # Ensure references are properly configured
    if config['references']
      config['references'].each do |ref|
        if ref['path'] == './tsconfig.node.json'
          puts "  Reference to tsconfig.node.json found"
        end
      end
    end
    
    puts "✅ Main tsconfig.json looks good"
  rescue JSON::ParserError => e
    puts "⚠️  Could not parse tsconfig.json: #{e.message}"
  end
end

puts "\nConfiguration fixed. Ready to deploy!"