#!/usr/bin/env ruby
# Direct generation test - minimal example
# Run with: bin/rails runner test_direct_generation.rb

puts "Starting direct AI generation test..."

# Get existing team and user
team = Team.find_by(name: "AI Test Team") 
user = team&.memberships&.first&.user

if !team || !user
  puts "❌ No test team or user found. Run the interactive script first."
  exit 1
end

puts "✅ Using team: #{team.name}, user: #{user.email}"

# Create minimal test app
app = team.apps.create!(
  name: "Direct Test #{Time.current.to_i}",
  prompt: "Create a simple React app that displays 'Hello World' in the browser.",
  status: 'generating',
  app_type: 'tool',
  framework: 'react',
  creator: team.memberships.first
)

puts "✅ Created app: #{app.name} (ID: #{app.id})"

# Create user message
message = app.app_chat_messages.create!(
  user: user,
  role: 'user',
  content: "Create a simple React app that displays 'Hello World' in the browser."
)

puts "✅ Created message: #{message.id}"

# Test orchestrator with timeout
puts "🤖 Testing AI generation..."
start_time = Time.current

begin
  Timeout.timeout(300) do # 5 minute timeout
    orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
    orchestrator.execute!
  end
  
  duration = Time.current - start_time
  
  # Check results
  app.reload
  puts "✅ AI generation completed in #{duration.round(1)}s"
  puts "   App status: #{app.status}"
  puts "   Files created: #{app.app_files.count}"
  
  if app.app_files.any?
    puts "   Sample files:"
    app.app_files.limit(5).each { |f| puts "     - #{f.path}" }
  else
    puts "   ❌ No files were created"
  end
  
rescue Timeout::Error
  puts "❌ Generation timed out after 5 minutes"
  app.update!(status: 'failed')
rescue => e
  puts "❌ Generation error: #{e.message}"
  puts "   #{e.backtrace.first(2).join("\n   ")}"
  app.update!(status: 'failed')
end

puts "\nFinal app state:"
puts "  ID: #{app.id}"
puts "  Status: #{app.status}"
puts "  Files: #{app.app_files.count}"
puts "\nTest completed."