#!/usr/bin/env ruby
# Create a new app and run comprehensive testing
# Run with: bin/rails runner scripts/create_and_test_new_app.rb

require 'benchmark'

puts "=" * 60
puts "🔍 OverSkill React App Testing"
puts "=" * 60
puts "Starting at: #{Time.current}"

# Step 1: Create a new app
puts "\n[STEP 1] Creating new app..."
puts "-" * 40

team = Team.first || Team.create!(name: "Test Team")
creator = team.memberships.first || team.memberships.create!(
  user: User.first || User.create!(
    email: "test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  ),
  role_ids: ["admin"]
)

app_name = "TaskFlow Pro #{Time.current.to_i}"
prompt = "Create a comprehensive task management app with:

**Authentication System:**
- User login/signup with email and password
- Social login (Google and GitHub OAuth) 
- Secure password reset functionality
- Protected routes requiring authentication

**Task Management Features:**
- Full CRUD operations for tasks (create, read, update, delete)
- Task properties: title, description, priority (low/medium/high), due date, status (pending/in-progress/completed), category
- User-scoped data (each user sees only their own tasks)
- Real-time updates and data persistence with Supabase

**Advanced Functionality:**
- Filter tasks by status, priority, category, and due date
- Sort tasks by due date, priority, or creation date
- Mark tasks as complete with smooth animations
- Task search functionality
- Task categories/labels with color coding
- Bulk operations (select multiple tasks, bulk complete/delete)

**Modern UI/UX:**
- Professional design with Tailwind CSS
- Smooth animations and micro-interactions
- Dark/light theme support
- Responsive design optimized for mobile, tablet, and desktop
- Loading states and empty states
- Toast notifications for actions

**Technical Requirements:**
- React with TypeScript for type safety
- Supabase for database and authentication
- Modern React patterns (hooks, context)
- Error handling and loading states
- Performance optimization

app = team.apps.create!(
  name: app_name,
  prompt: prompt,
  status: 'generating',
  app_type: 'tool',
  framework: 'react',
  creator: creator
)

puts "✅ Created App ##{app.id}: #{app.name}"
puts "  Team: #{team.name}"
puts "  Creator: #{creator.user.email}"

# Step 2: Generate app with AI
puts "\n[STEP 2] Generating app with AI..."
puts "-" * 40

generation_time = Benchmark.measure do
  begin
    # Create initial chat message
    message = app.app_chat_messages.create!(
      user: creator.user,
      role: 'user',
      content: prompt
    )
    
    puts "📝 Created chat message ##{message.id}"
    
    # Process with AI orchestrator
    orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
    result = orchestrator.execute!
    
    if result[:success]
      puts "✅ AI generation successful"
      message.update!(status: 'completed', ai_response: result[:response])
      app.update!(status: 'generated')
    else
      puts "❌ AI generation failed: #{result[:error]}"
      message.update!(status: 'failed')
      app.update!(status: 'failed')
    end
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
    app.update!(status: 'failed')
  end
end

puts "⏱️  Generation time: #{generation_time.real.round(2)}s"

# Step 3: Deploy the app
puts "\n[STEP 3] Deploying app..."
puts "-" * 40

deploy_time = Benchmark.measure do
  if app.status == 'generated'
    begin
      deploy_service = Deployment::CloudflarePreviewService.new(app)
      result = deploy_service.update_preview!
      
      if result[:success]
        puts "✅ Deployment successful"
        puts "  URL: #{result[:preview_url]}"
        app.update!(
          status: 'published',
          preview_url: result[:preview_url],
          deployed_at: Time.current
        )
      else
        puts "❌ Deployment failed: #{result[:error]}"
      end
    rescue => e
      puts "❌ Deploy error: #{e.message}"
    end
  else
    puts "⚠️  Skipping deployment (app not generated)"
  end
end

puts "⏱️  Deployment time: #{deploy_time.real.round(2)}s"

# Step 4: Run comprehensive tests
puts "\n[STEP 4] Running comprehensive tests..."
puts "-" * 40

# Test 1: File structure
puts "\n📁 File Structure Test:"
expected_files = [
  "index.html",
  "package.json",
  "src/main.tsx",
  "src/lib/supabase.ts",
  "src/pages/auth/Login.tsx",
  "src/pages/auth/Signup.tsx", 
  "src/pages/auth/AuthCallback.tsx",
  "src/pages/auth/ForgotPassword.tsx",
  "src/components/auth/SocialButtons.tsx",
  "src/components/auth/ProtectedRoute.tsx",
  "src/hooks/useAuth.ts",
  "src/contexts/AuthContext.tsx",
  "tailwind.config.js",
  "vite.config.ts"
]

file_checks = {}
expected_files.each do |path|
  file = app.app_files.find_by(path: path)
  file_checks[path] = file.present?
  status = file.present? ? "✅" : "❌"
  puts "  #{status} #{path}"
end

# Test 2: Code quality
puts "\n🔍 Code Quality Test:"
app_tsx = app.app_files.find_by(path: "src/App.tsx")
if app_tsx
  quality_checks = {
    "TypeScript types": app_tsx.content.match?(/interface|type\s+\w+/),
    "React hooks": app_tsx.content.match?(/useState|useEffect/),
    "Authentication": app_tsx.content.include?("Auth"),
    "Task CRUD": app_tsx.content.match?(/create|update|delete/i),
    "Filtering": app_tsx.content.match?(/filter/i),
    "Sorting": app_tsx.content.match?(/sort/i),
    "Tailwind classes": app_tsx.content.match?(/className="[^"]*(?:flex|grid|p-|m-|bg-)/),
    "Responsive design": app_tsx.content.match?(/(?:sm:|md:|lg:|xl:)/),
    "User scoping": app_tsx.content.match?(/user_id|userId/),
    "Correct table name": app_tsx.content.include?("app_#{app.id}_tasks")
  }
  
  quality_checks.each do |check, passed|
    status = passed ? "✅" : "❌"
    puts "  #{status} #{check}"
  end
