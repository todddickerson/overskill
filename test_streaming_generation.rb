#!/usr/bin/env ruby
# Test actual app generation with streaming

require_relative 'config/environment'

puts "Testing app generation with streaming..."

team = Team.first
abort("No team found!") unless team

app = App.create!(
  team: team,
  name: "Streaming Todo App",
  slug: "streaming-todo-#{Time.now.to_i}",
  prompt: "Create a simple todo app with add and delete functionality. Use a modern blue theme.",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"  # Will trigger auto-generation if V3 is enabled
)

puts "Created app ##{app.id} with GPT-5"
puts "AI Model: #{app.ai_model_name}"
puts "Using V3? #{app.use_v3_orchestrator?}"

# Create initial message to trigger generation
message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "Created message ##{message.id}"

# Manually trigger generation
puts "\nStarting generation..."
app.update!(status: 'generating')

# Check if V3 orchestrator is being used
if app.use_v3_orchestrator?
  puts "Using V3 orchestrator with streaming support"
  ProcessAppUpdateJobV3.perform_later(message)
else
  puts "Using legacy generation (no streaming)"
  generation = app.app_generations.create!(
    team: team,
    prompt: app.prompt,
    status: "pending",
    started_at: Time.current
  )
  AppGenerationJob.perform_later(generation)
end

puts "\n✅ Generation job queued!"
puts "\nMonitoring progress for 10 seconds..."

10.times do |i|
  sleep 1
  app.reload
  print "."
  
  if app.status != 'generating'
    puts "\n\nApp status changed to: #{app.status}"
    break
  end
  
  if app.app_files.any?
    puts "\n\nFiles being created! Current count: #{app.app_files.count}"
  end
end

puts "\n\nFinal Status:"
puts "-" * 40
puts "App Status: #{app.status}"
puts "Files Created: #{app.app_files.count}"
puts "Chat Messages: #{app.app_chat_messages.count}"

if app.app_files.any?
  puts "\nCreated Files:"
  app.app_files.each do |file|
    puts "  - #{file.path} (#{file.content.length} bytes)"
  end
end

puts "\n✅ Test complete!"
puts "View app at: http://localhost:3000/account/apps/#{app.id}/editor"