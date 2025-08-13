#!/usr/bin/env ruby
# Test script to verify database setup is complete and working

require_relative 'config/environment'

def run_test(name)
  print "Testing #{name}... "
  begin
    yield
    puts "✅ PASSED"
    true
  rescue => e
    puts "❌ FAILED: #{e.message}"
    false
  end
end

puts "="*80
puts "DATABASE SETUP VERIFICATION"
puts "="*80
puts ""

results = []

# Test 1: Database shard exists
results << run_test("Database shard exists") do
  # Use SQL directly to avoid model connection issues
  shard = ActiveRecord::Base.connection.execute('SELECT * FROM database_shards LIMIT 1').first
  raise "No shards found" unless shard
  raise "Shard not available" unless shard['status'].to_i == 1 # 1 = available
end

# Test 2: Can create user
results << run_test("User creation") do
  user = User.create!(
    email: "test-#{SecureRandom.hex(4)}@example.com",
    password: 'password123',
    first_name: 'Test',
    last_name: 'User',
    time_zone: 'UTC'
  )
  raise "User not created" unless user.persisted?
  user.destroy
end

# Test 3: Can create app
results << run_test("App creation") do
  user = User.first || User.create!(
    email: "app-test-#{SecureRandom.hex(4)}@example.com",
    password: 'password123',
    first_name: 'App',
    last_name: 'Test',
    time_zone: 'UTC'
  )
  team = user.teams.first || user.teams.create!(name: "Test Team")
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, roles: ['admin'])
  
  app = team.apps.create!(
    name: "Test App #{Time.current.to_i}",
    status: 'generating',
    prompt: 'Test prompt',
    creator: membership,
    app_type: 'tool'
  )
  raise "App not created" unless app.persisted?
  app.destroy
end

# Test 4: Supabase sync job can run
results << run_test("Supabase sync job") do
  user = User.create!(
    email: "sync-test-#{SecureRandom.hex(4)}@example.com",
    password: 'password123',
    first_name: 'Sync',
    last_name: 'Test',
    time_zone: 'UTC'
  )
  
  # Run job synchronously
  SupabaseAuthSyncJob.perform_now(user.id, 'create')
  
  # Check if mapping was created
  if user.user_shard_mappings.any?
    # Clean up
    user.user_shard_mappings.destroy_all
  end
  user.destroy
end

# Test 5: V5 builder can initialize
results << run_test("V5 builder initialization") do
  user = User.first || User.create!(
    email: "v5-test-#{SecureRandom.hex(4)}@example.com",
    password: 'password123',
    first_name: 'V5',
    last_name: 'Test',
    time_zone: 'UTC'
  )
  team = user.teams.first || user.teams.create!(name: "V5 Test Team")
  membership = team.memberships.find_by(user: user) || team.memberships.create!(user: user, roles: ['admin'])
  
  app = team.apps.create!(
    name: "V5 Test App #{Time.current.to_i}",
    status: 'generating',
    prompt: 'Test prompt',
    creator: membership,
    app_type: 'tool'
  )
  
  message = AppChatMessage.create!(
    app: app,
    user: user,
    role: 'user',
    content: 'Test message'
  )
  
  builder = Ai::AppBuilderV5.new(message)
  raise "Builder not initialized" unless builder
  
  # Clean up
  message.destroy
  app.destroy
end

# Test 6: Test environment database setup
results << run_test("Test environment readiness") do
  # This would fail if schema isn't properly set up
  ActiveRecord::Base.connection.tables.each do |table|
    ActiveRecord::Base.connection.columns(table)
  end
end

puts ""
puts "="*80
puts "RESULTS SUMMARY"
puts "="*80
passed = results.count(true)
failed = results.count(false)
total = results.count

puts "✅ Passed: #{passed}/#{total}"
puts "❌ Failed: #{failed}/#{total}" if failed > 0
puts ""

if failed == 0
  puts "🎉 All tests passed! Database is properly configured."
else
  puts "⚠️  Some tests failed. Please review and fix the issues."
  exit 1
end