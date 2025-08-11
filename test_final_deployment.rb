#!/usr/bin/env ruby
# Final test of deployment with all fixes

ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_V3_OPTIMIZED'] = 'true'

require_relative 'config/environment'
require 'net/http'
require 'uri'

puts "="*60
puts "FINAL DEPLOYMENT TEST"
puts "="*60
puts "Testing: Generation → Deployment → Preview Access"
puts "="*60

team = Team.first
abort("No team found!") unless team

# Create a test app with a simple prompt
app = App.create!(
  team: team,
  name: "Final Deploy Test",
  slug: "final-deploy-#{Time.now.to_i}",
  prompt: "Create a todo app with beautiful UI",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

puts "\n✅ Created app ##{app.id}"

# Create message to trigger generation
message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "✅ Created message ##{message.id}"
puts "\n⏳ Generating and deploying..."

start_time = Time.now

begin
  # Run generation synchronously
  ProcessAppUpdateJobV3.new.perform(message)
  
  # Reload to get latest state
  app.reload
  
  generation_time = Time.now - start_time
  
  puts "\n" + "="*60
  puts "GENERATION COMPLETE (#{generation_time.round(1)}s)"
  puts "="*60
  
  puts "\n📊 Results:"
  puts "  Status: #{app.status}"
  puts "  Files: #{app.app_files.count}"
  puts "  Preview URL: #{app.preview_url || 'NOT SET'}"
  
  if app.app_files.any?
    puts "\n📁 Files created:"
    app.app_files.each do |file|
      puts "    #{file.path} (#{file.content.length} bytes)"
    end
  end
  
  # Test preview URL accessibility
  if app.preview_url
    puts "\n⏳ Testing preview URL (waiting 3s for propagation)..."
    sleep 3
    
    uri = URI.parse(app.preview_url)
    max_attempts = 3
    success = false
    
    max_attempts.times do |i|
      puts "\n  Attempt #{i+1}/#{max_attempts}..."
      
      begin
        response = Net::HTTP.get_response(uri)
        puts "    Status: #{response.code}"
        
        if response.code == '200'
          puts "    ✅ SUCCESS - Preview is accessible!"
          
          # Check content
          body = response.body
          if body.include?('<!DOCTYPE html')
            puts "    ✅ Contains HTML"
          end
          if body.include?('React')
            puts "    ✅ Contains React"
          end
          if body.include?('todo') || body.include?('Todo')
            puts "    ✅ Contains todo content"
          end
          
          success = true
          break
        elsif response.code == '500'
          # Check for worker error
          if response.body.include?('Error 1101')
            puts "    ❌ Worker JavaScript error"
            puts "    Error details: #{response.body.match(/<title>(.*?)<\/title>/)[1] rescue 'Unknown'}"
          else
            puts "    ⚠️ Server error (may need time to propagate)"
          end
        else
          puts "    ⚠️ Unexpected status: #{response.code}"
        end
        
        sleep 2 unless i == max_attempts - 1
      rescue => e
        puts "    ❌ Error: #{e.message}"
      end
    end
    
    puts "\n" + "="*60
    if success
      puts "🎉 COMPLETE SUCCESS!"
      puts "="*60
      puts "✅ App generated with #{app.app_files.count} files"
      puts "✅ Deployed to Cloudflare Workers"
      puts "✅ Preview is live and accessible"
      puts "\n🌐 View at: #{app.preview_url}"
    else
      puts "⚠️ PARTIAL SUCCESS"
      puts "="*60
      puts "✅ App generated with #{app.app_files.count} files"
      puts "✅ Deployed to Cloudflare Workers"
      puts "❌ Preview not accessible (worker error)"
      puts "\nThis indicates the worker script needs adjustment"
    end
  else
    puts "\n❌ No preview URL was set"
  end
  
rescue => e
  puts "\n❌ Test failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
ensure
  puts "\n📝 View in editor: http://localhost:3000/account/apps/#{app.id}/editor"
end