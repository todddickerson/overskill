#!/usr/bin/env ruby

# Test Live AI Message with Database Planning
# This script creates a real AI message and tests the complete flow

require_relative 'config/environment'

class LiveAiMessageTester
  def initialize
    @team = Team.first || create_test_team
    @app = @team.apps.first || create_test_app
    @user = @team.memberships.first&.user || create_test_user
  end
  
  def run_live_test
    puts "🧪 Testing Live AI Message with Database Planning"
    puts "=" * 60
    
    puts "\n📋 Test Setup:"
    puts "   Team: #{@team.name}"
    puts "   App: #{@app.name} (#{@app.framework})"
    puts "   User: #{@user.email}"
    puts "   Existing files: #{@app.app_files.count}"
    puts "   Existing tables: #{@app.app_tables.count}"
    
    # Test message that should trigger database planning
    test_message = create_test_message
    
    puts "\n💬 Created test message:"
    puts "   ID: #{test_message.id}"
    puts "   Content: '#{test_message.content[0..100]}...'"
    
    # Test the orchestrator (but don't actually execute to avoid API costs)
    test_orchestrator_initialization(test_message)
    
    # Test AI prompt building
    test_ai_prompt_building
    
    puts "\n✅ Live AI Message Test Completed!"
    puts "🎯 System ready for database-aware AI interactions"
  end
  
  private
  
  def create_test_message
    content = <<~MESSAGE
      I want to create a comprehensive blog platform with the following features:
      
      1. User Management:
         - User registration and authentication
         - User profiles with avatars
         - Admin and author roles
      
      2. Content System:
         - Blog posts with title, content, excerpt, and featured images
         - Categories and tags for organization
         - Draft/published status
      
      3. Engagement Features:
         - Comments on posts (threaded/nested)
         - Like/rating system
         - Email subscriptions
      
      4. Analytics:
         - View counts and popular posts
         - User engagement metrics
      
      Please plan the database schema and implement the initial structure.
    MESSAGE
    
    @app.app_chat_messages.create!(
      role: 'user',
      content: content,
      user: @user
    )
  end
  
  def test_orchestrator_initialization(message)
    puts "\n🔧 Testing AI Orchestrator:"
    
    orchestrator = Ai::AppUpdateOrchestrator.new(message)
    puts "   ✓ Orchestrator initialized successfully"
    puts "   ✓ App: #{orchestrator.app.name}"
    puts "   ✓ User: #{orchestrator.user.email}"
    puts "   ✓ Message ID: #{orchestrator.chat_message.id}"
    
    # Test that it can access app context
    puts "   ✓ App type: #{orchestrator.app.app_type}"
    puts "   ✓ Framework: #{orchestrator.app.framework}"
    puts "   ✓ Current files: #{orchestrator.app.app_files.count}"
    puts "   ✓ Current tables: #{orchestrator.app.app_tables.count}"
  end
  
  def test_ai_prompt_building
    puts "\n🤖 Testing AI Prompt Building:"
    
    client = Ai::OpenRouterClient.new
    
    # Test analysis prompt building
    current_files = @app.app_files.map do |file|
      { path: file.path, content: file.content, type: file.file_type }
    end
    
    app_context = {
      name: @app.name,
      type: @app.app_type,
      framework: @app.framework
    }
    
    test_request = "Add user authentication and a posts system"
    
    begin
      analysis_prompt = client.send(:build_analysis_prompt, test_request, current_files, app_context)
      puts "   ✓ Analysis prompt built successfully"
      puts "   ✓ Prompt length: #{analysis_prompt.length} characters"
      
      # Check for database integration
      database_keywords = ['DATABASE', 'SCHEMA', 'TABLE', 'SUPABASE']
      found_keywords = database_keywords.select do |keyword|
        analysis_prompt.upcase.include?(keyword)
      end
      
      puts "   ✓ Database keywords found: #{found_keywords.join(', ')}"
      puts "   ✓ Database integration: #{found_keywords.length >= 2 ? 'Strong' : 'Weak'}"
      
    rescue => e
      puts "   ❌ Error building analysis prompt: #{e.message}"
    end
  end
  
  def create_test_team
    Team.create!(
      name: "Live Test Team - #{Time.current.to_i}",
      slug: "live-test-#{Time.current.to_i}"
    )
  end
  
  def create_test_app
    @team.apps.create!(
      name: "Blog Platform Test",
      slug: "blog-test-#{Time.current.to_i}",
      prompt: "A comprehensive blog platform with user management",
      status: "generated",
      creator: @team.memberships.first,
      base_price: 0,
      app_type: "blog",
      framework: "react"
    )
  end
  
  def create_test_user
    User.create!(
      email: "live-test-#{Time.current.to_i}@example.com",
      password: "password123",
      first_name: "Live",
      last_name: "Tester"
    ).tap do |user|
      @team.memberships.create!(user: user, role: :admin)
    end
  end
end

# Run the test
if __FILE__ == $0
  begin
    tester = LiveAiMessageTester.new
    tester.run_live_test
  rescue => e
    puts "\n❌ Test failed with error:"
    puts "   #{e.class}: #{e.message}"
    puts "\n   Backtrace:"
    e.backtrace.first(10).each { |line| puts "     #{line}" }
    exit 1
  end
end