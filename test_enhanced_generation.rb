puts "Testing enhanced V3 Optimized generation for team 8..."

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
  name: "TaskMaster Pro #{Time.current.to_i}",
  slug: "taskmaster-#{SecureRandom.hex(6)}",
  prompt: "Create a professional task management application with user authentication (email and social login), task CRUD operations with categories and priorities, real-time updates, beautiful modern UI with dark mode, search and filtering, due date reminders, and full Supabase integration. Use React Router for navigation between login, dashboard, settings, and profile pages.",
  app_type: "saas",
  framework: "react",
  status: "draft",
  base_price: 0,
  visibility: "private"
)

puts "Created app ##{app.id}: #{app.name}"
puts "Slug: #{app.slug}"
puts "Status: #{app.status}"

puts "\n✅ App created - auto-generation will trigger"
puts "\nApp details:"
puts "  ID: #{app.id}"
puts "  Team: #{team.id}"
puts "  URL: https://dev.overskill.app/account/apps/#{app.to_param}/editor"
puts "  Preview URL: https://preview-#{app.id}.overskill.app"
puts "\n🚀 Monitor the generation to see if comprehensive files are created!"
puts "\nExpected files:"
puts "  - index.html (with React Router and Supabase CDN)"
puts "  - src/App.jsx (main app with router)"
puts "  - src/lib/supabase.js"
puts "  - src/lib/router.jsx"
puts "  - src/pages/Home.jsx"
puts "  - src/pages/auth/Login.jsx"
puts "  - src/pages/auth/SignUp.jsx"
puts "  - src/pages/Dashboard.jsx"
puts "  - src/components/auth/Auth.jsx"
puts "  - src/components/auth/SocialButtons.jsx"
puts "  - src/components/auth/ProtectedRoute.jsx"
puts "  - And more..."