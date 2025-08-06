#!/usr/bin/env ruby
# Debug the UnifiedAiCoordinator to find where it hangs

require_relative 'config/environment'
require 'timeout'

# Clean test setup
app = App.find_or_create_by(slug: "debug-coordinator") do |a|
  a.team = Team.first
  a.creator = Team.first.memberships.first
  a.name = "Debug Coordinator Test"
  a.prompt = "Create a simple landing page"
  a.app_type = "saas"
  a.framework = "react"
  a.status = "draft"
  a.base_price = 0
  a.visibility = "private"
end

# Clean up old data
app.app_chat_messages.destroy_all
app.app_files.destroy_all

# Create message
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple landing page with a hero section",
  user: User.first
)

puts "🔍 Debugging UnifiedAiCoordinator"
puts "="*60
puts "App: ##{app.id}"
puts "Message: ##{message.id}"

# Test each component separately
puts "\n1️⃣ Testing TodoTracker..."
begin
  todo_tracker = Ai::TodoTracker.new(app, message)
  todo_tracker.add("Test task")
  puts "✅ TodoTracker works"
rescue => e
  puts "❌ TodoTracker error: #{e.message}"
end

puts "\n2️⃣ Testing ProgressBroadcaster..."
begin
  progress = Ai::Services::ProgressBroadcaster.new(app, message)
  progress.define_stages([{name: :test, description: "Testing"}])
  puts "✅ ProgressBroadcaster works"
rescue => e
  puts "❌ ProgressBroadcaster error: #{e.message}"
end

puts "\n3️⃣ Testing MessageRouter..."
begin
  router = Ai::Services::MessageRouter.new(message)
  routing = router.route
  puts "✅ MessageRouter works: action=#{routing[:action]}"
rescue => e
  puts "❌ MessageRouter error: #{e.message}"
end

puts "\n4️⃣ Testing OpenRouterClient..."
begin
  client = Ai::OpenRouterClient.new
  Timeout::timeout(10) do
    result = client.chat([{role: "user", content: "Say hi"}], model: :claude_4, max_tokens: 50)
    puts "✅ OpenRouterClient works: #{result[:success]}"
  end
rescue => e
  puts "❌ OpenRouterClient error: #{e.message}"
end

puts "\n5️⃣ Creating coordinator..."
begin
  coordinator = Ai::UnifiedAiCoordinator.new(app, message)
  puts "✅ Coordinator created"
rescue => e
  puts "❌ Coordinator creation error: #{e.message}"
  exit 1
end

puts "\n6️⃣ Testing coordinator methods..."

# Test analyze_requirements with timeout
puts "\n   Testing analyze_requirements..."
begin
  Timeout::timeout(15) do
    analysis = coordinator.send(:analyze_requirements)
    puts "   ✅ Analysis returned: #{analysis.keys.join(', ')}"
  end
rescue Timeout::Error
  puts "   ❌ analyze_requirements timed out!"
rescue => e
  puts "   ❌ analyze_requirements error: #{e.message}"
end

# Test the main execute flow with detailed logging
puts "\n7️⃣ Testing execute! with detailed logging..."

# Monkey-patch to add logging
class Ai::UnifiedAiCoordinator
  alias_method :original_generate_new_app, :generate_new_app
  
  def generate_new_app(metadata)
    puts "   [DEBUG] Entered generate_new_app"
    
    # Add checkpoints
    puts "   [DEBUG] Defining stages..."
    @progress_broadcaster.define_stages([
      { name: :thinking, description: "Understanding requirements" },
      { name: :planning, description: "Planning structure" },
      { name: :coding, description: "Writing code" }
    ])
    
    puts "   [DEBUG] Entering thinking stage..."
    @progress_broadcaster.enter_stage(:thinking)
    
    puts "   [DEBUG] Adding analyze todo..."
    @todo_tracker.add("Analyze requirements")
    
    puts "   [DEBUG] Starting todo..."
    todo_id = @todo_tracker.todos.last[:id]
    @todo_tracker.start(todo_id)
    
    puts "   [DEBUG] Calling analyze_requirements..."
    analysis = analyze_requirements
    
    puts "   [DEBUG] Analysis complete: #{analysis.inspect[0..100]}..."
    @todo_tracker.complete(todo_id, analysis)
    
    puts "   [DEBUG] Planning from analysis..."
    @todo_tracker.plan_from_analysis(analysis)
    
    puts "   [DEBUG] Entering planning stage..."
    @progress_broadcaster.enter_stage(:planning)
    
    # Stop here for debugging
    puts "   [DEBUG] Stopping at planning stage for debug"
    @progress_broadcaster.complete("Debug stop")
  end
end

begin
  Timeout::timeout(30) do
    puts "   Starting execute!..."
    coordinator.execute!
    puts "   ✅ Execute completed!"
  end
rescue Timeout::Error
  puts "   ❌ Execute timed out after 30 seconds"
  puts "\n   Checking what was completed:"
  app.reload
  puts "   - Files: #{app.app_files.count}"
  puts "   - Assistant messages: #{app.app_chat_messages.where(role: 'assistant').count}"
  
  if last_msg = app.app_chat_messages.where(role: 'assistant').last
    puts "   - Last message: #{last_msg.content[0..100]}..."
  end
rescue => e
  puts "   ❌ Execute error: #{e.message}"
  puts "   Backtrace:"
  puts e.backtrace.first(5).map { |l| "     #{l}" }
end

puts "\n" + "="*60
puts "Debug complete!"