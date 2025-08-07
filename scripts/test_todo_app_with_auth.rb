#!/usr/bin/env ruby
# Test script for generating a todo app with full authentication and per-user todos
# Run with: bin/rails runner scripts/test_todo_app_with_auth.rb

require 'securerandom'

puts "=" * 80
puts "🚀 TODO APP WITH AUTHENTICATION TEST"
puts "=" * 80
puts "This test will create a fully functional todo app with:"
puts "- User authentication (login/signup)"
puts "- Per-user todo lists"
puts "- Social login (Google/GitHub)"
puts "- Protected routes"
puts "- Real-time database sync"
puts "=" * 80

# Find or create a test user and team
user = User.first
unless user
  puts "Creating test user..."
  user = User.create!(
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  )
end

team = user.teams.first || Team.create!(name: "Test Team")
membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, role_ids: ["admin"])

puts "\n📋 Using team: #{team.name}"
puts "👤 Using user: #{user.email}"

# Create a new app for testing
app_name = "Todo App #{Time.now.strftime('%H%M%S')}"
prompt = <<~PROMPT
  Create a modern todo application with user authentication. 

  Requirements:
  - User authentication with login/signup pages
  - Each user has their own private todo list
  - Users can only see and edit their own todos
  - Todo items should have: title, description, completed status, created date
  - Clean, modern UI with Tailwind CSS
  - Dashboard shows user's todos with ability to add, edit, delete, and mark complete
  - Use React Router for navigation
  - Social login with Google and GitHub
  
  Database:
  - Store todos in Supabase with user_id field
  - Each todo belongs to the authenticated user
  - Use Row Level Security to ensure users only see their own todos

  The app should feel professional and responsive, similar to popular todo apps like Todoist or Any.do.
PROMPT

puts "\n📝 Creating app with prompt:"
puts prompt.lines.first(3).join
puts "..."

# Create the app with creator
app = App.create!(
  team: team,
  creator: membership,  # Set the creator to the membership
  name: app_name,
  prompt: prompt,
  app_type: 'saas',
  framework: 'react',
  status: 'generating'
)

puts "\n✅ Created app ##{app.id}: #{app.name}"

# Create app generation record
app_generation = AppGeneration.create!(
  team: team,  # Add team
  app: app,
  prompt: prompt,
  status: 'pending',
  started_at: Time.current
)

puts "📦 Created AppGeneration ##{app_generation.id}"

# Create initial chat message for context
chat_message = AppChatMessage.create!(
  app: app,
  user: user,
  content: prompt,
  role: 'user'  # Use 'role' field instead of 'is_ai_response'
)

puts "💬 Created initial chat message ##{chat_message.id}"

# Trigger the generation job
puts "\n🔄 Starting app generation..."
puts "This will:"
puts "1. Generate app code with AI"
puts "2. Include auth templates automatically"
puts "3. Create database tables"
puts "4. Set up auth settings"
puts "5. Build with Vite"
puts "6. Deploy to Cloudflare"

