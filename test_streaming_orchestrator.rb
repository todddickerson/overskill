#!/usr/bin/env ruby
# Test script for streaming AI orchestrator

require_relative 'config/environment'

def test_streaming_orchestrator
  puts "\n🚀 Testing Streaming AI Orchestrator\n"
  puts "=" * 60
  
  # Setup test data
  team = Team.first || Team.create!(name: "Test Team")
  user = User.first || User.create!(email: "test@example.com", password: "password123")
  
  unless team.memberships.exists?(user: user)
    team.memberships.create!(user: user, role_ids: ["admin"])
  end
  
  # Get membership for creator reference
  membership = team.memberships.find_by(user: user)
  
  # Create or find test app
  app = team.apps.find_or_create_by!(name: "Streaming Test App") do |a|
    a.prompt = "A simple test app"
    a.app_type = "business"
    a.framework = "vanilla"
    a.status = "generated"
    a.creator = membership  # Apps require a creator (membership)
  end
  
  # Ensure app has base file
  unless app.app_files.exists?
    app.app_files.create!(
      path: "index.html",
      content: "<html><body><h1>Original</h1></body></html>",
      file_type: "html",
      team: team  # AppFile requires team reference
    )
  end
  
  puts "📱 Test App: #{app.name} (ID: #{app.id})"
  
  # Test requests
  test_requests = [
    "Add a beautiful contact form with name, email, and message fields",
    "Create a dashboard with charts and statistics",
    "Add a navigation menu with Home, About, and Contact pages"
  ]
  
  # Use environment variable or default to first request
  request_index = (ENV['REQUEST_INDEX'] || '1').to_i - 1
  request_index = 0 if request_index < 0 || request_index >= test_requests.length
  
  request = ENV['CUSTOM_REQUEST'] || test_requests[request_index]
  
  puts "\n📝 Request: \"#{request}\""
  
  # Create chat message
  chat_message = app.app_chat_messages.create!(
    user: user,
    role: "user",
    content: request
  )
  
  puts "\n⚡ Testing Streaming Orchestrator..."
  puts "=" * 60
  
  # Create a mock broadcast receiver to see updates
  updates_received = []
  
  # Monkey-patch to capture broadcasts
  original_broadcast = Turbo::StreamsChannel.method(:broadcast_action_to)
  Turbo::StreamsChannel.define_singleton_method(:broadcast_action_to) do |channel, **options|
    if channel == "app_#{app.id}_chat" && options[:action] == :replace
      puts "\n📢 UPDATE: #{options[:html][0..200]}..." if options[:html]
      updates_received << options
    end
    original_broadcast.call(channel, **options)
  end
  
  begin
    # Test the streaming orchestrator directly
    orchestrator = Ai::AppUpdateOrchestratorStreaming.new(chat_message)
    
    # Monkey-patch to see streaming chunks
    client = orchestrator.instance_variable_get(:@client)
    original_stream = client.method(:stream_chat)
    
    chunks_received = []
    client.define_singleton_method(:stream_chat) do |messages, &block|
      puts "\n🌊 Starting stream..."
      
      # Simulate streaming with test data
      test_chunks = [
        "[THINKING] I need to create a contact form with proper styling\n",
        "[PLANNING] I'll add a form with Tailwind CSS styling and validation\n",
        "[FILE_START:index.html]\n",
        "<!DOCTYPE html>\n",
        "<html lang=\"en\">\n",
        "<head>\n",
        "  <title>Contact Form</title>\n",
        "  <script src=\"https://cdn.tailwindcss.com\"></script>\n",
        "</head>\n",
        "<body>\n",
        "  <div class=\"max-w-md mx-auto mt-10\">\n",
        "    <form class=\"bg-white p-6 rounded-lg shadow\">\n",
        "      <input type=\"text\" placeholder=\"Name\" class=\"w-full mb-4 p-2 border rounded\">\n",
        "      <input type=\"email\" placeholder=\"Email\" class=\"w-full mb-4 p-2 border rounded\">\n",
        "      <textarea placeholder=\"Message\" class=\"w-full mb-4 p-2 border rounded\"></textarea>\n",
        "      <button type=\"submit\" class=\"bg-blue-500 text-white px-4 py-2 rounded\">Send</button>\n",
        "    </form>\n",
        "  </div>\n",
        "</body>\n",
        "</html>\n",
        "[FILE_END:index.html]\n",
        "[PROGRESS] Contact form created with Tailwind styling\n",
        "[COMPLETE] Successfully added a contact form to your app!\n"
      ]
      
      test_chunks.each_with_index do |chunk, i|
        puts "  Chunk #{i + 1}: #{chunk[0..50]}..." if chunk.length > 50
        chunks_received << chunk
        block.call(chunk)
        sleep(0.1) # Simulate network delay
      end
      
      { success: true }
    end
    
    # Execute the orchestrator
    start_time = Time.now
    orchestrator.execute!
    elapsed = Time.now - start_time
    
    puts "\n" + "=" * 60
    puts "✅ Streaming completed in #{elapsed.round(2)} seconds"
    
    # Show statistics
    puts "\n📊 Statistics:"
    puts "  Chunks received: #{chunks_received.length}"
    puts "  Updates broadcast: #{updates_received.length}"
    puts "  Files modified: #{app.reload.app_files.where("updated_at > ?", 1.minute.ago).count}"
    
    # Show final message
    final_message = app.app_chat_messages.where(role: "assistant").last
    if final_message
      puts "\n💬 Final Message:"
      puts "  Status: #{final_message.status}"
      puts "  Content: #{final_message.content[0..200]}..."
    end
    
    # Show updated files
    puts "\n📁 Updated Files:"
    app.app_files.where("updated_at > ?", 1.minute.ago).each do |file|
      puts "  • #{file.path} (#{file.content.length} bytes)"
    end
    
  rescue => e
    puts "\n❌ ERROR: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  ensure
    # Restore original methods
    Turbo::StreamsChannel.define_singleton_method(:broadcast_action_to, &original_broadcast)
  end
  
  puts "\n🎯 Test Complete!"
  puts "View the app at: http://localhost:3000/account/apps/#{app.id}/editor"
