#!/usr/bin/env ruby
# Test script for V3 orchestrator - Fresh environment

# Force Rails to reload all models
if defined?(Rails)
  Rails.application.eager_load!
  ActiveRecord::Base.descendants.each(&:reset_column_information)
end

require_relative 'config/environment'

# Ensure models are reloaded with new columns
AppVersion.reset_column_information
App.reset_column_information

puts "Testing V3 Orchestrator (GPT-5 Optimized) - Fresh Environment"
puts "=" * 60

# Verify columns exist
puts "\nVerifying AppVersion columns:"
required_columns = %w[status started_at completed_at metadata error_message]
missing = required_columns - AppVersion.column_names
if missing.empty?
  puts "✓ All required columns present"
else
  puts "✗ Missing columns: #{missing.join(', ')}"
  puts "Run: bin/rails db:migrate"
  exit 1
end

# Ensure V3 is enabled
ENV['USE_V3_ORCHESTRATOR'] = 'true'

# Find or create test user
user = User.find_by(email: 'test-v3@overskill.app') || User.create!(
  email: 'test-v3@overskill.app',
  password: 'test123456',
  first_name: 'V3',
  last_name: 'Tester'
)

team = user.current_team || user.teams.first || Team.create!(
  name: "V3 Test Team"
)

membership = team.memberships.find_by(user: user) || team.memberships.create!(
  user: user,
  user_first_name: user.first_name,
  user_last_name: user.last_name,
  user_email: user.email
)

puts "\nTest Environment:"
puts "User: #{user.email}"
puts "Team: #{team.name}"
puts "V3 Enabled: #{ENV['USE_V3_ORCHESTRATOR']}"

# Simple test: Create a basic app
puts "\n" + "=" * 60
puts "Creating simple test app with V3"
puts "=" * 60

begin
  test_app = team.apps.create!(
    creator: membership,
    name: "V3 Test #{Time.current.to_i}",
    slug: "v3-test-#{SecureRandom.hex(4)}",
    prompt: "Create a simple hello world app",
    app_type: "tool",
    framework: "react",
    base_price: 0,
    visibility: "private"
  )
  
  puts "✓ App created: #{test_app.name} (ID: #{test_app.id})"
  puts "✓ Status: #{test_app.status}"
  
  # Check for message creation
  if test_app.app_chat_messages.any?
    msg = test_app.app_chat_messages.first
    puts "✓ Message created: #{msg.role} - #{msg.content[0..30]}..."
  end
  
  # Manually trigger generation to test
  puts "\nManually triggering generation..."
  test_app.initiate_generation!
  
  puts "✓ Generation initiated"
  
  # Check for version
  if test_app.app_versions.any?
    version = test_app.app_versions.last
    puts "✓ Version created: #{version.version_number}"
    puts "  - Status: #{version.status}"
    puts "  - Started at: #{version.started_at || 'pending'}"
  end
  
rescue => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n" + "=" * 60
puts "Test Complete"
puts "Check Sidekiq queue for ProcessAppUpdateJobV3 jobs"
puts "Monitor with: tail -f log/development.log | grep V3"