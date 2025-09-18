#!/usr/bin/env rails runner

# End-to-end test for V4 Enhanced with all fixes applied
require "timeout"

puts "=" * 60
puts "V4 Enhanced End-to-End Test"
puts "=" * 60

# Find existing user and team
user = User.first
team = user&.teams&.first
membership = team&.memberships&.where(user: user)&.first

unless user && team && membership
  puts "❌ Missing required data. Please ensure database has users/teams."
  exit 1
end

puts "Using user: #{user.email}"
puts "Using team: #{team.name}"

# Create a test app
app = App.create!(
  name: "V4 Enhanced E2E Test #{Time.current.strftime("%H%M%S")}",
  team: team,
  creator: membership,
  prompt: "Create a modern counter app with increment and decrement buttons",
  status: "generating",
  app_type: "tool"
)

puts "\n✅ Created app: #{app.name} (ID: #{app.id})"

# Create user message
user_message = AppChatMessage.create!(
  app: app,
  user: user,
  role: "user",
  content: "Create a modern counter app with increment and decrement buttons. Use React with TypeScript."
)

puts "✅ Created user message: #{user_message.id}"

# Test V4 Enhanced Orchestrator
puts "\n" + "=" * 40
puts "Testing V4 Enhanced Orchestrator..."
puts "=" * 40

begin
  # Load the orchestrator
  require_relative "app/services/ai/app_builder_v4_enhanced"

  # Initialize orchestrator with the chat message
  orchestrator = Ai::AppBuilderV4Enhanced.new(user_message)

  puts "\n📋 Starting 6-phase generation process..."

  # Track start time
  Time.current

  # Execute with timeout
  Timeout.timeout(120) do
    result = orchestrator.execute!

    if result[:success]
      puts "\n✅ V4 Enhanced Orchestrator completed successfully!"
      puts "   Files generated: #{result[:files_generated]}"
      puts "   Build time: #{result[:build_time]}s"
      puts "   Token usage: #{result[:token_usage]}"

      # Check if app was deployed
      if result[:deployed]
        puts "\n🚀 App deployed successfully!"
        puts "   Preview URL: #{result[:preview_url]}"
        puts "   Worker status: #{result[:worker_status]}"
      else
        puts "\n⚠️  App generated but not deployed"
      end
    else
      puts "\n❌ Orchestrator failed: #{result[:error]}"
      puts "   Error details: #{result[:error_details]}"
    end
  end
rescue Timeout::Error
  puts "\n⚠️  Orchestrator timed out after 120 seconds"
  puts "This might indicate an issue with AI response times"
rescue => e
  puts "\n❌ Orchestrator error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Check generated files
puts "\n" + "=" * 40
puts "Checking Generated Files..."
puts "=" * 40

app.reload
if app.app_files.any?
  puts "\n📁 Generated #{app.app_files.count} files:"
  app.app_files.order(:path).limit(10).each do |file|
    size = file.content.bytesize
    puts "   • #{file.path} (#{size} bytes)"
  end

  # Check for key files
  key_files = ["index.html", "src/App.tsx", "package.json", "vite.config.ts"]
  key_files.each do |path|
    if app.app_files.exists?(path: path)
      puts "   ✅ #{path} exists"
    else
      puts "   ⚠️  #{path} missing"
    end
  end
else
  puts "⚠️  No files generated"
end

# Check app versions
puts "\n" + "=" * 40
puts "Checking App Versions..."
puts "=" * 40

if app.app_versions.any?
  latest_version = app.app_versions.order(created_at: :desc).first
  puts "\n📦 Latest version: #{latest_version.version_number || "v1"}"
  puts "   Status: #{latest_version.status}"
  puts "   Files changed: #{latest_version.app_version_files.count}"
  puts "   Created: #{latest_version.created_at}"

  if latest_version.deployed
    puts "   ✅ Deployed successfully"
  else
    puts "   ⚠️  Not deployed"
  end
else
  puts "⚠️  No versions created"
end

# Check chat messages
puts "\n" + "=" * 40
puts "Checking Chat Messages..."
puts "=" * 40

assistant_messages = app.app_chat_messages.where(role: "assistant").order(:created_at)
if assistant_messages.any?
  puts "\n💬 Found #{assistant_messages.count} assistant messages:"
  assistant_messages.each_with_index do |msg, i|
    preview = msg.content.lines.first(2).join.strip[0..100]
    puts "   #{i + 1}. #{preview}..."
  end
else
  puts "⚠️  No assistant messages found"
end

# Summary
puts "\n" + "=" * 60
puts "Test Summary"
puts "=" * 60

success_count = 0
total_checks = 5

# Check 1: App created
if app.persisted?
  puts "✅ App created successfully"
  success_count += 1
else
  puts "❌ App creation failed"
end

# Check 2: Files generated
if app.app_files.count > 0
  puts "✅ Files generated (#{app.app_files.count} files)"
  success_count += 1
else
  puts "❌ No files generated"
end

# Check 3: Assistant messages created
if assistant_messages.count > 0
  puts "✅ Chat messages created (#{assistant_messages.count} messages)"
  success_count += 1
else
  puts "❌ No chat messages created"
end

# Check 4: Version created
if app.app_versions.count > 0
  puts "✅ Version created"
  success_count += 1
else
  puts "❌ No version created"
end

# Check 5: Worker deployment
latest_version = app.app_versions.order(created_at: :desc).first
if latest_version&.deployed
  puts "✅ Worker deployed"
  success_count += 1
else
  puts "⚠️  Worker not deployed (may still be processing)"
end

puts "\n📊 Result: #{success_count}/#{total_checks} checks passed"

if success_count == total_checks
  puts "🎉 All tests passed! V4 Enhanced is working correctly."
  puts "\n🔗 Preview your app at: https://preview-#{app.id}.overskill.app"
elsif success_count >= 3
  puts "✅ Core functionality working. Some features may still be processing."
  puts "\n🔗 Check app status at: https://preview-#{app.id}.overskill.app"
else
  puts "⚠️  V4 Enhanced needs attention. Check logs for details."
end

puts "\n" + "=" * 60
puts "Test completed at #{Time.current.strftime("%H:%M:%S")}"
puts "=" * 60
