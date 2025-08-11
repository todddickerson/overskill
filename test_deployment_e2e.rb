#!/usr/bin/env ruby
# End-to-end test: App generation + deployment + UI update

ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_V3_OPTIMIZED'] = 'true'
ENV['AUTO_DEPLOY_AFTER_GENERATION'] = 'true'
ENV['VERBOSE_AI_LOGGING'] = 'true'

require_relative 'config/environment'

puts "="*60
puts "End-to-End Deployment Test"
puts "="*60
puts "Testing: Generation → Files → Deployment → Preview URL"
puts "="*60

team = Team.first
abort("No team found!") unless team

# Create test app
app = App.create!(
  team: team,
  name: "E2E Deployment Test",
  slug: "e2e-deploy-#{Time.now.to_i}",
  prompt: "Create a colorful welcome page with a button that changes the background color when clicked",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

puts "\n✅ Created app ##{app.id}"
puts "Initial preview_url: #{app.preview_url || 'NOT SET'}"

# Create message to trigger generation
message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "✅ Created message ##{message.id}"
puts "\n⏳ Starting generation and deployment..."
puts "-"*40

start_time = Time.now

begin
  # Run synchronously to track progress
  ProcessAppUpdateJobV3.new.perform(message)
  
  # Reload app to get latest state
  app.reload
  
  duration = Time.now - start_time
  
  puts "\n" + "="*60
  puts "RESULTS (#{duration.round(1)} seconds)"
  puts "="*60
  
  puts "\n📊 App Status:"
  puts "  Status: #{app.status}"
  puts "  Deployment Status: #{app.deployment_status || 'NOT SET'}"
  
  puts "\n📁 Files Created: #{app.app_files.count}"
  if app.app_files.any?
    app.app_files.each do |file|
      puts "  - #{file.path} (#{file.content.length} bytes)"
    end
  end
  
  puts "\n🌐 Deployment URLs:"
  puts "  Preview URL: #{app.preview_url || 'NOT SET'}"
  puts "  Preview Updated: #{app.preview_updated_at || 'NEVER'}"
  puts "  Production URL: #{app.production_url || 'NOT SET'}"
  
  # Test if preview URL is accessible
  if app.preview_url
    puts "\n🔍 Testing Preview URL..."
    require 'net/http'
    require 'uri'
    
    begin
      uri = URI.parse(app.preview_url)
      response = Net::HTTP.get_response(uri)
      puts "  HTTP Status: #{response.code}"
      puts "  Response Size: #{response.body.length} bytes"
      
      if response.code == '200'
        puts "  ✅ Preview is LIVE and accessible!"
      else
        puts "  ⚠️ Preview URL returned status #{response.code}"
      end
    rescue => e
      puts "  ❌ Could not access preview: #{e.message}"
    end
  end
  
  puts "\n" + "="*60
  puts "TEST COMPLETE"
  puts "="*60
  
  if app.preview_url && app.app_files.count > 0
    puts "✅ SUCCESS: App generated, deployed, and accessible!"
    puts "View at: #{app.preview_url}"
  else
    puts "⚠️ PARTIAL SUCCESS: Check the details above"
  end
  
rescue => e
  puts "\n❌ Test failed: #{e.message}"
  puts e.backtrace.first(5).join("\n")
ensure
  puts "\nView in editor: http://localhost:3000/account/apps/#{app.id}/editor"
end