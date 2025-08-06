#!/usr/bin/env ruby
# Test generation directly without UnifiedAiCoordinator
require_relative 'config/environment'

app = App.find(35)
app.app_chat_messages.destroy_all
app.app_files.destroy_all

message = app.app_chat_messages.create!(
  role: 'user',
  content: 'Create a landing page',
  user: User.first
)

puts "Testing direct generation (bypassing UnifiedAiCoordinator)..."

# Create assistant message
assistant_msg = app.app_chat_messages.create!(
  role: 'assistant',
  content: 'Generating your landing page...',
  status: 'generating'
)

# Call AI directly using the working approach
client = Ai::OpenRouterClient.new

# Use the generate_app_with_function_calling method that's proven to work
prompt = <<~PROMPT
  Generate a complete landing page application.
  
  Requirements:
  - Hero section with title and subtitle
  - Contact form with name, email, message
  - Blue color scheme
  - Modern, responsive design
  
  Framework: vanilla (HTML, CSS, JavaScript)
  
  #{File.read('AI_APP_STANDARDS.md') rescue 'Use best practices'}
PROMPT

puts "🤖 Calling AI with function calling..."

begin
  result = client.generate_app(prompt, framework: "vanilla", app_type: "landing_page")
  
  if result[:success] && result[:tool_calls]
    puts "✅ AI responded with function calls!"
    
    # Parse the function call
    tool_call = result[:tool_calls].first
    if tool_call && tool_call['function']
      args = tool_call['function']['arguments']
      data = args.is_a?(String) ? JSON.parse(args) : args
      
      # Create files
      if data['files']
        puts "\n📁 Creating #{data['files'].length} files..."
        data['files'].each do |file_info|
          file = app.app_files.create!(
            team: app.team,
            path: file_info['path'],
            content: file_info['content'],
            file_type: file_info['path'].split('.').last
          )
          puts "  ✅ #{file.path} (#{file.content.length} chars)"
        end
      end
      
      # Create version
      app.app_versions.create!(
        team: app.team,
        user: message.user,
        version_number: "1.0.0",
        changelog: "Initial generation"
      )
      
      # Update statuses
      app.update!(status: 'generated')
      assistant_msg.update!(
        content: "✅ Successfully generated your landing page!",
        status: 'completed'
      )
      
      puts "\n✅ Generation complete!"
    else
      puts "❌ No function call found in response"
    end
  else
    puts "❌ AI call failed: #{result[:error] || 'Unknown error'}"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

# Check results
app.reload
puts "\n📊 Final results:"
puts "  - Status: #{app.status}"
puts "  - Files: #{app.app_files.count}"
app.app_files.each do |f|
  puts "    • #{f.path}"
end
puts "  - Versions: #{app.app_versions.count}"