# Run the generation job synchronously for testing
begin
  job = AppGenerationJob.new
  job.perform(app_generation)
  
  # Reload to get latest status
  app.reload
  app_generation.reload
  
  if app.status == 'generated' || app.status == 'ready'
    puts "\n✅ App generated successfully!"
    
    # Check if auth settings were created
    if app.app_auth_setting
      puts "\n🔐 Auth Settings Created:"
      settings = app.app_auth_setting
      puts "  Visibility: #{settings.visibility}"
      puts "  Requires Auth: #{settings.requires_authentication?}"
      puts "  Allow Signups: #{settings.allow_signups}"
      puts "  Providers: #{settings.allowed_providers.join(', ')}"
      puts "  Email Domains: #{settings.allowed_email_domains.any? ? settings.allowed_email_domains.join(', ') : 'All allowed'}"
    else
      puts "\n⚠️ No auth settings created (will create now)"
      app.create_app_auth_setting!(
        visibility: 'public_login_required',
        allowed_providers: ['email', 'google', 'github'],
        allowed_email_domains: [],
        require_email_verification: false,
        allow_signups: true,
        allow_anonymous: false
      )
      puts "✅ Auth settings created"
    end
    
    # Check files created
    puts "\n📁 Files Generated:"
    auth_files = app.app_files.where("path LIKE '%auth%' OR path LIKE '%Auth%' OR path LIKE '%login%' OR path LIKE '%Login%'")
    if auth_files.any?
      auth_files.each do |file|
        puts "  ✅ #{file.path}"
      end
    else
      puts "  ⚠️ No auth files found - checking all files..."
      app.app_files.limit(10).each do |file|
        puts "  - #{file.path}"
      end
    end
    
    # Check for React Router
    router_files = app.app_files.where("content LIKE '%react-router%' OR content LIKE '%Routes%' OR content LIKE '%BrowserRouter%'")
    if router_files.any?
      puts "\n🔀 React Router Integration:"
      router_files.limit(3).each do |file|
        puts "  ✅ #{file.path} (contains routing)"
      end
    end
    
    # Check for Supabase integration
    supabase_files = app.app_files.where("content LIKE '%supabase%' OR content LIKE '%createClient%'")
    if supabase_files.any?
      puts "\n🗄️ Supabase Integration:"
      supabase_files.limit(3).each do |file|
        puts "  ✅ #{file.path} (contains Supabase)"
      end
    end
    
    # Deploy to preview
    puts "\n🚀 Deploying to Cloudflare..."
    preview_service = Deployment::CloudflarePreviewService.new(app)
    result = preview_service.update_preview!
    
    if result[:success]
      puts "✅ Deployed successfully!"
      puts "\n🌐 Preview URLs:"
      puts "  Main: #{result[:preview_url]}"
      puts "  Custom: #{result[:custom_domain_url]}" if result[:custom_domain_url]
      
      puts "\n📱 Test the App:"
      puts "  1. Visit: #{result[:preview_url]}"
      puts "  2. Click 'Sign Up' to create an account"
      puts "  3. Try social login with GitHub"
      puts "  4. Create some todos"
      puts "  5. Verify todos are private to your user"
      puts "  6. Test logout and login"
      
      puts "\n🔍 Check Auth Features:"
      puts "  - Login: #{result[:preview_url]}/login"
      puts "  - Signup: #{result[:preview_url]}/signup"
      puts "  - Dashboard: #{result[:preview_url]}/dashboard"
      puts "  - Forgot Password: #{result[:preview_url]}/forgot-password"
      
    else
      puts "❌ Deployment failed: #{result[:error]}"
    end
    
    # Show app editor URL
    puts "\n✏️ App Editor:"
    puts "  http://localhost:3000/account/apps/#{app.to_param}/editor"
    
    # Test database tables
    puts "\n🗄️ Checking Database Tables..."
    begin
      table_service = Supabase::AutoTableService.new(app)
      tables = table_service.list_app_tables
      
      if tables.any?
        puts "✅ Database tables created:"
        tables.each do |table|
          puts "  - #{table}"
        end
      else
        puts "⚠️ No tables found yet (will be created on first use)"
      end
    rescue => e
      puts "⚠️ Could not check tables: #{e.message}"
    end
    
    # Summary
    puts "\n" + "=" * 80
    puts "✅ TODO APP TEST COMPLETE!"
    puts "=" * 80
    puts "\n📊 Summary:"
    puts "  App ID: #{app.id}"
    puts "  Name: #{app.name}"
    puts "  Status: #{app.status}"
    puts "  Files: #{app.app_files.count}"
    puts "  Auth: #{app.app_auth_setting ? 'Configured' : 'Not configured'}"
    puts "  Preview: #{app.preview_url || 'Not deployed'}"
    puts "\n🎉 The todo app with authentication has been successfully generated!"
    
  else
    puts "\n❌ App generation failed!"
    puts "Status: #{app.status}"
    puts "Error: #{app_generation.error_message}" if app_generation.error_message
  end
  
rescue => e
  puts "\n❌ Error during generation: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  
  # Try to show any partial results
  app.reload if app.persisted?
  puts "\nApp status: #{app.status}" if app.persisted?
  puts "Files created: #{app.app_files.count}" if app.persisted?
end

puts "\n" + "=" * 80
puts "Test script completed at #{Time.current}"
puts "=" * 80