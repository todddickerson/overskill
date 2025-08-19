require_relative 'config/environment'

# Find App 1025 and test the updated validation
app = App.find(1025)
builder = Ai::AppBuilderV5.new(app.app_chat_messages.last)

# Test the validation with our updated logic
puts "\n=== Testing Updated Validation on App 1025 ==="
errors = builder.send(:validate_imports)

if errors.empty?
  puts "✅ No import errors detected! Validation fixed successfully."
else
  puts "❌ Still detecting errors:"
  errors.each { |e| puts "  - #{e}" }
end

# Check specific file
file = app.app_files.find_by(path: "src/components/FeaturesSection.tsx")
if file
  content = file.content
  
  # Show what components are actually imported
  imported = []
  content.scan(/import\s*{([^}]+)}\s*from\s+['"]lucide-react['"]/).each do |imports|
    imported.concat(imports[0].split(',').map(&:strip))
  end
  
  puts "\n=== Lucide Icons Already Imported ==="
  puts imported.join(", ")
  
  # Check for dynamic variables  
  dynamic_vars = content.scan(/const\s+(\w+)\s*=\s*\w+\.\w+/).flatten
  puts "\n=== Dynamic Variables Detected ==="
  puts dynamic_vars.join(", ")
end