else
  puts "  ❌ App.tsx not found"
end

# Test 3: Database integration
puts "\n💾 Database Integration Test:"
table_service = Supabase::AutoTableService.new(app)
detected_tables = table_service.send(:detect_required_tables)

puts "  Detected #{detected_tables.count} table(s):"
detected_tables.each do |table|
  puts "    • #{table[:name]} (#{table[:columns].count} columns)"
  if table[:columns].any?
    puts "      Columns: #{table[:columns].map { |c| c[:name] }.first(5).join(', ')}"
  end
end

# Test 4: OAuth integration test
puts "\n🔐 OAuth Integration Test:"
oauth_checks = {}
if app.preview_url
  begin
    require 'net/http'
    require 'uri'
    
    # Check main app
    uri = URI(app.preview_url)
    response = Net::HTTP.get_response(uri)
    oauth_checks["Main app accessible"] = response.code == '200'
    
    # Check auth pages exist in HTML
    if response.code == '200'
      body = response.body
      oauth_checks["Auth components loaded"] = body.include?('Auth') || body.include?('Login') || body.include?('auth')
      oauth_checks["Supabase client"] = body.include?('supabase') || body.include?('createClient')
      oauth_checks["OAuth providers"] = body.include?('google') || body.include?('github') || body.include?('oauth')
      oauth_checks["React router"] = body.include?('router') || body.include?('Route')
    end
    
    # Test auth-specific routes
    auth_routes = ['/login', '/signup', '/auth/callback']
    auth_routes.each do |route|
      begin
        auth_uri = URI("#{app.preview_url.chomp('/')}#{route}")
        auth_response = Net::HTTP.get_response(auth_uri)
        oauth_checks["#{route} accessible"] = auth_response.code == '200'
      rescue => e
        oauth_checks["#{route} accessible"] = false
      end
    end
    
  rescue => e
    oauth_checks["OAuth test error"] = "#{e.message}"
  end
else
  oauth_checks["No preview URL"] = false
end

