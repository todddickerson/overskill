#!/usr/bin/env ruby
# Test GenerateAppNameJob on the most recent app

require_relative 'config/environment'

puts "🔍 Finding the most recent app to test naming..."

# Find the most recent app
latest_app = App.order(created_at: :desc).first

if latest_app.nil?
  puts "❌ No apps found in the database"
  exit 1
end

puts "📱 Found latest app:"
puts "   ID: #{latest_app.id}"
puts "   Current Name: '#{latest_app.name}'"
puts "   Prompt: '#{latest_app.prompt&.truncate(100)}'"
puts "   Created: #{latest_app.created_at}"
puts "   Name Generated At: #{latest_app.name_generated_at || 'Never'}"

# Check if naming has already been done
if latest_app.name_generated_at.present?
  puts "\n⚠️  This app already has a generated name. Testing anyway..."
  # Reset the name_generated_at to allow re-generation
  latest_app.update_column(:name_generated_at, nil)
  puts "   Reset name_generated_at to allow re-testing"
end

puts "\n🚀 Running GenerateAppNameJob..."
puts "   Job will use: gpt-4o via direct OpenAI API"

# Test the job synchronously to see immediate results
begin
  job = GenerateAppNameJob.new
  job.perform(latest_app.id)
  
  # Reload the app to see if the name was updated
  latest_app.reload
  
  puts "\n✅ Job completed successfully!"
  puts "📝 Results:"
  puts "   Old name: '#{latest_app.name}'"
  puts "   Name Generated At: #{latest_app.name_generated_at}"
  
  if latest_app.name_generated_at.present?
    puts "🎉 SUCCESS: App name was generated!"
    puts "   ✅ No 'max_tokens' parameter errors"
    puts "   ✅ No 'undefined method split for nil' errors"
    puts "   ✅ Direct OpenAI API (gpt-4o) working correctly"
  else
    puts "❌ FAILED: name_generated_at was not updated"
  end
  
rescue => e
  puts "\n❌ Job failed with error:"
  puts "   #{e.class}: #{e.message}"
  puts "   #{e.backtrace.first}"
  
  # Check common failure patterns
  if e.message.include?('max_tokens')
    puts "\n🔍 This looks like the old max_tokens parameter error"
  elsif e.message.include?('split')
    puts "\n🔍 This looks like the nil content split error"
  elsif e.message.include?('OpenAI')
    puts "\n🔍 This is an OpenAI API related error"
  end
end

puts "\n🧹 Test completed!"
