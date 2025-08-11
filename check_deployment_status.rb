#!/usr/bin/env ruby
# Check deployment status for recent apps

require_relative 'config/environment'

puts "="*60
puts "Checking Recent App Deployments"
puts "="*60

# Get recent apps from the last hour
recent_apps = App.where('created_at > ?', 1.hour.ago).order(created_at: :desc).limit(5)

if recent_apps.empty?
  puts "No apps created in the last hour"
else
  recent_apps.each do |app|
    puts "\nApp ##{app.id}: #{app.name}"
    puts "  Created: #{app.created_at}"
    puts "  Status: #{app.status}"
    puts "  AI Model: #{app.ai_model || 'default'}"
    puts "  Files: #{app.app_files.count}"
    puts "  Preview URL: #{app.preview_url || 'NOT SET'}"
    puts "  Production URL: #{app.production_url || 'NOT SET'}"
    puts "  Deployment Status: #{app.deployment_status || 'NOT SET'}"
    puts "  Preview Updated: #{app.preview_updated_at || 'NEVER'}"
    
    # Check if V3 optimized was used
    last_message = app.app_chat_messages.where(role: 'user').last
    if last_message
      puts "  Last user message: #{last_message.created_at}"
    end
  end
end

puts "\n" + "="*60
puts "Environment Variables:"
puts "  AUTO_DEPLOY_AFTER_GENERATION: #{ENV['AUTO_DEPLOY_AFTER_GENERATION'] || 'NOT SET'}"
puts "  USE_V3_ORCHESTRATOR: #{ENV['USE_V3_ORCHESTRATOR'] || 'NOT SET'}"
puts "  USE_V3_OPTIMIZED: #{ENV['USE_V3_OPTIMIZED'] || 'NOT SET'}"
puts "="*60