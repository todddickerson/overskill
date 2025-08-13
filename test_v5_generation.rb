#!/usr/bin/env ruby
# Test script for V5 Agent Loop Generation

require_relative 'config/environment'

def test_v5_generation
  puts "\n" + "="*80
  puts "V5 AGENT LOOP TEST - TODO APP GENERATION"
  puts "="*80
  
  # 1. Setup test user and team
  puts "\n📋 Setting up test data..."
  
  user = User.find_by(email: 'test@overskill.app') || User.create!(
    email: 'test@overskill.app',
    password: 'password123',
    password_confirmation: 'password123',
    first_name: 'Test',
    last_name: 'User',
    time_zone: 'America/Los_Angeles'
  )
  puts "✅ User: #{user.email}"
  
  team = user.teams.first || user.teams.create!(name: "Test Team")
  puts "✅ Team: #{team.name}"
  
  membership = team.memberships.find_by(user: user) || 
               team.memberships.create!(user: user, roles: ['admin'])
  puts "✅ Membership: #{membership.id}"
  
  # 2. Create chat message
  puts "\n💬 Creating chat message..."
  
  message = AppChatMessage.create!(
    user: user,
    role: 'user',
    content: 'Create a simple todo app with the ability to add tasks, mark them as complete, and delete them. Use modern React with TypeScript.'
  )
  puts "✅ Message created: #{message.id}"
  puts "   Content: #{message.content[0..100]}..."
  
  # 3. Test V5 Builder directly (not through job)
  puts "\n🚀 Starting V5 Builder..."
  puts "   Using Claude Opus 4.1 with prompt caching"
  puts "   Template: overskill_20250728"
  
  begin
    builder = Ai::AppBuilderV5.new(message)
    puts "✅ Builder initialized"
    
    # Check that assistant message was created
    assistant_msg = AppChatMessage.where(role: 'assistant').last
    puts "✅ Assistant message created: #{assistant_msg.id}" if assistant_msg
    
    # Monitor in separate thread for real-time updates
    monitor_thread = Thread.new do
      loop do
        assistant_msg.reload
        
        if assistant_msg.thinking_status.present?
          puts "   🧠 Thinking: #{assistant_msg.thinking_status}"
        end
        
        if assistant_msg.loop_messages.any?
          last_msg = assistant_msg.loop_messages.last
          puts "   📝 Loop message: #{last_msg['content'][0..100]}..." if last_msg['content']
        end
        
        if assistant_msg.tool_calls.any?
          last_tool = assistant_msg.tool_calls.last
          puts "   🔧 Tool: #{last_tool['name']} [#{last_tool['status']}]"
        end
        
        break if assistant_msg.status == 'completed' || assistant_msg.status == 'failed'
        sleep 1
      end
    end
    
    # Execute the builder
    puts "\n⚙️ Executing agent loop..."
    builder.execute!
    
    # Wait for monitor to finish
    monitor_thread.join(timeout: 60)
    
    # 4. Check results
    puts "\n📊 Results:"
    
    app = message.reload.app
    if app
      puts "✅ App created: #{app.id}"
      puts "   Name: #{app.name}"
      puts "   Status: #{app.status}"
      puts "   Files generated: #{app.app_generated_files.count}"
      
      if app.app_generated_files.any?
        puts "\n   Files:"
        app.app_generated_files.limit(10).each do |file|
          puts "   - #{file.path} (#{file.content.bytesize} bytes)"
        end
      end
      
      if app.preview_url.present?
        puts "\n   Preview URL: #{app.preview_url}"
      end
    else
      puts "❌ No app created"
    end
    
    # Check assistant message final state
    assistant_msg.reload
    puts "\n📨 Assistant Message Final State:"
    puts "   Status: #{assistant_msg.status}"
    puts "   Iterations: #{assistant_msg.iteration_count}"
    puts "   Loop messages: #{assistant_msg.loop_messages.count}"
    puts "   Tool calls: #{assistant_msg.tool_calls.count}"
    puts "   Code generation: #{assistant_msg.is_code_generation?}"
    
    if assistant_msg.app_version.present?
      puts "   App version: #{assistant_msg.app_version.version_number}"
    end
    
  rescue => e
    puts "\n❌ ERROR: #{e.message}"
    puts e.backtrace.first(10).join("\n")
  end
  
  puts "\n" + "="*80
  puts "TEST COMPLETE"
  puts "="*80
end

# Run the test
if __FILE__ == $0
  test_v5_generation
end