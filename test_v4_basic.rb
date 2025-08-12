#!/usr/bin/env ruby

# Test basic V4 services
require_relative './config/environment'

begin
  puts 'Testing V4 services...'
  
  # Find or create a test app
  team = Team.first
  if team.nil?
    puts 'ERROR: No teams found. Need a team to create test app.'
    exit 1
  end
  
  # Get a creator (team member)
  creator = team.memberships.first
  if creator.nil?
    puts 'ERROR: No team memberships found.'
    exit 1
  end

  app = team.apps.find_by(name: 'V4 Test App') || 
        team.apps.create!(
          name: 'V4 Test App', 
          description: 'Testing V4 orchestrator',
          prompt: 'Build a simple todo app',
          creator: creator,
          base_price: 0
        )
  
  puts "Found/created app: #{app.id}"
  
  # Test SharedTemplateService
  template_service = Ai::SharedTemplateService.new(app)
  puts "Template service initialized: #{template_service.class}"
  
  # Test builder initialization
  user = team.users.first
  if user.nil?
    puts 'ERROR: No users found in team.'
    exit 1
  end
  
  message = app.app_chat_messages.create!(
    role: 'user', 
    content: 'Build a simple todo app', 
    user: user
  )
  
  builder = Ai::AppBuilderV4.new(message)
  puts "Builder initialized: #{builder.class}"
  
  puts 'Basic V4 services working!'
  
rescue => e
  puts "ERROR: #{e.class}: #{e.message}"
  puts e.backtrace.first(3).join("\n")
  exit 1
end