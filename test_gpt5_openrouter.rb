#!/usr/bin/env ruby

# Load proper environment variables first
require 'dotenv'
Dotenv.load('.env.local', '.env.development.local', '.env.development', '.env')

# Override system dummy key
ENV['OPENAI_API_KEY'] = File.read('.env.local').match(/OPENAI_API_KEY=(.+)$/)[1] rescue nil

require_relative 'config/environment'
require 'colorize'

puts "🧪 Testing GPT-5 via OpenRouter".colorize(:cyan)
puts "==" * 30

# Test 1: Basic chat
puts "\n📝 Test 1: Basic GPT-5 chat via OpenRouter".colorize(:blue)

client = Ai::OpenRouterClient.new

messages = [
  {
    role: "system",
    content: "You are a helpful assistant. Answer concisely."
  },
  {
    role: "user",
    content: "Say 'Hello GPT-5!' if you're working."
  }
]

start_time = Time.current
response = client.chat(messages, model: :gpt5, temperature: 1.0)
elapsed = Time.current - start_time

if response[:success]
  puts "✅ GPT-5 responded in #{elapsed.round(1)}s:".colorize(:green)
  puts "   #{response[:content]}".colorize(:light_green)
else
  puts "❌ GPT-5 failed: #{response[:error]}".colorize(:red)
end

# Test 2: With tools
puts "\n🔧 Test 2: GPT-5 with tools via OpenRouter".colorize(:blue)

tools = [
  {
    type: "function",
    function: {
      name: "write_file",
      description: "Write content to a file",
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

tool_messages = [
  {
    role: "system",
    content: "You are a helpful assistant that can write files."
  },
  {
    role: "user",
    content: "Create a simple hello.txt file with 'Hello World' content"
  }
]

start_time = Time.current
tool_response = client.chat_with_tools(tool_messages, tools, model: :gpt5, temperature: 1.0)
elapsed = Time.current - start_time

if tool_response[:success]
  puts "✅ GPT-5 with tools responded in #{elapsed.round(1)}s".colorize(:green)
  if tool_response[:tool_calls]
    puts "   Tool calls made: #{tool_response[:tool_calls].count}".colorize(:light_green)
    tool_response[:tool_calls].each do |call|
      puts "     - #{call[:function][:name]}(#{call[:function][:arguments]})".colorize(:light_blue)
    end
  else
    puts "   Response: #{tool_response[:content]}".colorize(:light_green)
  end
else
  puts "❌ GPT-5 with tools failed: #{tool_response[:error]}".colorize(:red)
end

puts "\n✨ Test complete".colorize(:green)