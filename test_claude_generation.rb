#!/usr/bin/env ruby
require_relative 'config/environment'

# Test with Claude fallback
puts "\n=== Testing with Claude Fallback ==="

# Directly test Claude generation
client = Ai::OpenRouterClient.new
prompt = <<~PROMPT
  Create a simple counter React app.
  
  Return JSON with exactly this structure:
  {
    "app": {"name": "Counter App", "description": "Simple counter"},
    "files": [
      {"path": "index.html", "content": "complete HTML"},
      {"path": "src/App.tsx", "content": "complete React code"},
      {"path": "package.json", "content": "complete package.json"}
    ]
  }
  
  Return ONLY the JSON, no other text.
PROMPT

messages = [
  {role: "system", content: "You are a code generator. Return only valid JSON."},
  {role: "user", content: prompt}
]

puts "Testing with Claude 4..."
result = client.chat(messages, model: :claude_4, max_tokens: 8000)

if result[:success]
  puts "✅ Claude response received"
  
  # Try to parse JSON
  begin
    json_match = result[:content].match(/\{.*"files".*\}/m)
    if json_match
      data = JSON.parse(json_match[0])
      puts "✅ JSON parsed successfully"
      puts "Files: #{data['files'].size}"
    else
      puts "❌ No JSON found in response"
    end
  rescue => e
    puts "❌ Parse error: #{e.message}"
  end
else
  puts "❌ Claude failed: #{result[:error]}"
end

puts "\n=== Done ==="