#!/usr/bin/env ruby
# Direct test of V3 orchestrator without background jobs

require_relative 'config/environment'

# Reset column info
AppVersion.reset_column_information

puts "Direct V3 Orchestrator Test"
puts "=" * 60

# Create test app and message
user = User.first || User.create!(
  email: 'direct@test.com',
  password: 'test123',
  first_name: 'Direct',
  last_name: 'Test'
)

team = user.current_team || Team.first
membership = team.memberships.find_by(user: user) || team.memberships.create!(
  user: user,
  user_first_name: user.first_name,
  user_last_name: user.last_name,
  user_email: user.email
)

app = team.apps.create!(
  creator: membership,
  name: "Direct V3 Test",
  slug: "direct-v3-#{SecureRandom.hex(4)}",
  prompt: "Create a simple counter app",
  app_type: "tool",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple counter app with increment and decrement buttons",
  user: user
)

puts "Created app: #{app.name} (ID: #{app.id})"
puts "Created message: #{message.content[0..50]}..."

# Test the orchestrator directly
puts "\nTesting V3 Orchestrator directly..."
begin
  orchestrator = Ai::AppUpdateOrchestratorV3.new(message)
  
  # Check initialization
  puts "✓ Orchestrator initialized"
  puts "  - App: #{orchestrator.app.name}"
  puts "  - User: #{orchestrator.user.email}"
  puts "  - New app?: #{orchestrator.instance_variable_get(:@is_new_app)}"
  
  # Execute
  puts "\nExecuting orchestrator..."
  orchestrator.execute!
  
  puts "✓ Execution complete"
  
  # Check results
  if app.reload.app_versions.any?
    version = app.app_versions.last
    puts "\nVersion created:"
    puts "  - Number: #{version.version_number}"
    puts "  - Status: #{version.status}"
    puts "  - Started: #{version.started_at}"
    puts "  - Completed: #{version.completed_at}"
  end
  
  if app.app_files.any?
    puts "\nFiles created: #{app.app_files.count}"
    app.app_files.pluck(:path).each do |path|
      puts "  - #{path}"
    end
  end
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
end

puts "\n" + "=" * 60
puts "Test complete"