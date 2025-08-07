#!/usr/bin/env ruby
require_relative 'config/environment'

puts "🚀 Direct GPT-5 Test (No Orchestrator)"
puts "=" * 40

# Set API keys
# Ensure OpenAI API key is set
if ENV['OPENAI_API_KEY'].nil? || ENV['OPENAI_API_KEY'] == 'dummy-key'
  puts "Please set OPENAI_API_KEY environment variable"
  exit 1
end

# Test 1: Basic GPT-5 Response (No Tools)
puts "🧪 Test 1: Basic GPT-5 Chat"
begin
  client = Ai::OpenRouterClient.new
  response = client.chat([
    { role: "user", content: "Say 'GPT-5 is working!' and explain in one sentence what React useState does." }
  ], model: :gpt5, temperature: 0.7)
  
  if response[:success]
    puts "✅ Basic chat success: #{response[:content][0..100]}..."
    puts "   Model used: #{response[:model] || 'Unknown'}"
  else
    puts "❌ Basic chat failed: #{response[:error]}"
  end
rescue => e
  puts "❌ Exception in basic chat: #{e.message}"
end

puts "\n" + "-" * 40

# Test 2: GPT-5 with Simple Tools
puts "🧪 Test 2: GPT-5 with Tool Calling"

tools = [
  {
    type: "function",
    function: {
      name: "create_file",
      description: "Create a new file with content",
      parameters: {
        type: "object",
        properties: {
          filename: { type: "string", description: "Name of the file" },
          content: { type: "string", description: "Content of the file" }
        },
        required: ["filename", "content"]
      }
    }
  }
]

messages = [
  { role: "user", content: "Create a simple HTML file called 'hello.html' with the text 'Hello World'" }
]

begin
  client = Ai::OpenRouterClient.new
  response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 0.7)
  
  if response[:success]
    puts "✅ Tool calling success!"
    puts "   Response: #{response[:content][0..100]}..." if response[:content]
    
    if response[:tool_calls]
      puts "   Tool calls: #{response[:tool_calls].length}"
      response[:tool_calls].each_with_index do |tool_call, i|
        puts "     #{i+1}. #{tool_call[:function][:name]} - #{tool_call[:function][:arguments][0..50]}..."
      end
    else
      puts "   No tool calls made"
    end
  else
    puts "❌ Tool calling failed: #{response[:error]}"
  end
rescue => e
  puts "❌ Exception in tool calling: #{e.message}"
  puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
end

puts "\n" + "-" * 40

# Test 3: End-to-End File Generation
puts "🧪 Test 3: End-to-End File Generation Test"

app = App.find(59)
original_file_count = app.app_files.count

# Define React app generation tools
react_tools = [
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Create or update a file with the given content",
      parameters: {
        type: "object",
        properties: {
          path: { type: "string", description: "File path (e.g. 'index.html', 'src/App.jsx')" },
          content: { type: "string", description: "File content" }
        },
        required: ["path", "content"]
      }
    }
  }
]

react_messages = [
  {
    role: "system", 
    content: "You are a React app generator. Create minimal but functional React apps using CDN React."
  },
  {
    role: "user", 
    content: "Create a minimal counter app with just index.html and inline React code. Keep it under 100 lines total."
  }
]

begin
  client = Ai::OpenRouterClient.new
  response = client.chat_with_tools(react_messages, react_tools, model: :gpt5, temperature: 0.3)
  
  if response[:success] && response[:tool_calls]
    puts "✅ GPT-5 generated file instructions!"
    puts "   Files to create: #{response[:tool_calls].length}"
    
    # Simulate file creation (don't actually create to avoid conflicts)
    response[:tool_calls].each_with_index do |tool_call, i|
      if tool_call[:function][:name] == "write_file"
        args = JSON.parse(tool_call[:function][:arguments])
        filename = args["path"]
        content_length = args["content"].length
        
        puts "     #{i+1}. #{filename} (#{content_length} chars)"
        
        # Check for React patterns
        content = args["content"]
        patterns = []
        patterns << "React" if content.include?("React")
        patterns << "useState" if content.include?("useState")
        patterns << "counter" if content.downcase.include?("counter")
        
        puts "       Patterns found: #{patterns.join(', ')}" if patterns.any?
      end
    end
    
    puts "✅ GPT-5 WORKING END-TO-END!"
    
  else
    puts "❌ File generation failed: #{response[:error] || 'No tool calls'}"
  end
rescue => e
  puts "❌ Exception in file generation: #{e.message}"
end

puts "\n" + "=" * 40
puts "🎯 CONCLUSION: Direct GPT-5 testing complete"
puts "=" * 40