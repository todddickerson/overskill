#!/usr/bin/env ruby
# Full test of App 57 regeneration with automatic table creation
# Run with: bin/rails runner scripts/test_full_regeneration.rb

require 'benchmark'

puts "=" * 60
puts "FULL APP REGENERATION TEST WITH AUTO TABLES"
puts "=" * 60
puts "Starting at: #{Time.current}"

app = App.find(57)
puts "\n📱 App: #{app.name} (ID: #{app.id})"
puts "  Team: #{app.team.name}"
puts "  Current status: #{app.status}"
puts "  Files: #{app.app_files.count}"

# Step 1: Clear existing tables metadata to test fresh creation
puts "\n[STEP 1] Clearing existing table metadata..."
app.app_tables.destroy_all
puts "✅ Cleared #{app.app_tables.count} tables"

# Step 2: Create a regeneration request via chat
puts "\n[STEP 2] Creating regeneration chat message..."
creator = app.creator || app.team.memberships.first

regeneration_message = app.app_chat_messages.create!(
  user: creator.user,
  role: 'user',
  content: "Please regenerate this todo app with the following features:
  
1. User authentication (login/signup)
2. Todo list with add, edit, delete, and mark complete
3. User-scoped data (each user sees only their todos)
4. Modern, clean UI with Tailwind CSS
5. Real-time updates when todos change

Make sure to use the table name app_57_todos and include proper authentication."
)

puts "✅ Created chat message ##{regeneration_message.id}"

# Step 3: Process with orchestrator and measure time
puts "\n[STEP 3] Processing with AI orchestrator..."
puts "⏱️  Starting benchmark..."

benchmark_result = Benchmark.measure do
  begin
    # Use the V2 orchestrator for better results
    orchestrator = Ai::AppUpdateOrchestratorV2.new(regeneration_message)
    
    # Mark app as generating
    app.update!(status: 'generating')
    
    # Execute orchestration
    result = orchestrator.execute!
    
    if result[:success]
      puts "✅ AI generation successful"
      puts "  Files updated: #{result[:files_updated]}" if result[:files_updated]
      
      regeneration_message.update!(
        status: 'completed',
        ai_response: result[:response]
      )
      
      app.update!(status: 'generated')
    else
      puts "❌ AI generation failed: #{result[:error]}"
      regeneration_message.update!(
        status: 'failed'
      )
    end
  rescue => e
    puts "❌ Orchestration error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
end

puts "\n⏱️  AI Generation Time: #{benchmark_result.real.round(2)} seconds"

# Step 4: Test automatic table creation
puts "\n[STEP 4] Testing automatic table creation..."
table_benchmark = Benchmark.measure do
  begin
    table_service = Supabase::AutoTableService.new(app)
    result = table_service.ensure_tables_exist!
    
    if result[:success]
      puts "✅ Tables created automatically:"
      result[:tables].each do |table|
        puts "    - #{table}"
      end
    else
      puts "❌ Table creation failed: #{result[:error]}"
    end
  rescue => e
    puts "❌ Table service error: #{e.message}"
  end
end

puts "⏱️  Table Creation Time: #{table_benchmark.real.round(2)} seconds"

# Step 5: Deploy the app
puts "\n[STEP 5] Deploying to Cloudflare..."
deploy_benchmark = Benchmark.measure do
  begin
    deploy_service = Deployment::CloudflarePreviewService.new(app)
    result = deploy_service.update_preview!
    
    if result[:success]
      puts "✅ Deployment successful"
      puts "  Preview URL: #{result[:preview_url]}"
      app.update!(
        status: 'published',
        preview_url: result[:preview_url],
        deployed_at: Time.current
      )
    else
      puts "❌ Deployment failed: #{result[:error]}"
    end
  rescue => e
    puts "❌ Deployment error: #{e.message}"
  end
end

puts "⏱️  Deployment Time: #{deploy_benchmark.real.round(2)} seconds"

# Step 6: Verify results
puts "\n[STEP 6] Verification..."

# Check files
auth_file = app.app_files.find_by(path: "src/components/Auth.tsx")
app_tsx = app.app_files.find_by(path: "src/App.tsx")

verification_results = {
  auth_component: auth_file.present?,
  app_integration: app_tsx && app_tsx.content.include?('Auth'),
  user_scoping: app_tsx && app_tsx.content.include?('user_id'),
  correct_table: app_tsx && app_tsx.content.include?('app_57_todos'),
  tables_created: app.app_tables.any?,
  deployment_url: app.preview_url.present?
}

puts "✅ Verification Results:"
verification_results.each do |check, passed|
  status = passed ? "✅" : "❌"
  puts "  #{status} #{check.to_s.humanize}: #{passed}"
end

# Step 7: Database metadata check
puts "\n[STEP 7] Database Metadata..."
if app.app_tables.any?
  app.app_tables.each do |table|
    puts "📊 Table: #{table.name}"
    puts "  Display name: #{table.display_name}"
    puts "  Scope: #{table.scope_type}"
    puts "  Columns: #{table.app_table_columns.count}"
    table.app_table_columns.limit(5).each do |col|
      puts "    - #{col.name} (#{col.column_type})"
    end
  end
else
  puts "⚠️  No tables tracked in metadata"
end

# Final Summary
puts "\n" + "=" * 60
puts "BENCHMARK SUMMARY"
puts "=" * 60

total_time = benchmark_result.real + table_benchmark.real + deploy_benchmark.real

puts "⏱️  Timing Breakdown:"
puts "  AI Generation:    #{benchmark_result.real.round(2)}s"
puts "  Table Creation:   #{table_benchmark.real.round(2)}s"
puts "  Deployment:       #{deploy_benchmark.real.round(2)}s"
puts "  ─────────────────────────"
puts "  TOTAL TIME:       #{total_time.round(2)}s"

puts "\n📊 Success Metrics:"
success_count = verification_results.values.count(true)
total_checks = verification_results.values.count
success_rate = (success_count.to_f / total_checks * 100).round(1)

puts "  Checks Passed:    #{success_count}/#{total_checks}"
puts "  Success Rate:     #{success_rate}%"

if success_rate == 100
  puts "\n🎉 PERFECT! All systems working!"
elsif success_rate >= 80
  puts "\n✅ GOOD! Most systems working"
else
  puts "\n⚠️  NEEDS ATTENTION! Some systems failing"
end

puts "\n📱 App Details:"
puts "  Name: #{app.name}"
puts "  Status: #{app.status}"
puts "  URL: #{app.preview_url || 'Not deployed'}"
puts "  Tables: #{app.app_tables.pluck(:name).join(', ')}"

puts "\n💡 Test Insights:"
if total_time < 30
  puts "  ⚡ Lightning fast! Under 30 seconds total"
elsif total_time < 60
  puts "  🚀 Fast generation! Under 1 minute"
elsif total_time < 120
  puts "  ✅ Good performance! Under 2 minutes"
else
  puts "  ⚠️  Slow performance! Over 2 minutes"
end

puts "\nCompleted at: #{Time.current}"
puts "=" * 60