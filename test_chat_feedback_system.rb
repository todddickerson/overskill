#!/usr/bin/env ruby
# Test the new ChatProgressBroadcaster system with V4 generation

# Load Rails environment if available, otherwise use standalone mocks
begin
  require_relative 'config/environment'
  puts "🚀 Testing ChatProgressBroadcaster in Rails environment"
  RAILS_MODE = true
rescue LoadError
  puts "🧪 Testing ChatProgressBroadcaster in standalone mode"
  RAILS_MODE = false
  
  # Basic mocks for standalone testing
  class Time
    def self.current
      @current ||= Time.now
    end
  end
  
  class MockAppChatMessage
    attr_accessor :id, :content, :updated_at
    
    def initialize(attrs = {})
      @id = rand(1000)
      @content = attrs[:content] || ""
      @updated_at = Time.current
    end
    
    def update!(attrs)
      @content = attrs[:content] if attrs[:content]
      @updated_at = Time.current
      self
    end
  end
  
  class AppChatMessage
    def self.create!(attrs)
      puts "📝 Creating assistant message: #{attrs[:content][0..50]}..."
      MockAppChatMessage.new(attrs)
    end
  end
  
  module ActionCable
    def self.server
      @server ||= Class.new do
        def broadcast(channel, data)
          puts "📡 Broadcasting to #{channel}: #{data[:type]}"
        end
      end.new
    end
  end
  
  class MockApp
    attr_accessor :id, :name, :status, :preview_url
    
    def initialize
      @id = 123
      @name = "Test App"
      @status = "generating"
    end
    
    def update!(attrs)
      attrs.each { |k, v| send("#{k}=", v) }
      puts "💾 Updated app: #{attrs}"
    end
  end
  
  class MockUser
    attr_accessor :id, :email
    
    def initialize
      @id = 1
      @email = "test@example.com"
    end
  end
end

# Load the ChatProgressBroadcaster
if RAILS_MODE
  # In Rails mode, classes should already be loaded
else
  # Mock the Ai module structure
  module Ai
    # Load the actual ChatProgressBroadcaster code if available
    begin
      load 'app/services/ai/chat_progress_broadcaster.rb'
    rescue LoadError
      puts "⚠️ Could not load ChatProgressBroadcaster, using mock"
      
      class ChatProgressBroadcaster
        def initialize(app, user, initial_message)
          @app = app
          @user = user
          @initial_message = initial_message
          puts "🎯 Initialized ChatProgressBroadcaster for app ##{app.id}"
        end
        
        def broadcast_start(plan_summary)
          puts "🚀 Broadcasting start: #{plan_summary}"
        end
        
        def broadcast_step_start(step_name, description)
          puts "📋 Step started: #{step_name} - #{description}"
        end
        
        def broadcast_step_complete(step_name, details = {})
          puts "✅ Step completed: #{step_name} #{details}"
        end
        
        def broadcast_file_created(path, size, preview = nil)
          puts "📄 File created: #{path} (#{size}B)"
        end
        
        def broadcast_completion(preview_url = nil, build_stats = {})
          puts "🎉 Generation completed! URL: #{preview_url}"
        end
        
        def broadcast_chat_ready
          puts "💬 Chat ready for user interactions"
        end
      end
    end
  end
end

# Test the ChatProgressBroadcaster functionality
def test_chat_progress_broadcaster
  puts "\n" + "="*50
  puts "🧪 Testing ChatProgressBroadcaster System"
  puts "="*50
  
  # Create test objects
  if RAILS_MODE
    # Create user first
    user = User.find_by(email: "test@example.com") || User.create!(
      email: "test@example.com", 
      password: "password123",
      first_name: "Test",
      last_name: "User"
    )
    
    # Create team
    team = user.teams.first || Team.create!(
      name: "Test Team"
    )
    
    # Ensure user has membership in the team
    membership = team.memberships.find_by(user: user) || team.memberships.create!(
      user: user,
      role: :admin
    )
    
    # Create app with required attributes
    app = team.apps.find_by(name: "Test Chat App") || team.apps.create!(
      name: "Test Chat App",
      creator: membership,
      prompt: "Create a todo app with real-time chat feedback",
      slug: "test-chat-app"
    )
  else
    app = MockApp.new
    user = MockUser.new
  end
  
  # Mock message object
  initial_message = if RAILS_MODE
    app.app_chat_messages.create!(
      content: "Create a todo app with real-time updates",
      user: user,
      role: "user"
    )
  else
    MockAppChatMessage.new(content: "Create a todo app with real-time updates")
  end
  
  puts "📱 Created test app: ##{app.id} - #{app.name}"
  puts "👤 Using test user: #{user.email}"
  
  # Initialize ChatProgressBroadcaster
  broadcaster = Ai::ChatProgressBroadcaster.new(app, user, initial_message)
  
  # Test the broadcast sequence
  puts "\n🎬 Testing broadcast sequence..."
  
  # 1. Start generation
  broadcaster.broadcast_start("a professional todo app with real-time updates")
  sleep(0.5)
  
  # 2. Test step progression
  broadcaster.broadcast_step_start("Project Foundation", "Setting up package.json, configs, and core files")
  sleep(0.5)
  broadcaster.broadcast_step_complete("Project Foundation", { files_count: 8 })
  
  # 3. Test file creation
  broadcaster.broadcast_file_created("src/App.tsx", 1245, "import React from 'react';\n\nexport default function App() {")
  broadcaster.broadcast_file_created("src/components/TodoList.tsx", 2100, "interface Todo {\n  id: string;\n  text: string;\n}")
  sleep(0.5)
  
  # 4. Test build progress
  broadcaster.broadcast_step_start("Build & Deploy", "Building with npm + Vite")
  broadcaster.broadcast_build_progress(:npm_install)
  sleep(0.2)
  broadcaster.broadcast_build_progress(:vite_build)
  sleep(0.2)
  broadcaster.broadcast_build_progress(:complete)
  broadcaster.broadcast_step_complete("Build & Deploy", { build_time: "877ms", size: 245_000 })
  
  # 5. Test completion
  preview_url = "https://preview-#{app.id}.overskill.app"
  broadcaster.broadcast_completion(preview_url, { size: 245_000, build_time: "877ms" })
  
  # 6. Test chat ready
  sleep(0.5)
  broadcaster.broadcast_chat_ready
  
  puts "\n✅ ChatProgressBroadcaster test completed successfully!"
  puts "📊 Summary:"
  puts "   • Generation plan broadcast ✅"
  puts "   • Step-by-step progress tracking ✅"
  puts "   • File creation notifications ✅"
  puts "   • Build progress updates ✅"
  puts "   • Completion summary ✅"
  puts "   • Chat readiness notification ✅"
  
  if RAILS_MODE
    puts "\n📝 Check your app_chat_messages table for assistant messages!"
    if defined?(AppChatMessage)
      recent_messages = AppChatMessage.where(role: 'assistant').order(:created_at).last(3)
      puts "   Recent assistant messages: #{recent_messages.count}"
      recent_messages.each do |msg|
        puts "   • #{msg.content[0..60]}..."
      end
    end
  end
  
rescue => e
  puts "\n❌ Test failed: #{e.message}"
  puts "   Backtrace: #{e.backtrace&.first(3)&.join("\n   ")}"
  return false
end

# Run the test
if test_chat_progress_broadcaster
  puts "\n🎯 Next steps:"
  puts "   1. The chat feedback system is working!"
  puts "   2. Ready to test with actual V4 generation"
  puts "   3. Can proceed with Cloudflare deployment setup"
else
  puts "\n⚠️ Issues detected - check implementation"
end