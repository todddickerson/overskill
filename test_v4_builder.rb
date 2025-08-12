#!/usr/bin/env ruby
require_relative 'config/environment'

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
  
rescue => e
  puts "Builder failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end