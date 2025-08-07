#!/usr/bin/env ruby

# Full Orchestrator Test
puts "🎭 Testing Full App Update Orchestrator"
puts "Run with: rails runner test_orchestrator_full.rb"

if defined?(Rails)
  puts "✅ Rails environment loaded"
  
  begin
    # Create a test app and message
    puts "\n📝 Creating test data..."
    
    # Find or create a test team
    team = Team.first || Team.create!(
      name: "Test Team",
      email: "test@example.com"
    )
    puts "✅ Team: #{team.name}"
    
    # Find or create a test user
    user = User.first || User.create!(
      email: "test@example.com",
      team: team
    )
    puts "✅ User: #{user.email}"
    
    # Create a test app
    app = App.create!(
      name: "Test Todo App",
      app_type: "productivity",
      framework: "react",
      team: team,
      user: user
    )
    puts "✅ App: #{app.name} (ID: #{app.id})"
    
    # Create initial files
    app.app_files.create!([
      {
        path: "index.html",
        content: "<!DOCTYPE html><html><head><title>Test App</title></head><body><div id='root'></div></body></html>",
        file_type: "html",
        team: team
      },
      {
        path: "app.js", 
        content: "console.log('Hello World');",
        file_type: "js",
        team: team
      }
    ])
    puts "✅ Created #{app.app_files.count} initial files"
    
    # Create a test message
    message = app.app_chat_messages.create!(
      role: "user",
      content: "Add a todo list with the ability to add, remove, and check off tasks. Use modern React with hooks.",
      user: user,
      team: team
    )
    puts "✅ Test message: #{message.content[0..50]}..."
    
    # Test the orchestrator
    puts "\n🎭 Testing AppUpdateOrchestratorV2..."
    
    orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
    puts "✅ Orchestrator initialized"
    
    # Test individual components
    puts "\n🔍 Testing orchestrator methods..."
    
    # Test get_cached_or_load_files
    files = orchestrator.send(:get_cached_or_load_files)
    puts "✅ File loading: #{files.size} files"
    
    # Test get_cached_or_load_env_vars
    env_vars = orchestrator.send(:get_cached_or_load_env_vars)
    puts "✅ Env vars loading: #{env_vars.size} variables"
    
    # Test build_execution_tools
    tools = orchestrator.send(:build_execution_tools)
    puts "✅ Tool building: #{tools.size} tools defined"
    
    puts "\n🚀 Running full orchestrator execution..."
    puts "⚠️  This may take several minutes and use API credits"
    puts "Press Ctrl+C to cancel in the next 5 seconds..."
    
    sleep(5)
    
    start_time = Time.now
    result = orchestrator.execute!
    duration = Time.now - start_time
    
    puts "✅ Orchestrator execution completed"
    puts "  Duration: #{duration.round(2)} seconds"
    
    # Check results
    app.reload
    puts "  Final file count: #{app.app_files.count}"
    puts "  Chat messages: #{app.app_chat_messages.count}"
    
    # Show some file content
    app.app_files.limit(3).each do |file|
      puts "  📄 #{file.path}: #{file.content.length} chars"
    end
    
    # Clean up
    puts "\n🧹 Cleaning up test data..."
    app.app_files.destroy_all
    app.app_chat_messages.destroy_all
    app.destroy!
    puts "✅ Test data cleaned up"
    
  rescue => e
    puts "❌ Test failed: #{e.message}"
    puts "  Backtrace:"
    e.backtrace.first(10).each { |line| puts "    #{line}" }
    
    # Clean up on error
    begin
      app&.destroy! if defined?(app) && app&.persisted?
    rescue => cleanup_error
      puts "⚠️  Cleanup error: #{cleanup_error.message}"
    end
  end
  
else
  puts "❌ Rails environment not loaded"
  puts "Run with: rails runner test_orchestrator_full.rb"
end