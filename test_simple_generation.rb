#!/usr/bin/env ruby
require_relative 'config/environment'

app = App.find(35)
message = app.app_chat_messages.where(role: 'user').last

puts "Testing simplified generation..."
puts "App: #{app.name}"
puts "Message: #{message.content}"

# Test just the AI call directly
client = Ai::OpenRouterClient.new

prompt = <<~PROMPT
  Create a simple landing page with:
  - Hero section
  - Contact form
  
  Return a JSON with:
  {
    "files": [
      {"path": "index.html", "content": "..."},
      {"path": "style.css", "content": "..."}
    ]
  }
  
  Keep it simple and brief.
PROMPT

puts "\n🤖 Calling AI..."
begin
  response = client.chat(
    [{ role: "user", content: prompt }],
    model: :claude_4,
    temperature: 0.5,
    max_tokens: 4000
  )
  
  if response[:success]
    puts "✅ AI responded!"
    
    # Try to parse JSON from response
    content = response[:content]
    if match = content.match(/```json\n(.*?)```/m) || content.match(/\{.*\}/m)
      json_str = match[1] || match[0]
      data = JSON.parse(json_str)
      
      puts "\n📁 Files to create:"
      data["files"].each do |file|
        puts "  - #{file["path"]} (#{file["content"].length} chars)"
        
        # Create the file
        app.app_files.create!(
          team: app.team,
          path: file["path"],
          content: file["content"],
          file_type: file["path"].split('.').last
        )
      end
      
      puts "\n✅ Files created successfully!"
    else
      puts "❌ Could not parse JSON from response"
      puts "Response preview: #{content[0..200]}..."
    end
  else
    puts "❌ AI call failed: #{response[:error]}"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Check results
app.reload
puts "\n📊 Final state:"
puts "  - Files: #{app.app_files.count}"
app.app_files.each do |f|
  puts "    • #{f.path}"
end