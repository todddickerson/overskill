#!/usr/bin/env ruby
# End-to-end test for V4 builder with all integrations

require_relative 'config/environment'

class V4EndToEndTest
  def self.run
    puts "\n🚀 V4 End-to-End Test Starting..."
    puts "=" * 60
    
    begin
      # 1. Create test user and app
      user = create_test_user
      app = create_test_app(user)
      
      # 2. Create initial chat message
      message = create_chat_message(app, user)
      
      # 3. Run V4 builder
      puts "\n📦 Running V4 Builder..."
      builder = Ai::AppBuilderV4.new(message)
      
      # Mock external services for testing
      mock_external_services
      
      # Execute generation
      start_time = Time.now
      builder.execute!
      end_time = Time.now
      
      puts "✅ Generation completed in #{(end_time - start_time).round(2)} seconds"
      
      # 4. Verify results
      verify_results(app)
      
      # 5. Check token tracking
      check_token_tracking(app)
      
      # 6. Verify component integration
      verify_components(app)
      
      puts "\n🎉 V4 End-to-End Test PASSED!"
      puts "=" * 60
      
    rescue => e
      puts "\n❌ Test failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end
  end
  
  private
  
  def self.create_test_user
    timestamp = Time.now.to_i
    user = User.create!(
      email: "v4_test_#{timestamp}@example.com",
      password: "SecureTestP@ssw0rd!2024"
    )
    puts "✅ Created test user: #{user.email}"
    user
  end
  
  def self.create_test_app(user)
    timestamp = Time.now.to_i
    team = Team.create!(name: "V4 Test Team #{timestamp}")
    membership = team.memberships.create!(user: user, role_ids: ['admin'])
    
    app = App.create!(
      name: "V4 Test Todo App #{timestamp}",
      slug: "v4-test-todo-#{timestamp}",
      team: team,
      creator: membership,
      prompt: "Build a todo app with authentication and file uploads",
      status: 'pending'
    )
    puts "✅ Created test app: #{app.name} (ID: #{app.id})"
    app
  end
  
  def self.create_chat_message(app, user)
    message = AppChatMessage.create!(
      app: app,
      user: user,
      role: 'user',
      content: 'Create a todo application with user authentication, file attachments, and realtime updates'
    )
    puts "✅ Created chat message"
    message
  end
  
  def self.mock_external_services
    # For now, we'll skip mocking and let it try the real services
    # or handle failures gracefully
    puts "⚠️  Running with real services (mocking disabled)"
  end
  
  def self.verify_results(app)
    app.reload
    
    # Check status
    if app.status == 'generated'
      puts "✅ App status: generated"
    else
      raise "App status is #{app.status}, expected 'generated'"
    end
    
    # Check files created
    file_count = app.app_files.count
    puts "✅ Files created: #{file_count}"
    
    # Verify core files exist
    core_files = [
      'package.json',
      'src/main.tsx',
      'src/App.tsx',
      'src/lib/supabase.ts',
      'src/lib/app-scoped-db.ts',
      'src/hooks/useAuth.ts'
    ]
    
    core_files.each do |path|
      if app.app_files.exists?(path: path)
        puts "  ✓ #{path}"
      else
        raise "Missing core file: #{path}"
      end
    end
    
    # Check for version
    version = app.app_versions.last
    if version
      puts "✅ App version created: #{version.version_number}"
    else
      raise "No app version created"
    end
  end
  
  def self.check_token_tracking(app)
    version = app.app_versions.last
    return puts "⚠️  Skipping token tracking (no Claude API call made)" unless version
    
    if version.ai_tokens_input && version.ai_tokens_input > 0
      puts "✅ Token tracking:"
      puts "  - Input tokens: #{version.ai_tokens_input}"
      puts "  - Output tokens: #{version.ai_tokens_output}"
      puts "  - Cost: #{version.ai_cost_cents} cents"
      puts "  - Model: #{version.ai_model_used}"
    else
      puts "⚠️  No tokens tracked (might be using mocked response)"
    end
  end
  
  def self.verify_components(app)
    # Check if components were detected and added
    auth_files = app.app_files.where("path LIKE '%auth%'").count
    if auth_files > 0
      puts "✅ Auth components: #{auth_files} files"
    end
    
    # Check for Supabase UI components based on request
    if app.app_files.exists?(path: 'src/components/auth/password-based-auth.tsx')
      puts "✅ Supabase auth component integrated"
    end
    
    if app.app_files.exists?(path: 'src/components/data/dropzone.tsx')
      puts "✅ Dropzone component integrated"
    end
    
    if app.app_files.exists?(path: 'src/components/realtime/realtime-chat.tsx')
      puts "✅ Realtime chat component integrated"
    end
  end
end

# Run the test
V4EndToEndTest.run