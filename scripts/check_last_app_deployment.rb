#!/usr/bin/env ruby
# Script to check the last app's deployment configuration

require_relative '../config/environment'

puts "\n🔍 Checking last app's deployment configuration..."
puts "=" * 80

app = App.last

if app.nil?
  puts "❌ No apps found in database"
  exit
end

puts "\n📱 App Details:"
puts "  ID: #{app.id}"
puts "  Name: #{app.name}"
puts "  Created: #{app.created_at}"
puts "  Status: #{app.status}"

puts "\n🔗 URL Fields:"
puts "  slug: #{app.slug.inspect}"
puts "  subdomain: #{app.subdomain.inspect}"
puts "  deployment_url: #{app.deployment_url.inspect}"
puts "  preview_url: #{app.preview_url.inspect}"
puts "  production_url: #{app.production_url.inspect}"
puts "  published_url: #{app.published_url.inspect}"

puts "\n📅 Deployment Timestamps:"
puts "  deployed_at: #{app.deployed_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"
puts "  preview_updated_at: #{app.preview_updated_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"
puts "  last_deployed_at: #{app.last_deployed_at&.strftime('%Y-%m-%d %H:%M:%S') || 'Never'}"

# Check if subdomain matches what's in deployment_url
if app.deployment_url.present?
  expected_url = "https://#{app.subdomain}.overskill.app"
  matches = app.deployment_url == expected_url
  
  puts "\n🎯 URL Consistency Check:"
  puts "  Expected URL (from subdomain): #{expected_url}"
  puts "  Actual deployment_url: #{app.deployment_url}"
  puts "  Match: #{matches ? '✅ YES' : '❌ NO'}"
  
  if !matches && app.deployment_url.include?('.overskill.app')
    # Extract subdomain from deployment_url
    actual_subdomain = app.deployment_url.match(/https:\/\/([^.]+)\.overskill\.app/)[1] rescue nil
    puts "  Subdomain in URL: #{actual_subdomain.inspect}"
  end
end

# Check recent apps to see if this is a pattern
puts "\n📊 Recent Apps Comparison (last 5):"
puts "%-10s %-30s %-20s %-20s %s" % ["ID", "Name", "Subdomain", "Slug", "Deployment URL Match?"]
puts "-" * 100

App.order(created_at: :desc).limit(5).each do |recent_app|
  expected = "https://#{recent_app.subdomain}.overskill.app"
  match = recent_app.deployment_url == expected ? "✅" : "❌"
  match = "🔸 No URL" if recent_app.deployment_url.blank?
  
  puts "%-10s %-30s %-20s %-20s %s" % [
    recent_app.id,
    recent_app.name.truncate(30),
    recent_app.subdomain || "(none)",
    recent_app.slug || "(none)",
    match
  ]
end

puts "\n" + "=" * 80
