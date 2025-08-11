#!/usr/bin/env ruby
# Test that the worker fix works

ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_V3_OPTIMIZED'] = 'true'

require_relative 'config/environment'
require 'net/http'
require 'uri'

puts "Testing Worker Fix"
puts "="*60

team = Team.first
app = App.create!(
  team: team,
  name: "Worker Fix Test",
  slug: "worker-fix-#{Time.now.to_i}",
  prompt: "Create a button that says Hello World",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

message = app.app_chat_messages.create!(
  role: 'user',
  content: app.prompt,
  user: team.memberships.first.user
)

puts "Created app ##{app.id}"
puts "Generating..."

# Run generation
ProcessAppUpdateJobV3.new.perform(message)

app.reload
puts "\nFiles: #{app.app_files.count}"
puts "Preview URL: #{app.preview_url}"

if app.preview_url
  puts "\nTesting preview..."
  sleep 2  # Give it a moment to propagate
  
  uri = URI.parse(app.preview_url)
  response = Net::HTTP.get_response(uri)
  
  puts "HTTP Status: #{response.code}"
  
  if response.code == '200'
    puts "✅ SUCCESS - Worker is fixed!"
  else
    puts "❌ Still broken - Status #{response.code}"
    puts "Body preview: #{response.body[0..500]}"
  end
end