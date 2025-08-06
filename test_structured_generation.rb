#!/usr/bin/env ruby
require_relative 'config/environment'

# Test the StructuredAppGenerator with UnifiedAiCoordinator
def test_structured_generation
  puts "\n=== Testing Structured App Generation (No Function Calling) ==="
  puts "This test uses structured prompts to work around Kimi K2's function calling limitations"
  
  # Find or create test app
  team = Team.first || Team.create!(name: "Test Team")
  membership = team.memberships.first || team.memberships.create!(
    user: User.first || User.create!(email: "test@example.com", password: "password"),
    role_ids: ["admin"]
  )
  
  # Try to find existing app first
  app = App.find_by(id: 'bNYLke') || App.find_by(slug: "test-todo-app")
  
  if app.nil?
    app = App.create!(
      team: team,
      creator: membership,
      name: "Test Todo App",
      slug: "test-todo-app-#{Time.now.to_i}",
      prompt: "Create a modern todo list application with React and TypeScript",
      app_type: "saas",
      framework: "react",
      status: "generating",
      base_price: 0
    )
  else
    app.update!(status: "generating", framework: "react", app_type: "saas")
  end
  
  puts "\nApp ID: #{app.id}"
  puts "App Name: #{app.name}"
  puts "Framework: #{app.framework}"
  
  # Clear existing files for clean test
  app.app_files.destroy_all
  puts "Cleared existing files"
  
  # Create a chat message
  message = app.app_chat_messages.create!(
    user: membership.user,
    role: "user",
    content: "Create a professional todo list app with React and TypeScript. Include features for adding, editing, deleting, and marking todos as complete. Use Tailwind CSS for styling and make it fully responsive."
  )
  
  puts "\nMessage created: #{message.id}"
  
  # Test direct StructuredAppGenerator first
  puts "\n--- Testing StructuredAppGenerator Directly ---"
  generator = Ai::StructuredAppGenerator.new
  result = generator.generate(
    message.content,
    framework: "react",
    app_type: "saas"
  )
  
  if result[:success]
    puts "✅ Direct generation successful!"
    puts "App info: #{result[:app].inspect}"
    puts "Files generated: #{result[:files].size}"
    result[:files].each do |file|
      puts "  - #{file['path']} (#{file['content'].size} bytes)"
    end
  else
    puts "❌ Direct generation failed: #{result[:error]}"
  end
  
  # Now test with UnifiedAiCoordinator
  puts "\n--- Testing UnifiedAiCoordinator Integration ---"
  coordinator = Ai::UnifiedAiCoordinator.new(app, message)
  
  begin
    coordinator.execute!
    
    # Check results
    app.reload
    puts "\n✅ Coordinator execution successful!"
    puts "App status: #{app.status}"
    puts "Files created: #{app.app_files.count}"
    
    app.app_files.each do |file|
      puts "  - #{file.path} (#{file.file_type}, #{file.content.size} bytes)"
    end
    
    # Check for React/TypeScript files
    tsx_files = app.app_files.where("path LIKE ?", "%.tsx")
    ts_files = app.app_files.where("path LIKE ?", "%.ts")
    
    puts "\nTypeScript files: #{ts_files.count + tsx_files.count}"
    puts "Has package.json: #{app.app_files.exists?(path: 'package.json')}"
    puts "Has wrangler.toml: #{app.app_files.exists?(path: 'wrangler.toml')}"
    puts "Has Supabase client: #{app.app_files.exists?(path: 'src/lib/supabase.ts')}"
    puts "Has analytics: #{app.app_files.exists?(path: 'src/lib/analytics.ts')}"
    
    # Check message updates
    message.reload
    assistant_messages = app.app_chat_messages.where(role: 'assistant').order(:created_at)
    puts "\nAssistant messages: #{assistant_messages.count}"
    assistant_messages.each do |msg|
      puts "  - #{msg.content[0..100]}..."
    end
    
  rescue => e
    puts "\n❌ Coordinator execution failed:"
    puts "Error: #{e.message}"
    puts e.backtrace.first(10).join("\n")
  end
  
  puts "\n=== Test Complete ==="
end

# Run the test
test_structured_generation