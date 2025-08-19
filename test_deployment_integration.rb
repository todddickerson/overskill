#!/usr/bin/env ruby

# Test script to verify DeployAppJob integration with app_builder_v5
# Run with: ruby test_deployment_integration.rb

require_relative 'config/environment'

def test_deployment_integration
  puts "\n🧪 Testing DeployAppJob Integration with AppBuilderV5\n"
  puts "=" * 60
  
  # Find or create test app
  team = Team.first
  unless team
    puts "❌ No team found. Please create a team first."
    exit 1
  end
  
  user = team.users.first
  unless user
    puts "❌ No user found in team. Please create a user first."
    exit 1
  end
  
  # Find the first membership for creator
  creator = team.memberships.first
  unless creator
    puts "❌ No membership found in team. Please create a membership first."
    exit 1
  end
  
  # Create a test app
  app = App.create!(
    name: "Test Deployment #{Time.current.to_i}",
    subdomain: "test-deploy-#{Time.current.to_i}",
    prompt: "Testing deployment integration",
    team: team,
    creator: creator,
    status: 'generating',
    base_price: 0
  )
  
  puts "✅ Created test app: #{app.name} (ID: #{app.id})"
  
  # Check if template files were automatically copied
  if app.app_files.any?
    puts "✅ Template files automatically copied: #{app.app_files.count} files"
  else
    # Only create test files if template files weren't copied
    app.app_files.create!(
      path: "test.html",
      content: "<html><body><h1>Test App</h1></body></html>",
      file_type: "html",
      team: team
    )
    
    app.app_files.create!(
      path: "src/TestApp.tsx",
      content: "export default function TestApp() { return <div>Test</div>; }",
      file_type: "tsx",
      team: team
    )
    
    puts "✅ Created #{app.app_files.count} test files"
  end
  
  # Test 1: Queue deployment job
  puts "\n📦 Test 1: Queueing DeployAppJob..."
  
  job = DeployAppJob.perform_later(app.id, "preview")
  puts "✅ Job queued with ID: #{job.job_id}"
  
  # Test 2: Check job was created
  sleep 1 # Give Sidekiq a moment
  
  # Check if job is in queue (if Sidekiq is running)
  if defined?(Sidekiq)
    queue = Sidekiq::Queue.new("deployment")
    job_found = queue.any? { |j| j.args.first == app.id }
    
    if job_found
      puts "✅ Job found in Sidekiq queue"
    else
      puts "⚠️  Job not in queue (may have already processed)"
    end
  end
  
  # Test 3: Execute job synchronously for testing
  puts "\n📦 Test 2: Executing job synchronously..."
  
  begin
    DeployAppJob.new.perform(app.id, "preview")
    puts "✅ Job executed successfully"
  rescue => e
    puts "❌ Job execution failed: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
  
  # Test 4: Check app status and URLs
  puts "\n📦 Test 3: Checking app updates..."
  
  app.reload
  
  if app.preview_url.present?
    puts "✅ Preview URL set: #{app.preview_url}"
  else
    puts "⚠️  Preview URL not set"
  end
  
  if app.status == 'generated'
    puts "✅ App status updated to: #{app.status}"
  else
    puts "⚠️  App status is: #{app.status} (expected: generated)"
  end
  
  # Test 5: Check version creation
  puts "\n📦 Test 4: Checking version creation..."
  
  if app.app_versions.any?
    latest_version = app.app_versions.last
    puts "✅ Version created: #{latest_version.version_number}"
    puts "   Changelog: #{latest_version.changelog}"
    puts "   Files snapshot: #{latest_version.files_snapshot.present? ? 'Present' : 'Missing'}"
  else
    puts "⚠️  No versions created"
  end
  
  # Test 6: Test app_builder_v5 integration
  puts "\n📦 Test 5: Testing AppBuilderV5 deployment method..."
  
  # Create a mock chat message
  chat_message = AppChatMessage.create!(
    app: app,
    user: user,
    team: team,
    content: "Test deployment",
    role: "user"
  )
  
  # Initialize builder
  builder = Ai::AppBuilderV5.new(chat_message)
  
  # Test the deploy_app method directly
  result = builder.send(:deploy_app)
  
  if result[:success]
    puts "✅ AppBuilderV5#deploy_app succeeded"
    puts "   Message: #{result[:message]}"
    puts "   Job ID: #{result[:job_id]}" if result[:job_id]
  else
    puts "❌ AppBuilderV5#deploy_app failed: #{result[:error]}"
  end
  
  # Summary
  puts "\n" + "=" * 60
  puts "📊 Test Summary:"
  puts "=" * 60
  
  tests_passed = 0
  tests_passed += 1 if app.preview_url.present?
  tests_passed += 1 if app.status == 'generated'
  tests_passed += 1 if app.app_versions.any?
  tests_passed += 1 if result && result[:success]
  
  puts "✅ Tests passed: #{tests_passed}/4"
  
  if tests_passed == 4
    puts "🎉 All tests passed! Deployment integration working correctly."
  else
    puts "⚠️  Some tests failed. Check the output above for details."
  end
  
  # Cleanup option
  print "\n🧹 Delete test app? (y/n): "
  if gets.chomp.downcase == 'y'
    app.destroy
    puts "✅ Test app deleted"
  else
    puts "ℹ️  Test app kept: #{app.name} (ID: #{app.id})"
  end
  
rescue => e
  puts "\n❌ Test failed with error: #{e.message}"
  puts e.backtrace.first(10).join("\n")
ensure
  puts "\n✨ Test complete!"
end

# Run the test
test_deployment_integration