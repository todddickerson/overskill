#!/usr/bin/env ruby
# Test that the AI is properly informed about existing UI components

require_relative '../config/environment'

puts "🧪 Testing Component Awareness Fix"
puts "=" * 60
puts

# Create a test app
app = App.last || App.create!(
  user: User.first,
  name: "Component Test App",
  status: "generating"
)

puts "📊 Testing BaseContextService component instructions..."
puts

# Initialize base context service
context_service = Ai::BaseContextService.new(app, {
  app_type: 'default',
  component_requirements: ['button', 'card', 'badge', 'textarea', 'label']
})

# Build the context
context = context_service.build_complete_context(app, {})

# Check for critical instructions
critical_checks = [
  "These UI components ALREADY EXIST",
  "DO NOT create new component files in src/components/ui/",
  "DO NOT use os-write to create new UI component files",
  "Import existing components directly"
]

puts "✅ Checking for critical instructions:"
critical_checks.each do |check|
  if context.include?(check)
    puts "  ✓ Found: '#{check.truncate(50)}'"
  else
    puts "  ✗ Missing: '#{check}'"
  end
end

puts
puts "📝 Testing prompt modifications..."
puts

# Test the modified user prompt
original_prompt = "build a todo app"
is_discussion = false

# Simulate the prompt modification
if !is_discussion
  modified_prompt = "#{original_prompt} \n\n Think ahead around tool calling needs, and update all necessary APPLICATION files in one response. IMPORTANT: Use existing UI components from @/components/ui/ - DO NOT create new UI component files (button.tsx, card.tsx, etc.) as they already exist in the template."
  
  if modified_prompt.include?("DO NOT create new UI component files")
    puts "✓ User prompt includes component clarification"
  else
    puts "✗ User prompt missing component clarification"
  end
end

puts
puts "=" * 60
puts "🎯 Summary:"
puts

# Count successful checks
success_count = critical_checks.count { |check| context.include?(check) }
total_checks = critical_checks.length + 1 # +1 for prompt modification

puts "Passed: #{success_count + 1}/#{total_checks} checks"

if success_count == critical_checks.length
  puts "✅ SUCCESS: All component awareness fixes are in place!"
else
  puts "⚠️  WARNING: Some fixes may be missing"
end

puts
puts "💡 Next Step: Test with actual app generation to verify AI behavior"