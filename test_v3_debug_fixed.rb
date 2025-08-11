#!/usr/bin/env ruby
# Debug V3 orchestrator to find why no files are created

ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_STREAMING'] = 'false'  # Disable streaming for simpler testing
ENV['VERBOSE_AI_LOGGING'] = 'true'
ENV['DEBUG'] = 'true'

require_relative 'config/environment'

puts "="*80
puts "V3 Orchestrator Debug Test"
puts "="*80

team = Team.first
abort("No team found!") unless team

# Create simple test app
app = App.create!(
  team: team,
  name: "Debug Test #{Time.now.to_i}",
  slug: "debug-test-#{Time.now.to_i}",
  prompt: "Create a simple hello world app with a button that shows an alert",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

puts "\n✅ Created app ##{app.id}"

message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "✅ Created message ##{message.id}"

# Initialize orchestrator directly
puts "\n🔧 Initializing V3 Orchestrator..."
orchestrator = Ai::AppUpdateOrchestratorV3.new(message)

# Check configuration
puts "\nConfiguration:"
puts "  Provider: #{orchestrator.instance_variable_get(:@provider)}"
puts "  Model: #{orchestrator.instance_variable_get(:@model)}"
puts "  Is new app: #{orchestrator.instance_variable_get(:@is_new_app)}"
puts "  Use streaming: #{orchestrator.instance_variable_get(:@use_streaming)}"

# Run execute! and capture all output
puts "\n📊 Executing orchestrator..."
puts "-"*40

begin
  # Execute
  orchestrator.execute!
  puts "\n✅ Orchestrator completed"
  
rescue => e
  puts "\n❌ Orchestrator failed:"
  puts "  Error: #{e.message}"
  puts "\n  Backtrace:"
  puts e.backtrace.first(5).map { |l| "    #{l}" }.join("\n")
end

# Check results
app.reload
puts "\n📊 Results:"
puts "-"*40
puts "App status: #{app.status}"
puts "Files created: #{app.app_files.count}"
puts "Chat messages: #{app.app_chat_messages.count}"

if app.app_files.any?
  puts "\nFiles:"
  app.app_files.each do |file|
    puts "  - #{file.path}"
  end
else
  puts "\n⚠️  No files were created!"
  
  # Check last message
  last_msg = app.app_chat_messages.order(:created_at).last
  if last_msg
    puts "\nLast message (#{last_msg.role}):"
    puts "  Status: #{last_msg.status}"
    puts "  Content: #{last_msg.content[0..500]}"
  end
end

puts "\n" + "="*80
puts "Debug test complete"
puts "="*80
