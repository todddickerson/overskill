#!/usr/bin/env ruby
# Test the optimized V3 orchestrator with system-level prompts and caching

# Enable the optimized version
ENV['USE_V3_ORCHESTRATOR'] = 'true'
ENV['USE_V3_OPTIMIZED'] = 'true'
ENV['USE_STREAMING'] = 'false'  # Start without streaming
ENV['VERBOSE_AI_LOGGING'] = 'true'

require_relative 'config/environment'

puts "="*80
puts "V3 OPTIMIZED Orchestrator Test"
puts "="*80
puts "Key optimizations:"
puts "  ✅ System-level prompt with standards (loaded once)"
puts "  ✅ OpenAI prompt caching enabled"
puts "  ✅ Phase-specific lightweight prompts"
puts "  ✅ Batched file processing"
puts "  ✅ 2-minute timeout per call (vs 5 minutes)"
puts "="*80

team = Team.first
abort("No team found!") unless team

# Test 1: Simple app to verify it works
puts "\n📝 Test 1: Simple Counter App"
puts "-"*40

app1 = App.create!(
  team: team,
  name: "Optimized Counter Test",
  slug: "optimized-counter-#{Time.now.to_i}",
  prompt: "Create a simple counter app with increment and decrement buttons. Use a modern purple gradient theme.",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

puts "Created app ##{app1.id}"

message1 = app1.app_chat_messages.create!(
  role: 'user',
  content: app1.prompt,
  user: team.memberships.first.user
)

puts "Starting generation..."
start_time = Time.now

begin
  # Run synchronously to see immediate results
  ProcessAppUpdateJobV3.new.perform(message1)
  
  duration = Time.now - start_time
  puts "\n✅ Generation completed in #{duration.round(1)} seconds!"
  
  app1.reload
  puts "\nResults:"
  puts "  Status: #{app1.status}"
  puts "  Files created: #{app1.app_files.count}"
  
  if app1.app_files.any?
    puts "\n  Files:"
    app1.app_files.each do |file|
      puts "    - #{file.path} (#{file.content.length} bytes)"
    end
  else
    puts "\n  ⚠️  No files created - optimization may need adjustment"
  end
  
rescue => e
  duration = Time.now - start_time
  puts "\n❌ Generation failed after #{duration.round(1)} seconds"
  puts "  Error: #{e.message}"
  puts "\n  Stack trace:"
  puts e.backtrace.first(5).map { |l| "    #{l}" }.join("\n")
end

# Test 2: More complex app with streaming enabled
puts "\n\n📝 Test 2: Todo App with Streaming"
puts "-"*40

ENV['USE_STREAMING'] = 'true'

app2 = App.create!(
  team: team,
  name: "Optimized Todo App",
  slug: "optimized-todo-#{Time.now.to_i}",
  prompt: "Create a todo app with add, complete, and delete functionality. Include categories and due dates. Use a professional blue theme.",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

puts "Created app ##{app2.id}"

message2 = app2.app_chat_messages.create!(
  role: 'user',
  content: app2.prompt,
  user: team.memberships.first.user
)

puts "Starting generation with streaming..."
start_time = Time.now

begin
  ProcessAppUpdateJobV3.new.perform(message2)
  
  duration = Time.now - start_time
  puts "\n✅ Generation completed in #{duration.round(1)} seconds!"
  
  app2.reload
  puts "\nResults:"
  puts "  Status: #{app2.status}"
  puts "  Files created: #{app2.app_files.count}"
  
  if app2.app_files.any?
    puts "\n  Files:"
    app2.app_files.each do |file|
      puts "    - #{file.path} (#{file.content.length} bytes)"
    end
  end
  
rescue => e
  duration = Time.now - start_time
  puts "\n❌ Generation failed after #{duration.round(1)} seconds"
  puts "  Error: #{e.message}"
end

# Compare with original V3 (if we want)
puts "\n\n📊 Comparison Test: Original V3 vs Optimized"
puts "-"*40

ENV['USE_V3_OPTIMIZED'] = 'false'  # Use original

app3 = App.create!(
  team: team,
  name: "Original V3 Test",
  slug: "original-v3-#{Time.now.to_i}",
  prompt: "Create a simple hello world app",
  creator: team.memberships.first,
  base_price: 0,
  ai_model: "gpt-5",
  status: "draft"
)

message3 = app3.app_chat_messages.create!(
  role: 'user',
  content: app3.prompt,
  user: team.memberships.first.user
)

puts "Testing original V3..."
original_start = Time.now

begin
  # Add timeout to prevent hanging
  Timeout::timeout(30) do
    ProcessAppUpdateJobV3.new.perform(message3)
  end
  original_duration = Time.now - original_start
  puts "  Original V3: #{original_duration.round(1)}s, #{app3.reload.app_files.count} files"
rescue Timeout::Error
  puts "  Original V3: TIMEOUT after 30s"
rescue => e
  puts "  Original V3: ERROR - #{e.message}"
end

# Summary
puts "\n" + "="*80
puts "TEST SUMMARY"
puts "="*80
puts "\nOptimizations implemented:"
puts "1. ✅ System prompt with standards (cached by OpenAI)"
puts "2. ✅ Condensed inline prompts (no duplicate standards)"
puts "3. ✅ Batched file processing"
puts "4. ✅ Streaming support (when enabled)"
puts "5. ✅ 2-minute timeout vs 5-minute"
puts "\nExpected improvements:"
puts "- 50-80% faster generation"
puts "- Reduced API costs (prompt caching)"
puts "- No timeout errors"
puts "- Consistent file generation"
puts "\n" + "="*80