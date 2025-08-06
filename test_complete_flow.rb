#!/usr/bin/env ruby
require_relative 'config/environment'

# Test complete generation flow
puts "\n=== Testing Complete Generation Flow ==="

# Setup
team = Team.first || Team.create!(name: "Test Team")
membership = team.memberships.first || team.memberships.create!(
  user: User.first || User.create!(email: "test@example.com", password: "password"),
  role_ids: ["admin"]
)

# Find or create app
app = App.find_by(slug: "test-counter-app") || App.create!(
  team: team,
  creator: membership,
  name: "Test Counter App",
  slug: "test-counter-app-#{Time.now.to_i}",
  prompt: "Create a counter app",
  app_type: "saas",
  framework: "react",
  status: "generating",
  base_price: 0
)

# Clear files
app.app_files.destroy_all
puts "App: #{app.name} (#{app.id})"

# Create message
message = app.app_chat_messages.create!(
  user: membership.user,
  role: "user",
  content: "Create a simple counter app with increment and decrement buttons"
)

puts "Message: #{message.content}"

# Test generation
puts "\nRunning UnifiedAiCoordinator..."
coordinator = Ai::UnifiedAiCoordinator.new(app, message)

begin
  coordinator.execute!
  
  app.reload
  puts "\n✅ Generation successful!"
  puts "Status: #{app.status}"
  puts "Files created: #{app.app_files.count}"
  
  # List files
  app.app_files.each do |file|
    puts "  - #{file.path} (#{file.content.size} bytes)"
  end
  
  # Check critical files
  puts "\nCritical files:"
  critical = ['index.html', 'src/App.tsx', 'package.json']
  critical.each do |path|
    file = app.app_files.find_by(path: path)
    if file
      puts "  ✅ #{path} exists"
    else
      puts "  ❌ #{path} missing"
    end
  end
  
rescue => e
  puts "\n❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts "\n=== Complete ===="