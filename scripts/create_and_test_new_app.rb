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

app_name = "Task Manager #{Time.current.to_i}"
prompt = "Create a modern task management app with:
1. User authentication (login/signup)
2. Task list with CRUD operations (create, read, update, delete)
3. Task properties: title, description, priority (low/medium/high), due date, status (pending/in-progress/completed)
4. Filter tasks by status and priority
5. Sort tasks by due date or priority
6. Mark tasks as complete with checkbox
7. Modern UI with Tailwind CSS and smooth animations
8. Responsive design for mobile and desktop"

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
  "src/App.tsx",
  "src/main.tsx",
  "src/components/Auth.tsx",
  "src/lib/supabase.ts",
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

# Test 4: Live app test
puts "\n🌐 Live App Test:"
if app.preview_url
  require 'net/http'
  require 'uri'
  
  begin
    uri = URI(app.preview_url)
    response = Net::HTTP.get_response(uri)
    
    live_checks = {
      "App accessible": response.code == '200',
      "HTML served": response.body.include?('<html'),
      "React root": response.body.include?('id="root"'),
      "JavaScript bundled": response.body.include?('.js'),
      "CSS bundled": response.body.include?('.css'),
      "Vite powered": response.body.include?('vite')
    }
    
    live_checks.each do |check, passed|
      status = passed ? "✅" : "❌"
      puts "  #{status} #{check}"
    end
    
    puts "  📊 Response size: #{response.body.length} bytes"
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