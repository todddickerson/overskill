#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 60
puts "Testing V3 Unified Generation with Claude Sonnet 4"
puts "=" * 60

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Create test app with Claude Sonnet 4
app = team.apps.create!(
  creator: membership,
  name: "Todo App Claude #{Time.current.to_i}",
  slug: "todo-claude-#{SecureRandom.hex(4)}",
  prompt: "Create a todo list app with categories, priorities, due dates, and search. Include user authentication with email login. Use a modern purple theme with smooth animations.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private",
  ai_model: "claude-sonnet-4"
)

puts "\n✅ Created app ##{app.id}: #{app.name}"
puts "   Model: #{app.ai_model}"
puts "   URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"

# Create message to trigger generation
message = app.app_chat_messages.create!(
  user: membership.user,
  role: 'user',
  content: app.prompt
)

puts "\n📝 Created message ##{message.id}"
puts "\n🚀 Starting V3 Unified generation with Claude Sonnet 4..."
puts "-" * 40

# Run generation
start_time = Time.current

begin
  orchestrator = Ai::AppUpdateOrchestratorV3Unified.new(message)
  
  # Monitor in thread with timeout
  generation_thread = Thread.new do
    orchestrator.execute!
  end
  
  # Monitor for 30 seconds
  30.times do |i|
    break unless generation_thread.alive?
    
    # Check for new files
    current_files = app.app_files.reload.count
    if current_files > 0
      puts "\n📁 Files created: #{current_files}"
      app.app_files.each do |file|
        puts "  ✓ #{file.path} (#{file.content.length} bytes)"
      end
      break
    end
    
    print "."
    sleep 1
  end
  
  if generation_thread.alive?
    puts "\n⏱️ Generation still running after 30 seconds..."
    generation_thread.kill
  else
    generation_thread.join
  end
  
  duration = Time.current - start_time
  puts "\n\n✅ Completed in #{duration.round(1)} seconds"
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

# Check results
app.reload
puts "\n📊 FINAL RESULTS:"
puts "-" * 40

if app.app_files.any?
  puts "Total files: #{app.app_files.count}"
  puts "Total size: #{app.app_files.sum { |f| f.content.length }} bytes"
  
  app.app_files.order(:path).each do |file|
    puts "  ✓ #{file.path} (#{file.content.length} bytes)"
  end
  
  # Check for key files
  key_files = ['index.html', 'src/App.jsx', 'src/lib/supabase.js']
  found = app.app_files.pluck(:path) & key_files
  
  if found.length == key_files.length
    puts "\n✅ All key files created!"
  else
    missing = key_files - found
    puts "\n⚠️ Missing: #{missing.join(', ')}"
  end
else
  puts "❌ No files created"
end

puts "\n" + "=" * 60
puts "View app at: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "=" * 60