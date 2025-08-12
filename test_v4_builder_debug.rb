#!/usr/bin/env ruby
require_relative 'config/environment'

# Enable more detailed logging
Rails.logger = Logger.new(STDOUT)
Rails.logger.level = Logger::DEBUG

user = User.last
team = Team.last

if team.nil?
  team = Team.create!(name: 'Test Team')
  user = User.create!(email: 'test_v4@example.com', password: 'SecureP@ssw0rd!2024')
  team.memberships.create!(user: user, role_ids: ['admin'])
end

app = App.create!(
  name: 'Test V4 Todo App', 
  slug: "test-v4-todo-#{Time.now.to_i}", 
  team: team, 
  creator: team.memberships.first, 
  prompt: 'Create a simple todo app with add, complete, and delete tasks'
)

puts "Created app: #{app.id}"

message = AppChatMessage.create!(
  app: app,
  content: 'Create a simple todo app with add, complete, and delete tasks',
  user: user,
  role: 'user'
)

puts "Created message: #{message.id}"

begin
  builder = Ai::AppBuilderV4.new(message)
  
  # Let's trace through the builder step by step
  puts "\nCalling execute!..."
  result = builder.execute!
  
  puts "Builder completed successfully!"
  
  # Check what files were created
  puts "\nFiles created: #{app.app_files.count}"
  app.app_files.order(:path).each do |file|
    puts "  #{file.path} (#{file.content&.size || 0} chars)"
  end
  
  # Check app status
  app.reload
  puts "\nApp status: #{app.status}"
  puts "Preview URL: #{app.preview_url}" if app.preview_url.present?
  
rescue ActiveRecord::RecordInvalid => e
  puts "\n❌ Validation error: #{e.message}"
  puts "Record: #{e.record.class.name}"
  puts "Errors: #{e.record.errors.full_messages.join(', ')}"
  puts "\nBacktrace:"
  puts e.backtrace.first(10).join("\n")
rescue => e
  puts "\n❌ Builder failed: #{e.message}"
  puts "\nBacktrace:"
  puts e.backtrace.first(10).join("\n")
end