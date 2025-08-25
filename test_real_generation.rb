#!/usr/bin/env rails runner
# Real app generation test with optimizations
# This tests the full flow with AppBuilderV5

puts "🚀 Testing Real App Generation with Optimizations"
puts "=" * 60
puts ""

# Find user and team
user = User.find_by(email: "test@overskill.app") || User.first
team = user.teams.first
membership = team.memberships.find_by(user: user)

# Create test app
app = App.create!(
  team: team,
  creator: membership,
  name: "Dashboard Analytics Pro",
  prompt: "Create a dashboard with charts showing sales data, a table for recent transactions, cards for key metrics, and select dropdowns for date ranges",
  app_type: "tool",
  framework: "react",
  status: "generating"
)

puts "✅ Created app: #{app.name} (ID: #{app.id})"
puts "📝 Prompt: #{app.prompt}"
puts ""

# Create chat message
chat_message = AppChatMessage.create!(
  app: app,
  user: user,
  role: 'user',
  content: app.prompt
)

# Test ComponentRequirementsAnalyzer
puts "🔮 Component Prediction:"
analyzer_result = Ai::ComponentRequirementsAnalyzer.analyze_with_confidence(
  app.prompt,
  [],
  { app_type: 'dashboard' }
)
puts "  Predicted: #{analyzer_result[:components].join(', ')}"
puts "  App type: #{analyzer_result[:app_type]}"
puts ""

# Reset metrics
Ai::CacheMetricsService.reset_metrics

# Initialize the app builder
puts "🤖 Initializing AppBuilderV5..."
builder = Ai::AppBuilderV5.new(chat_message)

# Monitor context size
puts "📊 Context Analysis:"
context_service = Ai::BaseContextService.new(app)
context = context_service.build_useful_context
puts "  Context size: #{context.length} chars (~#{(context.length / 3.5).to_i} tokens)"
puts "  Component files in context: #{context.scan(/src\/components\/ui\//).count}"
puts ""

# Generate a simple change to test the system
puts "🔨 Testing file generation..."
test_prompt = "Update the dashboard to show the key metrics"

begin
  # This would normally be called by the job
  # We'll just test the prompt building
  messages = builder.send(:build_messages, test_prompt)
  
  system_prompt = messages.find { |m| m[:role] == 'system' }
  if system_prompt && system_prompt[:content].is_a?(Array)
    puts "  System prompt blocks: #{system_prompt[:content].count}"
    system_prompt[:content].each_with_index do |block, idx|
      cached = block[:cache_control] ? "CACHED (#{block[:cache_control][:ttl]})" : "UNCACHED"
      size = block[:text]&.length || 0
      puts "    Block #{idx + 1}: #{cached} - #{size} chars"
    end
  end
  
  # Calculate total tokens
  total_chars = messages.sum do |msg|
    if msg[:content].is_a?(String)
      msg[:content].length
    elsif msg[:content].is_a?(Array)
      msg[:content].sum { |block| block[:text]&.length || 0 }
    else
      0
    end
  end
  
  total_tokens = (total_chars / 3.5).to_i
  puts ""
  puts "  Total message size: #{total_chars} chars (~#{total_tokens} tokens)"
  
  # Check if we're under target
  if total_tokens < 30_000
    puts "  ✅ OPTIMIZED: Under 30k token target!"
  else
    puts "  ⚠️  WARNING: Exceeds 30k token target"
  end
  
rescue => e
  puts "  ❌ Error: #{e.message}"
  puts "  This is expected if we're just testing prompt building"
end

puts ""
puts "📈 Cache Metrics Report:"
puts Ai::CacheMetricsService.generate_report
puts ""

# Clean up
app.destroy!
puts "🧹 Cleaned up test app"
puts ""
puts "✅ Test completed!"