end

# Alternative: Test real streaming from OpenRouter
def test_real_streaming
  puts "\n🌊 Testing Real OpenRouter Streaming\n"
  puts "=" * 60
  
  client = Ai::OpenRouterClient.new
  
  messages = [
    {
      role: "system",
      content: "You are a helpful assistant. When asked to create something, use markers like [THINKING], [FILE_START:name], [FILE_END:name], [PROGRESS], and [COMPLETE]."
    },
    {
      role: "user",
      content: "Create a simple HTML button that says 'Click me' with blue styling."
    }
  ]
  
  puts "Sending request to OpenRouter..."
  puts "Messages:", messages.to_json[0..200] + "..."
  puts "\nStreaming response:\n"
  
  all_content = ""
  chunk_count = 0
  
  result = client.stream_chat(messages) do |chunk|
    print chunk
    all_content += chunk
    chunk_count += 1
  end
  
  puts "\n\n" + "=" * 60
  puts "Stream complete!"
  puts "Success: #{result[:success]}"
  puts "Total chunks: #{chunk_count}"
  puts "Total content length: #{all_content.length}"
  
  # Check for markers
  puts "\nMarkers found:"
  puts "  [THINKING]: #{all_content.include?('[THINKING]')}"
  puts "  [FILE_START]: #{all_content.include?('[FILE_START')}"
  puts "  [FILE_END]: #{all_content.include?('[FILE_END')}"
  puts "  [PROGRESS]: #{all_content.include?('[PROGRESS]')}"
  puts "  [COMPLETE]: #{all_content.include?('[COMPLETE]')}"
end

# Run the test
if __FILE__ == $0
  # Check for command line argument or environment variable
  test_mode = ARGV[0] || ENV['TEST_MODE'] || '1'
  
  case test_mode
  when '2', 'real'
    puts "Running real OpenRouter streaming test..."
    test_real_streaming
  else
    puts "Running mock streaming orchestrator test..."
    test_streaming_orchestrator
  end
end