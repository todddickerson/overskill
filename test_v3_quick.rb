#!/usr/bin/env ruby
# Quick test of optimized V3 orchestrator

ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_V3_OPTIMIZED'] = 'true'
ENV['USE_STREAMING'] = 'false'
ENV['VERBOSE_AI_LOGGING'] = 'true'

require_relative 'config/environment'

puts "="*60
puts "Quick V3 Optimized Test"
puts "="*60

team = Team.first
abort("No team found!") unless team

app = App.create!(
  team: team,
  name: "Quick Test #{Time.now.to_i}",
  slug: "quick-#{Time.now.to_i}",
  prompt: "Create a simple button that says 'Click me' and shows an alert",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "Testing app ##{app.id}..."
start = Time.now

begin
  ProcessAppUpdateJobV3.new.perform(message)
  
  duration = Time.now - start
  app.reload
  
  puts "\n✅ Completed in #{duration.round(1)}s"
  puts "Files created: #{app.app_files.count}"
  
  if app.app_files.any?
    app.app_files.each do |file|
      puts "  - #{file.path}"
    end
  else
    puts "  ⚠️ No files created"
  end
  
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "="*60