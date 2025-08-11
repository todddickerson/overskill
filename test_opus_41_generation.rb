#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 80
puts "Testing V3 Unified Generation with Claude Opus 4.1"
puts "=" * 80
puts "\nClaude Opus 4.1 Features:"
puts "  • Most capable model for complex, long-running tasks"
puts "  • Extended thinking with tool use"
puts "  • 200k token context window"
puts "  • Released August 5, 2025"
puts "-" * 80

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Create complex app to test Opus 4.1 capabilities
app = team.apps.create!(
  creator: membership,
  name: "SaaS Platform Opus #{Time.current.to_i}",
  slug: "saas-opus-#{SecureRandom.hex(4)}",
  prompt: "Create a comprehensive SaaS platform with the following features:
1. Multi-tenant user authentication with email, Google, and GitHub OAuth
2. User dashboard with analytics charts showing usage metrics, revenue, and growth
3. Subscription management with Stripe integration for billing
4. Admin panel for user management and system settings
5. Project management features with kanban boards and task assignments
6. Real-time notifications using websockets
7. File upload and management system
8. API documentation page
9. Beautiful landing page with pricing tiers
10. Dark mode support throughout
Use a modern purple and blue gradient theme with smooth animations. Implement proper error handling, loading states, and empty states. Include comprehensive Supabase integration for all data persistence.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private",
  ai_model: "claude-opus-4.1"
)

puts "\n✅ Created app ##{app.id}: #{app.name}"
puts "   Model: #{app.ai_model}"
puts "   Prompt length: #{app.prompt.length} characters"
puts "   URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"

# Create message to trigger generation
message = app.app_chat_messages.create!(
  user: membership.user,
  role: 'user',
  content: app.prompt
)

puts "\n📝 Created message ##{message.id}"
puts "\n🚀 Starting V3 Unified generation with Claude Opus 4.1..."
puts "   This complex generation may take 1-2 minutes..."
puts "-" * 80

# Run generation with monitoring
start_time = Time.current
last_file_count = 0
files_created_list = []

begin
  # Start orchestrator
  orchestrator = Ai::AppUpdateOrchestratorV3Unified.new(message)
  
  puts "✓ Orchestrator initialized"
  puts "  Model: #{orchestrator.instance_variable_get(:@model)}"
  puts "  Provider: #{orchestrator.instance_variable_get(:@provider)}"
  puts "  Extended thinking: #{orchestrator.instance_variable_get(:@supports_extended_thinking)}"
  
  # Run in thread with monitoring
  generation_thread = Thread.new do
    orchestrator.execute!
  end
  
  puts "\n📊 Monitoring file generation:"
  puts "-" * 40
  
  # Monitor for up to 120 seconds (2 minutes for complex generation)
  120.times do |i|
    break unless generation_thread.alive?
    
    # Check for new files every 2 seconds
    if i % 2 == 0
      app.app_files.reload
      current_count = app.app_files.count
      
      if current_count > last_file_count
        # New files created
        new_files = app.app_files.order(:created_at).last(current_count - last_file_count)
        new_files.each do |file|
          timestamp = Time.current - start_time
          puts "[#{timestamp.round(1)}s] ✓ Created: #{file.path} (#{file.content.length} bytes)"
          files_created_list << file.path
        end
        last_file_count = current_count
      end
    end
    
    # Print progress dot
    print "." if last_file_count == 0
    sleep 1
  end
  
  if generation_thread.alive?
    puts "\n⏱️ Generation still running after 2 minutes..."
    puts "Waiting 30 more seconds..."
    30.times do
      break unless generation_thread.alive?
      print "."
      sleep 1
    end
    
    if generation_thread.alive?
      puts "\nForce stopping after 2.5 minutes"
      generation_thread.kill
    end
  else
    generation_thread.join
  end
  
  duration = Time.current - start_time
  puts "\n\n✅ Generation phase completed in #{duration.round(1)} seconds"
  
rescue => e
  puts "\n❌ ERROR during generation: #{e.message}"
  puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
end

# Final analysis
app.reload
puts "\n" + "=" * 80
puts "📊 FINAL ANALYSIS - Claude Opus 4.1 Generation"
puts "=" * 80

if app.app_files.any?
  total_size = app.app_files.sum { |f| f.content.length }
  
  puts "\n📁 FILES CREATED:"
  puts "  Total files: #{app.app_files.count}"
  puts "  Total size: #{total_size} bytes (#{(total_size / 1024.0).round(1)} KB)"
  
  # Group files by type
  files_by_type = {}
  app.app_files.each do |file|
    dir = File.dirname(file.path)
    dir = 'root' if dir == '.'
    files_by_type[dir] ||= []
    files_by_type[dir] << file
  end
  
  puts "\n📂 FILE STRUCTURE:"
  files_by_type.sort.each do |dir, files|
    puts "  #{dir}/"
    files.each do |file|
      filename = File.basename(file.path)
      puts "    ├── #{filename} (#{file.content.length} bytes)"
    end
  end
  
  # Check for expected complex app files
  expected_patterns = {
    'Authentication' => ['Login', 'SignUp', 'OAuth'],
    'Dashboard' => ['Dashboard', 'Analytics', 'Charts'],
    'Subscription' => ['Billing', 'Stripe', 'Pricing'],
    'Admin' => ['Admin', 'UserManagement'],
    'Project Management' => ['Kanban', 'Task', 'Project'],
    'Landing' => ['Landing', 'Home', 'Hero'],
    'API' => ['api', 'docs'],
    'Supabase' => ['supabase']
  }
  
  puts "\n🔍 FEATURE COVERAGE:"
  expected_patterns.each do |feature, patterns|
    found = app.app_files.any? do |file|
      patterns.any? { |p| file.path.include?(p) || file.content.include?(p) }
    end
    status = found ? "✅" : "❌"
    puts "  #{status} #{feature}"
  end
  
  # Sample content from main file
  main_file = app.app_files.find_by(path: 'src/App.jsx') || app.app_files.find_by(path: 'index.html')
  if main_file
    puts "\n📄 SAMPLE FROM #{main_file.path}:"
    puts "-" * 40
    puts main_file.content[0..500]
    puts "... (showing first 500 characters)"
  end
  
  # Performance metrics
  if app.app_files.count >= 15
    puts "\n🎉 EXCELLENT! Claude Opus 4.1 generated a comprehensive app with #{app.app_files.count} files!"
  elsif app.app_files.count >= 10
    puts "\n✅ GOOD! Generated #{app.app_files.count} files - substantial application"
  elsif app.app_files.count >= 5
    puts "\n⚠️ MODERATE: Generated #{app.app_files.count} files - expected more for complex prompt"
  else
    puts "\n❌ MINIMAL: Only #{app.app_files.count} files - Opus 4.1 should generate more"
  end
  
else
  puts "\n❌ ERROR: No files were created!"
  puts "This indicates a problem with the generation process."
end

# Check version status
if app.app_versions.any?
  version = app.app_versions.last
  puts "\n📌 VERSION INFO:"
  puts "  Version: #{version.version_number}"
  puts "  Status: #{version.status}"
  puts "  Error: #{version.error_message}" if version.error_message.present?
end

puts "\n" + "=" * 80
puts "🔗 View the generated app at:"
puts "https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "=" * 80