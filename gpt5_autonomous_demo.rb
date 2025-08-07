#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🚀 GPT-5 Autonomous Demo - Fast Results".colorize(:green)
puts "=" * 50

# Ensure OpenAI API key is configured
unless ENV['OPENAI_API_KEY'] && ENV['OPENAI_API_KEY'] != "dummy-key"
  puts "❌ Please set OPENAI_API_KEY environment variable"
  puts "   See SETUP_OPENAI.md for instructions"
  exit 1
end

def test_gpt5_app_generation(prompt, expected_patterns = [])
  puts "📝 Prompt: #{prompt}".colorize(:cyan)
  puts "⏱️  Starting generation...".colorize(:blue)
  
  start_time = Time.current
  
  # Define file creation tools
  tools = [
    {
      type: "function",
      function: {
        name: "create_file",
        description: "Create a new app file with content",
        parameters: {
          type: "object",
          properties: {
            filename: { type: "string", description: "File name (e.g. 'index.html', 'src/App.jsx')" },
            content: { type: "string", description: "File content" }
          },
          required: ["filename", "content"]
        }
      }
    },
    {
      type: "function", 
      function: {
        name: "finish_app",
        description: "Mark the app as complete",
        parameters: {
          type: "object",
          properties: {
            summary: { type: "string", description: "Brief summary of what was created" }
          },
          required: ["summary"]
        }
      }
    }
  ]

  messages = [
    {
      role: "system",
      content: "You are an expert React app developer. Create professional, working applications using CDN-based React. Always create complete, functional apps. Use the create_file tool for each file, then call finish_app when done."
    },
    {
      role: "user", 
      content: prompt
    }
  ]

  begin
    client = Ai::OpenRouterClient.new
    files_created = []
    max_iterations = 10
    iteration = 0
    ai_failed = false
    
    while iteration < max_iterations
      iteration += 1
      puts "   Iteration #{iteration}...".colorize(:light_blue)
      
      response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
      
      unless response[:success]
        puts "❌ GPT-5 failed: #{response[:error]}".colorize(:red)
        ai_failed = true
        break
      end
      
      # Add assistant response to conversation
      messages << {
        role: "assistant",
        content: response[:content],
        tool_calls: response[:tool_calls]
      }
      
      # Process tool calls
      if response[:tool_calls]
        tool_results = []
        
        response[:tool_calls].each do |tool_call|
          function_name = tool_call["function"]["name"]
          args = JSON.parse(tool_call["function"]["arguments"])
          
          case function_name
          when "create_file"
            filename = args["filename"]
            content = args["content"]
            files_created << { filename: filename, content: content, size: content.length }
            puts "     ✅ Created: #{filename} (#{content.length} chars)".colorize(:green)
            
            tool_results << {
              tool_call_id: tool_call["id"],
              role: "tool",
              content: JSON.generate({ success: true, message: "File #{filename} created successfully" })
            }
            
          when "finish_app"
            puts "     ✅ App completed: #{args['summary']}".colorize(:green)
            tool_results << {
              tool_call_id: tool_call["id"],
              role: "tool", 
              content: JSON.generate({ success: true, message: "App marked as complete" })
            }
            iteration = max_iterations  # Exit loop
          end
        end
        
        # Add tool results to conversation
        messages.concat(tool_results)
      else
        # No tool calls, we're done
        break
      end
    end
    
    elapsed = Time.current - start_time
    
    # Analyze results
    puts "\n📊 Results:".colorize(:cyan)
    puts "   ⏱️  Time: #{elapsed.round(2)}s".colorize(:blue)
    puts "   📁 Files: #{files_created.length}".colorize(:blue)
    
    if ai_failed
      puts "   ❌ FAILURE: AI failed during generation".colorize(:red)
      return { success: false, files: files_created.length, time: elapsed, error: "AI failed" }
    elsif files_created.any?
      puts "   ✅ SUCCESS: App generated!".colorize(:green)
      
      files_created.each do |file|
        puts "     📄 #{file[:filename]} (#{file[:size]} chars)".colorize(:light_green)
        
        # Check for expected patterns
        expected_patterns.each do |pattern|
          if file[:content].downcase.include?(pattern.downcase)
            puts "       ✅ Contains: #{pattern}".colorize(:green)
          end
        end
      end
      
      # Show summary stats
      total_chars = files_created.sum { |f| f[:size] }
      puts "   📈 Total code: #{total_chars} characters".colorize(:blue)
      
      return { success: true, files: files_created.length, time: elapsed }
    else
      puts "   ❌ FAILURE: No files created".colorize(:red)
      return { success: false, files: 0, time: elapsed }
    end
    
  rescue => e
    puts "❌ Exception: #{e.message}".colorize(:red)
    return { success: false, files: 0, time: Time.current - start_time, error: e.message }
  end
end

# Run test suite
test_cases = [
  {
    name: "Simple Counter",
    prompt: "Create a minimal counter app with + and - buttons. Use React with CDN. Just one index.html file.",
    patterns: ["React", "useState", "counter", "button"]
  },
  {
    name: "Todo List", 
    prompt: "Create a simple todo list app. Add/remove items. Use React with CDN. Just index.html.",
    patterns: ["React", "useState", "todo", "input"]
  }
]

results = []
puts "🧪 Running GPT-5 Test Suite".colorize(:yellow)
puts "-" * 50

test_cases.each_with_index do |test_case, i|
  puts "\n🎯 Test #{i+1}/#{test_cases.length}: #{test_case[:name]}".colorize(:yellow)
  puts "-" * 30
  
  result = test_gpt5_app_generation(test_case[:prompt], test_case[:patterns])
  results << result.merge(name: test_case[:name])
  
  sleep(2)  # Brief pause between tests
end

# Final report
puts "\n" + "=" * 50
puts "🎯 FINAL REPORT".colorize(:cyan)
puts "=" * 50

successful = results.count { |r| r[:success] }
success_rate = (successful.to_f / results.length * 100).round(1)

puts "📈 Success Rate: #{success_rate}% (#{successful}/#{results.length})".colorize(success_rate >= 80 ? :green : :red)

avg_time = results.map { |r| r[:time] }.sum / results.length
puts "⏱️  Average Time: #{avg_time.round(2)}s".colorize(:blue)

avg_files = results.select { |r| r[:success] }.map { |r| r[:files] }.sum.to_f / [successful, 1].max
puts "📁 Average Files: #{avg_files.round(1)}".colorize(:blue)

puts "\n💡 GPT-5 Autonomous Generation: #{success_rate >= 70 ? 'WORKING WELL! 🎉' : 'Needs improvement 🔧'}".colorize(success_rate >= 70 ? :green : :yellow)

puts "\n" + "=" * 50