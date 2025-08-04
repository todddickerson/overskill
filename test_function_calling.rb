#!/usr/bin/env ruby

# Test script for function calling implementation
require_relative 'config/environment'

puts "=== TESTING FUNCTION CALLING WITH KIMI K2 ==="

# Test the OpenRouter client directly
client = Ai::OpenRouterClient.new

# Simple test prompt
prompt = "Create a simple counter app with increment and decrement buttons"

puts "Testing function calling with prompt: #{prompt}"

# Test with verbose logging
ENV["VERBOSE_AI_LOGGING"] = "true"

begin
  result = client.generate_app(prompt, framework: "react")
  
  puts "\n=== RESULT ==="
  puts "Success: #{result[:success]}"
  puts "Model used: #{result[:model]}"
  
  if result[:success]
    if result[:tool_calls]
      puts "✅ Function calling worked!"
      puts "Tool calls: #{result[:tool_calls].length}"
      
      # Try to parse the function call
      tool_call = result[:tool_calls].first
      if tool_call
        puts "Function name: #{tool_call.dig('function', 'name')}"
        
        # Parse the arguments
        args = tool_call.dig('function', 'arguments')
        if args.is_a?(String)
          parsed_args = JSON.parse(args)
          puts "App name: #{parsed_args.dig('app', 'name')}"
          puts "Files count: #{parsed_args['files']&.length}"
          puts "✅ Function calling data looks good!"
        else
          puts "Arguments: #{args.class}"
        end
      end
    else
      puts "❌ No function calls in response"
      puts "Content: #{result[:content]&.[](0..200)}..."
    end
  else
    puts "❌ Function calling failed: #{result[:error]}"
  end
  
rescue => e
  puts "❌ Error testing function calling: #{e.message}"
  puts e.backtrace.first(5)
end

puts "\n=== TESTING COMPLETE ==="