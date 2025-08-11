#!/usr/bin/env ruby
require_relative 'config/environment'

puts "=" * 80
puts "Testing V3 Unified Generation with Claude 3 Opus"
puts "=" * 80
puts "\nClaude 3 Opus - Currently available premium model"
puts "  • Best for complex tasks and detailed generation"
puts "  • 200k token context window"
puts "  • Comprehensive app structure capabilities"
puts "-" * 80

# Get team 8
team = Team.find(8)
membership = team.memberships.first

unless membership
  puts "ERROR: No membership found for team 8"
  exit 1
end

# Create complex app to test Opus capabilities
app = team.apps.create!(
  creator: membership,
  name: "Enterprise Dashboard #{Time.current.to_i}",
  slug: "enterprise-#{SecureRandom.hex(4)}",
  prompt: "Create a comprehensive enterprise dashboard application with:
1. Multi-level user authentication (admin, manager, employee roles)
2. Interactive data visualization with multiple chart types (line, bar, pie, scatter)
3. Real-time metrics dashboard with KPIs and performance indicators
4. User management system with CRUD operations
5. File upload and document management
6. Notification system with email integration
7. Search and filtering across all data
8. Export functionality (CSV, PDF)
9. Responsive design with mobile support
10. Dark mode toggle
Use a professional blue and gray theme. Include proper error handling, loading states, and comprehensive Supabase integration.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private",
  ai_model: "claude-3-opus-20240229"  # Using actual Claude 3 Opus model ID
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
puts "\n🚀 Starting V3 Unified generation with Claude 3 Opus..."
puts "   This may take 30-60 seconds for complex generation..."
puts "-" * 80

# Run generation with monitoring
start_time = Time.current
last_file_count = 0

begin
  # Start orchestrator
  orchestrator = Ai::AppUpdateOrchestratorV3Unified.new(message)
  
  puts "✓ Orchestrator initialized"
  puts "  Selected model: #{orchestrator.instance_variable_get(:@model)}"
  puts "  Provider: #{orchestrator.instance_variable_get(:@provider)}"
  config = orchestrator.instance_variable_get(:@model_config)
  puts "  Max tokens: #{config[:max_tokens]}"
  puts "  Context window: #{config[:context_window]}"
  
  # Run in thread with monitoring
  generation_thread = Thread.new do
    orchestrator.execute!
  end
  
  puts "\n📊 Monitoring file generation:"
  puts "-" * 40
  
  # Monitor for up to 90 seconds
  90.times do |i|
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
        end
        last_file_count = current_count
      end
    end
    
    # Show progress
    if last_file_count == 0
      print "." if i % 5 == 0
    end
    sleep 1
  end
  
  if generation_thread.alive?
    puts "\n⏱️ Still processing... waiting 30 more seconds"
    30.times do
      break unless generation_thread.alive?
      print "."
      sleep 1
    end
    
    if generation_thread.alive?
      puts "\nStopping after 2 minutes"
      generation_thread.kill
    end
  else
    generation_thread.join
  end
  
  duration = Time.current - start_time
  puts "\n\n✅ Generation completed in #{duration.round(1)} seconds"
  
rescue => e
  puts "\n❌ ERROR: #{e.message}"
  puts e.backtrace.first(5).map { |line| "  #{line}" }.join("\n")
end

# Final analysis
app.reload
puts "\n" + "=" * 80
puts "📊 ANALYSIS - Claude 3 Opus Generation"
puts "=" * 80

if app.app_files.any?
  total_size = app.app_files.sum { |f| f.content.length }
  
  puts "\n📁 FILES SUMMARY:"
  puts "  Total files: #{app.app_files.count}"
  puts "  Total size: #{(total_size / 1024.0).round(1)} KB"
  
  puts "\n📂 FILES CREATED:"
  app.app_files.order(:path).each do |file|
    puts "  ✓ #{file.path} (#{file.content.length} bytes)"
  end
  
  # Check for key features
  features = {
    'Authentication' => app.app_files.any? { |f| f.path.downcase.include?('auth') || f.path.downcase.include?('login') },
    'Dashboard' => app.app_files.any? { |f| f.path.downcase.include?('dashboard') },
    'Charts/Visualization' => app.app_files.any? { |f| f.content.include?('chart') || f.content.include?('Chart') },
    'Supabase Integration' => app.app_files.any? { |f| f.path.include?('supabase') || f.content.include?('supabase') },
    'React Router' => app.app_files.any? { |f| f.content.include?('Router') || f.content.include?('Route') }
  }
  
  puts "\n🔍 FEATURE CHECK:"
  features.each do |feature, found|
    status = found ? "✅" : "❌"
    puts "  #{status} #{feature}"
  end
  
  # Quality assessment
  if app.app_files.count >= 10
    puts "\n🎉 EXCELLENT! Claude 3 Opus generated #{app.app_files.count} files!"
  elsif app.app_files.count >= 5
    puts "\n✅ GOOD! Generated #{app.app_files.count} files"
  else
    puts "\n⚠️ MINIMAL: Only #{app.app_files.count} files generated"
  end
  
else
  puts "\n❌ ERROR: No files were created!"
end

# Check version
if app.app_versions.any?
  version = app.app_versions.last
  puts "\n📌 VERSION: #{version.version_number} (#{version.status})"
end

puts "\n" + "=" * 80
puts "🔗 View app: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "=" * 80