oauth_checks.each do |check, result|
  if result.is_a?(String) && result.include?("error")
    puts "  ❌ #{check}: #{result}"
  else
    status = result ? "✅" : "❌"
    puts "  #{status} #{check}"
  end
end

# Test 5: Live app performance test
puts "\n🌐 Live App Performance Test:"
if app.preview_url
  require 'net/http'
  require 'uri'
  require 'benchmark'
  
  begin
    # Performance timing
    load_time = Benchmark.measure do
      uri = URI(app.preview_url)
      @response = Net::HTTP.get_response(uri)
    end
    
    live_checks = {
      "App accessible": @response.code == '200',
      "HTML served": @response.body.include?('<html'),
      "React root": @response.body.include?('id="root"'),
      "JavaScript bundled": @response.body.include?('.js'),
      "CSS bundled": @response.body.include?('.css'),
      "Vite powered": @response.body.include?('vite'),
      "TypeScript support": @response.body.include?('tsx') || @response.body.include?('typescript')
    }
    
    live_checks.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "  #{status} #{check}"
    end
    
    puts "  📊 Response size: #{@response.body.length} bytes"
    puts "  ⏱️  Load time: #{(load_time.real * 1000).round(0)}ms"
  rescue => e
    puts "  ❌ Error accessing app: #{e.message}"
  end
else
  puts "  ❌ No preview URL available"
end

# Step 5: Performance summary
puts "\n" + "=" * 60
puts "📊 PERFORMANCE SUMMARY"
puts "=" * 60

total_time = generation_time.real + deploy_time.real
puts "⏱️  Timing Breakdown:"
puts "  AI Generation:  #{generation_time.real.round(2)}s"
puts "  Deployment:     #{deploy_time.real.round(2)}s"
puts "  ─────────────────────"
puts "  TOTAL TIME:     #{total_time.round(2)}s"

# Calculate success metrics
total_checks = file_checks.count + (quality_checks&.count || 0) + (live_checks&.count || 0)
passed_checks = file_checks.values.count(true) + 
                (quality_checks&.values&.count(true) || 0) + 
                (live_checks&.values&.count(true) || 0)

success_rate = total_checks > 0 ? (passed_checks.to_f / total_checks * 100).round(1) : 0

puts "\n✅ Test Results:"
puts "  Checks Passed:  #{passed_checks}/#{total_checks}"
puts "  Success Rate:   #{success_rate}%"

# Final verdict
puts "\n🎯 Final Verdict:"
if success_rate >= 90
  puts "  🏆 EXCELLENT! App meets all quality standards"
elsif success_rate >= 75
  puts "  ✅ GOOD! App is functional with minor issues"
elsif success_rate >= 50
  puts "  ⚠️  ACCEPTABLE! App needs improvements"
else
  puts "  ❌ NEEDS WORK! Significant issues detected"
end

# Performance rating
puts "\n⚡ Performance Rating:"
if total_time < 30
  puts "  🚀 BLAZING FAST! Under 30 seconds"
elsif total_time < 60
  puts "  ⚡ FAST! Under 1 minute"
elsif total_time < 120
  puts "  ✅ GOOD! Under 2 minutes"
else
  puts "  ⚠️  SLOW! Over 2 minutes"
end

# App details
puts "\n📱 App Details:"
puts "  ID:     #{app.id}"
puts "  Name:   #{app.name}"
puts "  Status: #{app.status}"
puts "  Files:  #{app.app_files.count}"
puts "  URL:    #{app.preview_url || 'Not deployed'}"

# Recommendations
puts "\n💡 Recommendations:"
if !file_checks.values.all?
  puts "  • Some essential files are missing"
end
if quality_checks && !quality_checks["TypeScript types"]
  puts "  • Add TypeScript type definitions"
end
if quality_checks && !quality_checks["User scoping"]
  puts "  • Implement user data isolation"
end
if live_checks && !live_checks["App accessible"]
  puts "  • Check deployment configuration"
end
if total_time > 60
  puts "  • Optimize AI generation for faster results"
end

puts "\nCompleted at: #{Time.current}"
puts "=" * 60