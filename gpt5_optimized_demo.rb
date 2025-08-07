#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🚀 GPT-5 Optimized Demo - Speed-Focused".colorize(:green)
puts "=" * 50

# Ensure OpenAI API key is configured
unless ENV['OPENAI_API_KEY'] && ENV['OPENAI_API_KEY'] != "dummy-key"
  puts "❌ Please set OPENAI_API_KEY environment variable"
  puts "   See SETUP_OPENAI.md for instructions"
  exit 1
end

def test_optimized_generation(prompt, expected_patterns = [], complexity = :simple)
  puts "📝 Prompt: #{prompt}".colorize(:cyan)
  puts "🔧 Complexity: #{complexity.to_s.upcase}".colorize(:yellow)
  puts "⏱️  Starting generation...".colorize(:blue)
  
  start_time = Time.current
  
  # Optimized tools with batch creation
  tools = [
    {
      type: "function",
      function: {
        name: "create_complete_app",
        description: "Create a complete app with all necessary files in one call",
        parameters: {
          type: "object",
          properties: {
            files: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  filename: { type: "string", description: "File name" },
                  content: { type: "string", description: "File content" }
                },
                required: ["filename", "content"]
              },
              description: "Array of all files needed for the app"
            },
            summary: { type: "string", description: "Brief summary of what was created" }
          },
          required: ["files", "summary"]
        }
      }
    }
  ]

  # Complexity-aware system prompt
  system_prompt = case complexity
  when :simple
    "You are an expert at creating MINIMAL, focused React apps. For simple requests (counter, basic todo), create the most concise, working solution possible. Use React CDN, minimal styling, keep code under 2000 chars total. Create everything in ONE response using create_complete_app."
  when :complex  
    "You are an expert React app developer. Create comprehensive, feature-rich applications using CDN-based React. Include advanced features, proper error handling, and professional styling. Use create_complete_app with all necessary files."
  end

  messages = [
    {
      role: "system",
      content: system_prompt
    },
    {
      role: "user", 
      content: prompt
    }
  ]

  begin
    client = Ai::OpenRouterClient.new
    files_created = []
    
    puts "   Making single optimized request...".colorize(:light_blue)
    
    response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
    
    unless response[:success]
      puts "❌ GPT-5 failed: #{response[:error]}".colorize(:red)
      return { success: false, files: 0, time: Time.current - start_time, error: response[:error] }
    end
    
    # Process tool calls
    if response[:tool_calls]
      response[:tool_calls].each do |tool_call|
        function_name = tool_call["function"]["name"]
        args = JSON.parse(tool_call["function"]["arguments"])
        
        if function_name == "create_complete_app"
          args["files"].each do |file|
            filename = file["filename"]
            content = file["content"]
            files_created << { filename: filename, content: content, size: content.length }
            puts "     ✅ Created: #{filename} (#{content.length} chars)".colorize(:green)
          end
          puts "     ✅ App completed: #{args['summary']}".colorize(:green)
        end
      end
    end
    
    elapsed = Time.current - start_time
    
    # Analyze results
    puts "\n📊 Results:".colorize(:cyan)
    puts "   ⏱️  Time: #{elapsed.round(2)}s".colorize(:blue)
    puts "   📁 Files: #{files_created.length}".colorize(:blue)
    
    if files_created.any?
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
      
      # Performance analysis
      if complexity == :simple && total_chars > 2500
        puts "   ⚠️  Warning: Simple app exceeded 2500 chars".colorize(:yellow)
      end
      
      return { success: true, files: files_created.length, time: elapsed, chars: total_chars }
    else
      puts "   ❌ FAILURE: No files created".colorize(:red)
      return { success: false, files: 0, time: elapsed }
    end
    
  rescue => e
    puts "❌ Exception: #{e.message}".colorize(:red)
    return { success: false, files: 0, time: Time.current - start_time, error: e.message }
  end
end

# Run optimized tests
puts "🧪 Running Optimized GPT-5 Test Suite".colorize(:yellow)
puts "-" * 50

results = []

# Test 1: Simple Counter (should be < 20s, < 2000 chars)
result1 = test_optimized_generation(
  "Create a minimal counter app with + and - buttons. Use React with CDN. Just one index.html file.",
  ["react", "usestate", "counter", "button"],
  :simple
)
results << result1.merge(name: "Simple Counter")

puts "\n"

# Test 2: Simple Todo (should be < 30s, reasonable size)
result2 = test_optimized_generation(
  "Create a simple todo list app. Add/remove items. Use React with CDN. Just index.html.",
  ["react", "usestate", "todo", "input"],
  :simple
)
results << result2.merge(name: "Simple Todo")

# Final Report
puts "\n" + "=" * 50
puts "🎯 OPTIMIZATION REPORT".colorize(:cyan)
puts "=" * 50

successful = results.count { |r| r[:success] }
success_rate = (successful.to_f / results.length * 100).round(1)
avg_time = results.sum { |r| r[:time] } / results.length

puts "📈 Success Rate: #{success_rate}% (#{successful}/#{results.length})".colorize(success_rate >= 90 ? :green : :red)
puts "⏱️  Average Time: #{avg_time.round(2)}s".colorize(:blue)
puts "📁 Average Files: #{results.sum { |r| r[:files] } / results.length.to_f}".colorize(:blue)

results.each do |result|
  status = result[:success] ? "✅" : "❌"
  time_status = result[:time] < 25 ? "🚀" : "⏳"
  size_status = (result[:chars] || 0) < 2500 ? "📦" : "📚"
  
  puts "\n#{status} #{result[:name]}"
  puts "   #{time_status} Time: #{result[:time].round(1)}s"
  puts "   #{size_status} Size: #{result[:chars] || 0} chars" if result[:chars]
end

improvement = results.any? { |r| r[:time] < 25 }
puts "\n💡 Speed Optimization: #{improvement ? 'IMPROVED! 🎉' : 'Needs work 🔧'}".colorize(improvement ? :green : :yellow)

puts "\n" + "=" * 50