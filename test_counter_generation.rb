#!/usr/bin/env ruby
# Test counter app generation after fixes

require_relative 'config/environment'

puts "🧪 Testing Counter App Generation (Post-Fix)"
puts "=" * 50

# Get existing app or create new one
app = App.find_by(id: 58) || App.create!(
  name: "Counter Test App",
  app_type: "tool",
  framework: "react",
  prompt: "Simple counter app",
  team: Team.first,
  creator: Membership.first
)

puts "Using app: #{app.name} (ID: #{app.id})"

# Clear existing files
app.app_files.destroy_all
puts "Cleared existing files"

# Create a simple counter app request
message = app.app_chat_messages.create!(
  role: "user",
  content: "Create a simple counter app with increment, decrement, and reset buttons. Use React with useState. Style it nicely with Tailwind CSS. Don't include authentication or database - just a local state counter."
)

puts "Created message ID: #{message.id}"
puts "Request: #{message.content[0..100]}..."

# Process the message using the job
puts "\nProcessing with ProcessAppUpdateJob..."
begin
  job = ProcessAppUpdateJob.new
  job.perform(message)
  
  # Check results
  message.reload
  
  # Check generated files
  files = app.app_files.reload
  puts "\nGenerated #{files.count} files:"
  files.each do |file|
    puts "  - #{file.path} (#{file.file_type}, #{file.size_bytes} bytes)"
  end
  
  # Check if it's actually a counter app
  main_file = files.find { |f| f.path.include?('App.tsx') || f.path.include?('App.jsx') }
  if main_file
    content = main_file.content
    puts "\n🔍 Counter Implementation Analysis:"
    puts "  - useState: #{content.include?('useState') ? '✅' : '❌'}"
    puts "  - Counter state: #{content.match?(/useState.*count|count.*useState/i) ? '✅' : '❌'}"
    puts "  - Increment: #{content.match?(/increment|setCount.*\+|\+.*setCount/i) ? '✅' : '❌'}"
    puts "  - Decrement: #{content.match?(/decrement|setCount.*-|-.*setCount/i) ? '✅' : '❌'}"
    puts "  - Reset: #{content.match?(/reset|setCount.*0|setCount\(0\)/i) ? '✅' : '❌'}"
    puts "  - No Auth: #{!content.include?('Auth') && !content.include?('supabase') ? '✅' : '❌'}"
    puts "  - No Database: #{!content.include?('from(') && !content.include?('insert') ? '✅' : '❌'}"
  end
  
  # Test deployment
  puts "\n🌐 Testing Deployment:"
  begin
    preview_service = Deployment::FastPreviewService.new(app)
    result = preview_service.deploy_instant_preview!
    
    if result[:success]
      puts "✅ Deployment successful!"
      puts "  URL: #{result[:preview_url]}"
      
      # Test accessibility
      uri = URI(result[:preview_url])
      begin
        response = Net::HTTP.get_response(uri)
        puts "\n  Accessibility Check:"
        puts "    HTTP Status: #{response.code}"
        puts "    Content-Type: #{response['content-type']}"
        puts "    Response size: #{response.body.length} bytes"
        
        if response.code == '200'
          body = response.body
          puts "    Has HTML: #{body.include?('<html') ? '✅' : '❌'}"
          puts "    Has React: #{body.include?('react') || body.include?('React') ? '✅' : '❌'}"
          puts "    Has JS errors: #{body.include?('SyntaxError') || body.include?('ReferenceError') ? '❌' : '✅'}"
        end
      rescue => e
        puts "  ❌ Could not access preview: #{e.message}"
      end
    else
      puts "❌ Deployment failed: #{result[:error]}"
    end
  rescue => e
    puts "❌ Deployment error: #{e.message}"
  end
  
rescue => e
  puts "❌ Generation error: #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n" + "=" * 50
puts "📊 SUMMARY"
puts "=" * 50

if files.any?
  is_counter = main_file&.content&.match?(/useState.*count|count.*useState/i)
  has_no_auth = main_file && !main_file.content.include?('Auth') && !main_file.content.include?('supabase')
  
  puts "✅ Files Generated: #{files.count}"
  puts "#{is_counter ? '✅' : '❌'} Counter Implementation: #{is_counter ? 'YES' : 'NO'}"
  puts "#{has_no_auth ? '✅' : '❌'} No Auth/DB: #{has_no_auth ? 'YES' : 'NO'}"
  
  if is_counter && has_no_auth
    puts "\n🎉 SUCCESS: Generated correct counter app without todo bias!"
  else
    puts "\n⚠️ PARTIAL: App generated but may still have bias issues"
  end
else
  puts "❌ FAILED: No files generated"
end