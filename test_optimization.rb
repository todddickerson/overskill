#!/usr/bin/env rails runner
# Test script for system prompt cache optimization
# This tests the new optimizations including ComponentRequirementsAnalyzer

puts "🚀 Starting System Prompt Cache Optimization Test"
puts "=" * 60

# Find or create test app
user = User.first || User.create!(email: "test@example.com", password: "password123")
team = user.teams.first || user.teams.create!(name: "Test Team")
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user)

# Create a new app for testing
app = App.create!(
  team: team,
  creator: membership,
  name: "Task Manager Pro",
  prompt: "Create a todo task manager with checkboxes, input fields for adding tasks, and cards to display each task. Include a button to mark tasks complete.",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "✅ Created test app: #{app.name} (ID: #{app.id})"
puts ""

# Create user chat message
user_message = AppChatMessage.create!(
  app: app,
  user: user,
  role: 'user',
  content: app.prompt
)

puts "📝 User prompt: #{app.prompt}"
puts ""

# Test ComponentRequirementsAnalyzer predictions
puts "🔮 Testing ComponentRequirementsAnalyzer..."
analyzer_result = Ai::ComponentRequirementsAnalyzer.analyze_with_confidence(
  app.prompt,
  [],
  { app_type: app.app_type }
)

puts "  Detected app type: #{analyzer_result[:app_type]}"
puts "  Predicted components: #{analyzer_result[:components].join(', ')}"
puts "  Reasoning:"
analyzer_result[:reasoning].each { |r| puts "    - #{r}" }
puts ""

# Reset cache metrics
Ai::CacheMetricsService.reset_metrics

# Test BaseContextService with optimizations
puts "📦 Testing BaseContextService..."
context_service = Ai::BaseContextService.new(app)

# Build the useful context that would be provided to Claude
context_xml = context_service.build_useful_context

# Count files in the context
file_count = context_xml.scan(/<useful-context/).count
component_count = context_xml.scan(/src\/components\/ui\//).count
essential_count = Ai::BaseContextService::ESSENTIAL_FILES.count { |f| context_xml.include?(f) }

# Extract component names from the context
component_matches = context_xml.scan(/src\/components\/ui\/(\w+)\.tsx/)
component_names = component_matches.flatten.uniq

puts "  Files in context: #{file_count}"
puts "  Essential files included: #{essential_count}/#{Ai::BaseContextService::ESSENTIAL_FILES.count}"
puts "  UI components included: #{component_count}"
puts "  Component names: #{component_names.join(', ')}"
puts "  Context size: #{context_xml.length} characters (~#{(context_xml.length / 3.5).to_i} tokens)"
puts ""

# Build the optimized prompt
puts "🏗️  Building optimized system prompt..."

# Load template files manually for analysis
template_dir = Rails.root.join('app/templates/overskill_20250728')
template_files = []

# Load essential files
Ai::BaseContextService::ESSENTIAL_FILES.each do |file_path|
  full_path = template_dir.join(file_path)
  if File.exist?(full_path)
    template_files << OpenStruct.new(
      path: file_path,
      content: File.read(full_path)
    )
  end
end

# Load predicted component files
component_names.each do |component|
  file_path = "src/components/ui/#{component}.tsx"
  full_path = template_dir.join(file_path)
  if File.exist?(full_path)
    template_files << OpenStruct.new(
      path: file_path,
      content: File.read(full_path)
    )
  end
end

prompt_builder = Ai::Prompts::GranularCachedPromptBuilder.new(
  base_prompt: File.read(Rails.root.join('app/services/ai/prompts/agent-prompt.txt')),
  template_files: template_files,
  context_data: { app: app },
  app_id: app.id
)

system_blocks = prompt_builder.build_granular_system_prompt

puts "  Total blocks: #{system_blocks.count}"
system_blocks.each_with_index do |block, idx|
  cached = block[:cache_control].present? ? "CACHED (#{block[:cache_control][:ttl]})" : "UNCACHED"
  size = block[:text].length
  tokens = (size / 3.5).to_i
  puts "  Block #{idx + 1}: #{cached} - #{size} chars (~#{tokens} tokens)"
end

total_chars = system_blocks.sum { |b| b[:text].length }
total_tokens = (total_chars / 3.5).to_i
cached_blocks = system_blocks.count { |b| b[:cache_control].present? }

puts ""
puts "📊 Optimization Results:"
puts "  Total characters: #{total_chars}"
puts "  Estimated tokens: #{total_tokens}"
puts "  Cached blocks: #{cached_blocks}/#{system_blocks.count}"
puts "  Target: <30,000 tokens"
puts "  Status: #{total_tokens < 30_000 ? '✅ OPTIMIZED' : '⚠️  NEEDS WORK'}"
puts ""

# Verify component prediction accuracy
predicted_components = analyzer_result[:components]
expected_components = %w[input checkbox button card]
correct_predictions = predicted_components & expected_components
accuracy = (correct_predictions.size.to_f / expected_components.size * 100).round(1)

puts "🎯 Component Prediction Accuracy:"
puts "  Expected: #{expected_components.join(', ')}"
puts "  Predicted: #{predicted_components.join(', ')}"
puts "  Correct predictions: #{correct_predictions.join(', ')}"
puts "  Accuracy: #{accuracy}%"
puts ""

# Show cost comparison
standard_cost = (134_000 * 15.0) / 1_000_000  # $15 per million
optimized_cost = (total_tokens * 15.0) / 1_000_000
savings = ((1 - optimized_cost / standard_cost) * 100).round(1)

puts "💰 Cost Analysis:"
puts "  Standard approach: 134,000 tokens = $#{standard_cost.round(4)}"
puts "  Optimized approach: #{total_tokens} tokens = $#{optimized_cost.round(4)}"
puts "  Savings: #{savings}% reduction"
puts ""

# Clean up
app.destroy!
puts "🧹 Cleaned up test app"
puts ""
puts "✅ Test completed successfully!"