#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 60
puts "Testing V3 Optimized with Forced Tool Usage"
puts "=" * 60

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Create a comprehensive test app
app = team.apps.create!(
  creator: membership,
  name: "Todo Master Pro #{Time.current.to_i}",
  slug: "todo-master-#{SecureRandom.hex(6)}",
  prompt: "Create a professional todo application with user authentication (email + Google/GitHub OAuth), task management with categories and priorities, due dates, search and filtering, and a beautiful modern UI with dark mode. Use React Router for navigation and Supabase for data persistence.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "\n✅ Created app ##{app.id}: #{app.name}"
puts "   URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "   Preview: https://preview-#{app.id}.overskill.app"

# Create a chat message to trigger generation
message = app.app_chat_messages.create!(
  user: membership.user,
  role: 'user',
  content: app.prompt
)

puts "\n📝 Created message ##{message.id}"
puts "\n🚀 Starting V3 Optimized generation..."
puts "-" * 40

# Execute orchestrator directly to see output
begin
  orchestrator = Ai::AppUpdateOrchestratorV3Optimized.new(message)
  
  # Track start time
  start_time = Time.current
  
  # Execute
  orchestrator.execute!
  
  # Calculate duration
  duration = Time.current - start_time
  
  puts "\n✅ Generation completed in #{duration.round(1)} seconds"
  
rescue => e
  puts "\n❌ ERROR during generation:"
  puts "   #{e.message}"
  puts e.backtrace.first(5).map { |line| "     #{line}" }.join("\n")
end

# Check what files were created
puts "\n📁 FILES CREATED:"
puts "-" * 40

app.reload
if app.app_files.any?
  app.app_files.order(:path).each do |file|
    puts "  ✓ #{file.path} (#{file.content.length} bytes)"
  end
  
  puts "\n📊 SUMMARY:"
  puts "  Total files: #{app.app_files.count}"
  puts "  Total size: #{app.app_files.sum { |f| f.content.length }} bytes"
  
  # Check for expected files
  expected_files = [
    'index.html',
    'src/App.jsx',
    'src/lib/supabase.js',
    'src/pages/auth/Login.jsx',
    'src/pages/auth/SignUp.jsx',
    'src/pages/Dashboard.jsx'
  ]
  
  created_paths = app.app_files.pluck(:path)
  missing_files = expected_files - created_paths
  
  if missing_files.any?
    puts "\n⚠️  MISSING EXPECTED FILES:"
    missing_files.each { |f| puts "    - #{f}" }
  else
    puts "\n✅ All expected core files were created!"
  end
  
  # Show a sample of the first file's content
  first_file = app.app_files.find_by(path: 'index.html') || app.app_files.first
  if first_file
    puts "\n📄 SAMPLE CONTENT (#{first_file.path}):"
    puts "-" * 40
    puts first_file.content[0..500]
    puts "... (truncated)"
  end
else
  puts "  ❌ NO FILES CREATED!"
  puts "\n  This indicates the AI did not call the create_file tool."
  puts "  Check the logs for more details."
end

# Check recent version
if app.app_versions.any?
  version = app.app_versions.last
  puts "\n📌 VERSION INFO:"
  puts "  Version: #{version.version_number}"
  files_snapshot = version.files_snapshot ? JSON.parse(version.files_snapshot) : nil
  if files_snapshot.is_a?(Hash)
    puts "  Files snapshot: #{files_snapshot.keys.join(', ')}"
  elsif files_snapshot.is_a?(Array)
    puts "  Files snapshot: #{files_snapshot.join(', ')}"
  else
    puts "  Files snapshot: None"
  end
end

puts "\n" + "=" * 60
puts "Test completed. Check the app in the browser:"
puts "https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "=" * 60