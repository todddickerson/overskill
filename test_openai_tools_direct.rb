#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'uri'

puts "Testing OpenAI tools directly with GPT-5..."

# Simple tool definition
tools = [
  {
    type: "function",
    function: {
      name: "create_file",
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

# Simple prompt
messages = [
  {
    role: "system",
    content: "You are a helpful assistant that creates files using the create_file tool function."
  },
  {
    role: "user", 
    content: "Create a simple HTML file at index.html with a hello world message. Use the create_file tool to do this."
  }
]

# Make API request
uri = URI('https://api.openai.com/v1/chat/completions')

request_body = {
  model: "gpt-5",
  messages: messages,
  tools: tools,
  tool_choice: "auto",
  # temperature: 1,  # GPT-5 only supports default temperature of 1
  max_completion_tokens: 1000  # GPT-5 uses max_completion_tokens
}

http = Net::HTTP.new(uri.host, uri.port)
http.use_ssl = true
http.read_timeout = 30

request = Net::HTTP::Post.new(uri)
request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
request['Content-Type'] = 'application/json'
request.body = request_body.to_json

puts "Sending request to OpenAI..."
puts "Model: #{request_body[:model]}"
puts "Tools: #{tools.length} defined"
puts "-" * 40

begin
  response = http.request(request)
  puts "Response status: #{response.code}"
  
  result = JSON.parse(response.body)
  
  if result['error']
    puts "❌ API Error: #{result['error']['message']}"
    puts "Error type: #{result['error']['type']}"
    puts "Full error: #{JSON.pretty_generate(result['error'])}"
  else
    puts "✅ Success!"
    
    if result['choices'] && result['choices'][0]
      choice = result['choices'][0]
      message = choice['message']
      
      puts "\nResponse structure:"
      puts "  Role: #{message['role']}"
      puts "  Has content: #{message['content'] ? 'Yes' : 'No'}"
      puts "  Has tool_calls: #{message['tool_calls'] ? 'Yes' : 'No'}"
      
      if message['tool_calls']
        puts "\n📦 Tool calls detected: #{message['tool_calls'].length}"
        message['tool_calls'].each_with_index do |call, i|
          puts "\n  Tool call #{i + 1}:"
          puts "    Function: #{call['function']['name']}"
          
          begin
            args = JSON.parse(call['function']['arguments'])
            puts "    Arguments:"
            args.each do |key, value|
              puts "      #{key}: #{value[0..100]}#{value.length > 100 ? '...' : ''}"
            end
          rescue
            puts "    Arguments (raw): #{call['function']['arguments']}"
          end
        end
      elsif message['content']
        puts "\n📝 Content response (first 500 chars):"
        puts message['content'][0..500]
      end
      
      puts "\nFinish reason: #{choice['finish_reason']}"
    end
    
    puts "\n📊 Token usage:"
    puts "  Prompt tokens: #{result['usage']['prompt_tokens']}"
    puts "  Completion tokens: #{result['usage']['completion_tokens']}"
    puts "  Total tokens: #{result['usage']['total_tokens']}"
  end
  
rescue => e
  puts "❌ Exception: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end