puts "Creating test app for team 8 (auto-generation only)..."

# Get team 8
team = Team.find(8)
puts "Team: #{team.name}"

# Get first membership for creator
membership = team.memberships.first
unless membership
  puts "No memberships found for team 8"
  exit
end

# Create a new app - the after_create callback will handle generation
app = team.apps.create!(
  creator: membership,
  name: "Advanced Todo #{Time.current.to_i}",
  slug: "advanced-todo-#{SecureRandom.hex(6)}",
  prompt: "Create a comprehensive todo application with these features: user authentication with email and social login (Google/GitHub), task management with CRUD operations, categories and tags, priority levels, due dates, search and filtering, beautiful modern UI with smooth animations, dark mode support, mobile responsive design, proper data persistence with Supabase integration. Use React Router for multi-page navigation with login, dashboard, and settings pages.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "Created app ##{app.id}: #{app.name}"
puts "Slug: #{app.slug}"
puts "Status: #{app.status}"

puts "\n✅ App created - auto-generation should trigger via after_create callback"
puts "\nApp details:"
puts "  ID: #{app.id}"
puts "  Team: #{team.id}"
puts "  URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "  Preview URL: https://preview-#{app.id}.overskill.app"
puts "\nThe after_create callback will handle generation automatically!"