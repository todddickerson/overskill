#!/usr/bin/env ruby
# Full test of incremental streaming with text ordering fix

require 'rails'

# Create a test app and message
puts "🚀 Setting up test app and message..."

user = User.first || User.create!(
  email: "test@example.com",
  password: "password123"
)

app = App.create!(
  user: user,
  name: "Test Incremental Streaming",
  status: "generating"
)

message = AppChatMessage.create!(
  app: app,
  role: "user",
  content: "Create a simple counter app"
)

assistant_message = AppChatMessage.create!(
  app: app,
  role: "assistant",
  content: "",
  conversation_flow: []
)

puts "✅ Created app ##{app.id} and message ##{assistant_message.id}"
puts

# Simulate the incremental streaming process
puts "🔄 Testing incremental streaming..."
puts "=" * 60

# Initialize the builder
builder = Ai::AppBuilderV5.new(assistant_message)

# Test conversation messages (minimal for testing)
conversation = [
  { role: "system", content: "You are an AI assistant that builds apps." },
  { role: "user", content: message.content }
]

# Set up monitoring
monitor_thread = Thread.new do
  loop do
    assistant_message.reload
    flow = assistant_message.conversation_flow || []
    
    if flow.any?
      text_items = flow.select { |f| f['type'] == 'message' || f['type'] == 'content' }
      tool_items = flow.select { |f| f['type'] == 'tools' }
      
      if text_items.any? || tool_items.any?
        puts "\n📊 Current state:"
        flow.each_with_index do |item, i|
          if item['type'] == 'message' || item['type'] == 'content'
            content = item['content'].to_s
            puts "  [#{i}] TEXT: #{content.truncate(50)} (#{content.length} chars)"
          elsif item['type'] == 'tools'
            tools = item['tools'] || []
            puts "  [#{i}] TOOLS: #{tools.count} tools"
          end
        end
        
        # Check ordering
        text_index = flow.find_index { |f| f['type'] == 'message' || f['type'] == 'content' }
        tools_index = flow.find_index { |f| f['type'] == 'tools' }
        
        if text_index && tools_index
          if text_index < tools_index
            puts "  ✅ Order correct: Text at [#{text_index}] before Tools at [#{tools_index}]"
          else
            puts "  ❌ Order wrong: Text at [#{text_index}] after Tools at [#{tools_index}]"
          end
        end
      end
    end
    
    sleep 2
  rescue => e
    puts "Monitor error: #{e.message}"
  end
end

# Run a limited test (just one iteration to see the flow)
begin
  puts "\n🎯 Starting incremental execution..."
  
  # Call the method directly (simplified for testing)
  # This would normally be called via ProcessAppUpdateJobV5
  
  # Note: We'll need to mock or stub the API response for a full test
  puts "Note: For a full test, trigger via UI or ProcessAppUpdateJobV5"
  puts "Monitoring conversation_flow updates for 10 seconds..."
  
  sleep 10
  
ensure
  monitor_thread.kill if monitor_thread
end

puts "\n" + "=" * 60
puts "📝 Final Analysis:"
puts

assistant_message.reload
flow = assistant_message.conversation_flow || []

if flow.empty?
  puts "⚠️  No conversation flow generated (may need to trigger via UI)"
else
  text_first = false
  flow.each_with_index do |item, i|
    type = item['type']
    if (type == 'message' || type == 'content') && !text_first
      text_first = (i == 0 || flow[0..i-1].none? { |f| f['type'] == 'tools' })
      break
    end
  end
  
  if text_first
    puts "✅ SUCCESS: Text appears before tools in conversation flow!"
  else
    puts "❌ FAILURE: Text does not appear before tools"
  end
end

puts
puts "Cleanup: Run 'App.find(#{app.id}).destroy' to remove test data"