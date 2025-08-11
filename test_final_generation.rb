puts "Final test of V3 Optimized generation with all fixes..."

# Get team 8
team = Team.find(8)
puts "Team: #{team.name}"

# Get first membership for creator
membership = team.memberships.first
unless membership
  puts "No memberships found for team 8"
  exit
end

# Create a new app with clear requirements
app = team.apps.create!(
  creator: membership,
  name: "Ultimate Todo #{Time.current.to_i}",
  slug: "ultimate-todo-#{SecureRandom.hex(6)}",
  prompt: "Create a complete todo application with these features: user authentication with email login and Google/GitHub OAuth, full CRUD operations for tasks, categories and priority levels, due dates with reminders, search and filtering, beautiful modern UI with animations, dark mode support, mobile responsive design. Use React Router for navigation between login, signup, dashboard, and settings pages. Include Supabase for database persistence.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "Created app ##{app.id}: #{app.name}"
puts "Slug: #{app.slug}"
puts "Status: #{app.status}"

puts "\n✅ App created - monitoring generation..."
puts "\nApp details:"
puts "  ID: #{app.id}"
puts "  Team: #{team.id}"
puts "  URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "  Preview URL: https://preview-#{app.id}.overskill.app"
puts "\n🚀 This should create a comprehensive app with:"
puts "  - Full authentication system"
puts "  - React Router navigation"
puts "  - Supabase integration"
puts "  - Multiple pages and components"
puts "  - Professional UI with Tailwind"