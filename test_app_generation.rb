puts "Creating test app for team 8..."

# Get team 8
team = Team.find(8)
puts "Team: #{team.name}"

# Get first membership for creator
membership = team.memberships.first
unless membership
  puts "No memberships found for team 8"
  exit
end

# Create a new app with comprehensive prompt
app = team.apps.create!(
  creator: membership,
  name: "Todo App #{Time.current.to_i}",
  slug: "todo-app-#{SecureRandom.hex(6)}",
  prompt: "Create a beautiful todo app with task management, categories, priorities, due dates, and a modern UI with smooth animations. Include authentication and proper data persistence.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "Created app ##{app.id}: #{app.name}"
puts "Slug: #{app.slug}"
puts "Status: #{app.status}"

# Create initial chat message to trigger generation
message = app.app_chat_messages.create!(
  role: "user",
  content: "Generate a todo app with beautiful ui",
  user: membership.user
)

puts "Created message ##{message.id}"

# Trigger V3 Optimized orchestrator
puts "Triggering V3 Optimized generation..."
ProcessAppUpdateJobV3.perform_later(message)

puts "\n✅ App generation triggered successfully!"
puts "\nApp details:"
puts "  ID: #{app.id}"
puts "  Team: #{team.id}"
puts "  URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "  Preview URL: https://preview-#{app.id}.overskill.app"
puts "\nMonitor progress in the app editor!"