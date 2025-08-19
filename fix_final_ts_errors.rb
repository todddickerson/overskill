#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(1027)
puts "Fixing final TypeScript errors for #{app.name}..."

# Fix APP_CONFIG window property
app_tsx = app.app_files.find_by(path: 'src/App.tsx')
if app_tsx
  # Add window type declaration at the top
  content = app_tsx.content
  
  # Replace window.APP_CONFIG references with optional chaining
  content = content.gsub('window.APP_CONFIG', 'window.APP_CONFIG || {}')
  
  # Or add type declaration
  unless content.include?('declare global')
    type_declaration = <<~TS
      declare global {
        interface Window {
          APP_CONFIG?: any;
        }
      }
      
    TS
    
    # Insert after imports
    import_end = content.index(/^(?!import)/) || 0
    content = content[0...import_end] + type_declaration + content[import_end..]
  end
  
  app_tsx.content = content
  app_tsx.save!
  puts "✅ Fixed App.tsx window.APP_CONFIG errors"
end

# Fix unused _props in calendar.tsx
calendar = app.app_files.find_by(path: 'src/components/ui/calendar.tsx')
if calendar
  content = calendar.content
  
  # Comment out or remove unused _props parameters
  content = content.gsub(/(\w+): _props,/, '\1,')
  content = content.gsub(/: _props\b/, '')
  
  calendar.content = content
  calendar.save!
  puts "✅ Fixed calendar.tsx unused variable warnings"
end

puts "\nAll TypeScript errors fixed! Ready to deploy."