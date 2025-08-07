#!/usr/bin/env ruby
# Test tool calling structure to understand the issue
# Run with: bin/rails runner test_tool_structure.rb

ENV["VERBOSE_AI_LOGGING"] = "true"

puts "=" * 60
puts "🔧 TESTING TOOL CALL STRUCTURE" 
puts "=" * 60

begin
  client = Ai::OpenRouterClient.new
  
  tools = [
    {
      type: "function",
      function: {
        name: "write_file",
        description: "Create a new file with content",
        parameters: {
          type: "object",
          properties: {
            path: { type: "string", description: "File path" },
            content: { type: "string", description: "File content" }
          },
          required: ["path", "content"]
        }
      }
    }
  ]
  
  messages = [
    {
      role: "user",
      content: "Create a simple HTML file called index.html with 'Hello World' content. Use the write_file function."
    }
  ]
  
  puts "Testing tool calling with Claude Sonnet 4..."
  response = client.chat_with_tools(messages, tools, model: :claude_sonnet_4)
  
  puts "Response success: #{response[:success]}"
  
  if response[:success]
    puts "Content: #{response[:content] || 'None'}"
    puts "Tool calls count: #{response[:tool_calls]&.length || 0}"
    
    if response[:tool_calls]&.any?
      response[:tool_calls].each_with_index do |call, i|
        puts "\nTool call #{i+1}:"
        puts "  Keys: #{call.keys.join(', ')}"
        puts "  ID (symbol): #{call[:id] || 'MISSING'}"
        puts "  ID (string): #{call['id'] || 'MISSING'}"
        puts "  Type (symbol): #{call[:type] || 'MISSING'}"
        puts "  Type (string): #{call['type'] || 'MISSING'}"
        if call[:function]
          puts "  Function name: #{call[:function][:name]}"
          puts "  Function args keys: #{call[:function].keys.join(', ')}"
          
          if call[:function][:arguments]
            if call[:function][:arguments].is_a?(String)
              puts "  Arguments (string): #{call[:function][:arguments]}"
            else
              puts "  Arguments (hash): #{call[:function][:arguments].inspect}"
            end
          end
        end
      end
    end
  else
    puts "Error: #{response[:error]}"
  end
  
rescue => e
  puts "❌ Test error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n" + "=" * 60
puts "Tool structure test completed"