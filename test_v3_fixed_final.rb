#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 60
puts "FINAL TEST: V3 Optimized with All GPT-5 Fixes"
puts "=" * 60
puts "\nThis test includes fixes for:"
puts "  ✓ max_completion_tokens instead of max_tokens"
puts "  ✓ No temperature parameter (GPT-5 default only)"
puts "  ✓ No cache parameter (not supported)"
puts "  ✓ Enhanced prompts for tool usage"
puts "  ✓ Improved fallback file parsing"
puts "-" * 60

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Create a test app with clear requirements
app = team.apps.create!(
  creator: membership,
  name: "Task Tracker Pro #{Time.current.to_i}",
  slug: "task-tracker-#{SecureRandom.hex(6)}",
  prompt: "Create a task management app with: user login (email + OAuth), task CRUD with categories, priority levels, due dates, search/filter, and modern UI. Use React Router for navigation and Supabase for data storage.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "\n✅ Created app ##{app.id}: #{app.name}"
puts "   Team: #{team.name} (ID: #{team.id})"
puts "   URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "   Preview: https://preview-#{app.id}.overskill.app"

# Create a chat message to trigger generation
message = app.app_chat_messages.create!(
  user: membership.user,
  role: 'user',
  content: app.prompt
)

puts "\n📝 Created message ##{message.id}"
puts "\n🚀 Starting V3 Optimized generation with GPT-5..."
puts "-" * 40

# Track generation
start_time = Time.current
timeout_seconds = 120
check_interval = 5
files_created = 0

begin
  # Start generation in background
  orchestrator = Ai::AppUpdateOrchestratorV3Optimized.new(message)
  
  # Run in a thread with timeout
  generation_thread = Thread.new do
    orchestrator.execute!
  end
  
  # Monitor progress
  elapsed = 0
  while elapsed < timeout_seconds && generation_thread.alive?
    sleep(check_interval)
    elapsed += check_interval
    
    # Check current file count
    current_count = app.app_files.count
    if current_count > files_created
      new_files = app.app_files.order(:created_at).last(current_count - files_created)
      new_files.each do |file|
        puts "  📄 Created: #{file.path} (#{file.content.length} bytes)"
      end
      files_created = current_count
    end
    
    print "." if files_created == 0
  end
  
  # Ensure thread completes or kill it
  if generation_thread.alive?
    puts "\n⏱️  Generation taking longer than expected..."
    generation_thread.kill
  else
    generation_thread.join
  end
  
  duration = Time.current - start_time
  puts "\n\n✅ Generation completed in #{duration.round(1)} seconds"
  
rescue => e
  puts "\n❌ ERROR during generation:"
  puts "   #{e.message}"
  puts e.backtrace.first(3).map { |line| "     #{line}" }.join("\n")
end

# Final check of created files
puts "\n📁 FINAL FILE COUNT:"
puts "-" * 40

app.reload
if app.app_files.any?
  total_size = 0
  app.app_files.order(:path).each do |file|
    puts "  ✓ #{file.path} (#{file.content.length} bytes)"
    total_size += file.content.length
  end
  
  puts "\n📊 SUMMARY:"
  puts "  Total files: #{app.app_files.count}"
  puts "  Total size: #{total_size} bytes (#{(total_size / 1024.0).round(1)} KB)"
  
  # Check for critical files
  critical_files = [
    'index.html',
    'src/App.jsx',
    'src/lib/supabase.js',
    'src/pages/auth/Login.jsx',
    'src/pages/Dashboard.jsx'
  ]
  
  created_paths = app.app_files.pluck(:path)
  found_critical = critical_files & created_paths
  missing_critical = critical_files - created_paths
  
  if found_critical.any?
    puts "\n✅ Critical files created:"
    found_critical.each { |f| puts "    ✓ #{f}" }
  end
  
  if missing_critical.any?
    puts "\n⚠️  Missing critical files:"
    missing_critical.each { |f| puts "    ✗ #{f}" }
  end
  
  # Show sample of first HTML file
  html_file = app.app_files.find_by(path: 'index.html')
  if html_file
    puts "\n📄 SAMPLE - index.html (first 400 chars):"
    puts "-" * 40
    puts html_file.content[0..400]
    puts "..." if html_file.content.length > 400
  end
  
  # Check if comprehensive app was built
  if app.app_files.count >= 5
    puts "\n🎉 SUCCESS! Comprehensive app generated with #{app.app_files.count} files!"
  elsif app.app_files.count >= 3
    puts "\n⚠️  Partial success - #{app.app_files.count} files created (expected more)"
  else
    puts "\n❌ Minimal generation - only #{app.app_files.count} files created"
  end
else
  puts "  ❌ NO FILES CREATED!"
  puts "\n  This indicates the AI did not successfully call the create_file tool."
end

# Check version info
if app.app_versions.any?
  version = app.app_versions.last
  puts "\n📌 VERSION: #{version.version_number}"
  if version.status == 'completed'
    puts "   Status: ✅ Completed"
  else
    puts "   Status: ⚠️  #{version.status}"
  end
end

puts "\n" + "=" * 60
puts "Test completed. View the app at:"
puts "https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "=" * 60