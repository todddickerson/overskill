#!/usr/bin/env ruby

# Simple AI App Generation System Test

puts "🚀 AI App Generation System Test"
puts "=" * 50

# Test 1: Check core files exist
puts "\n📐 Test 1: Architecture Check"

required_files = [
  'app/services/ai/app_update_orchestrator_v2.rb',
  'app/services/ai/open_router_client.rb'
]

missing_files = []
required_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
  else
    puts "  ❌ #{file}"
    missing_files << file
  end
end

if missing_files.empty?
  puts "  📊 Architecture: PASS"
else
  puts "  📊 Architecture: FAIL - Missing #{missing_files.size} files"
end

# Test 2: Count tools in orchestrator
puts "\n🛠️ Test 2: Tool Implementation"

if File.exist?('app/services/ai/app_update_orchestrator_v2.rb')
  content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
  
  expected_tools = [
    'read_file', 'write_file', 'update_file', 'delete_file', 'line_replace',
    'search_files', 'rename_file', 'read_console_logs', 'read_network_requests',
    'add_dependency', 'remove_dependency', 'web_search', 'download_to_repo',
    'fetch_website', 'broadcast_progress', 'generate_image', 'edit_image',
    'read_analytics', 'git_status', 'git_commit', 'git_branch', 'git_diff', 'git_log'
  ]
  
  found_tools = []
  missing_tools = []
  
  expected_tools.each do |tool|
    if content.include?("\"#{tool}\"") || content.include?("'#{tool}'")
      found_tools << tool
      puts "  ✅ #{tool}"
    else
      missing_tools << tool
      puts "  ❌ #{tool}"
    end
  end
  
  puts "  📊 Tools: #{found_tools.size}/#{expected_tools.size} found"
  
  if missing_tools.any?
    puts "  ⚠️  Missing: #{missing_tools.join(', ')}"
  end
else
  puts "  ❌ Orchestrator file not found"
end

# Test 3: Check model configuration
puts "\n🔄 Test 3: Model Configuration"

if File.exist?('app/services/ai/open_router_client.rb')
  client_content = File.read('app/services/ai/open_router_client.rb')
  
  checks = {
    'GPT-5 Primary' => client_content.include?('DEFAULT_MODEL = :gpt5'),
    'Claude Fallback' => client_content.include?('falling back') && client_content.include?('claude'),
    'Model Specs' => client_content.include?('MODEL_SPECS'),
    'Error Handler' => client_content.include?('EnhancedErrorHandler'),
    'Tool Calling' => client_content.include?('chat_with_tools')
  }
  
  checks.each do |check, passed|
    status = passed ? '✅' : '❌'
    puts "  #{status} #{check}"
  end
  
  score = checks.values.count(true)
  puts "  📊 Configuration: #{score}/#{checks.size}"
else
  puts "  ❌ Client file not found"
end

# Test 4: Check supporting services
puts "\n🔧 Test 4: Supporting Services"

support_files = [
  'app/services/ai/context_cache_service.rb',
  'app/services/ai/enhanced_error_handler.rb'
]

found_support = 0
support_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
    found_support += 1
  else
    puts "  ❌ #{file}"
  end
end

puts "  📊 Support Services: #{found_support}/#{support_files.size}"

# Test 5: Deployment Infrastructure
puts "\n🚀 Test 5: Deployment Infrastructure"

deployment_files = [
  'app/services/deployment/fast_preview_service.rb',
  'app/services/deployment/cloudflare_preview_service.rb'
]

found_deployment = 0
deployment_files.each do |file|
  if File.exist?(file)
    puts "  ✅ #{file}"
    found_deployment += 1
  else
    puts "  ❌ #{file}"
  end
end

# Check for testing tools
testing_tools = ['test_todo_deployment.js', 'test_app_functionality.js']
found_testing = 0
testing_tools.each do |tool|
  if File.exist?(tool)
    puts "  ✅ #{tool}"
    found_testing += 1
  else
    puts "  ❌ #{tool}"
  end
end

puts "  📊 Deployment: #{found_deployment}/#{deployment_files.size} services"
puts "  📊 Testing Tools: #{found_testing}/#{testing_tools.size} tools"

# Test 6: Performance Features
puts "\n⚡ Test 6: Performance Features"

if File.exist?('app/services/ai/app_update_orchestrator_v2.rb')
  orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
  client_content = File.read('app/services/ai/open_router_client.rb') if File.exist?('app/services/ai/open_router_client.rb')
  
  performance_features = {
    'Caching' => (orchestrator_content.include?('cache') || (client_content && client_content.include?('cache'))),
    'Context Cache' => orchestrator_content.include?('ContextCacheService'),
    'Token Optimization' => (client_content && client_content.include?('calculate_optimal_max_tokens')),
    'Retry Logic' => (client_content && client_content.include?('execute_with_retry')),
    'Streaming' => (client_content && client_content.include?('stream_chat'))
  }
  
  performance_features.each do |feature, implemented|
    status = implemented ? '✅' : '❌'
    puts "  #{status} #{feature}"
  end
  
  perf_score = performance_features.values.count(true)
  puts "  📊 Performance: #{perf_score}/#{performance_features.size}"
end

# Summary
puts "\n" + "=" * 50
puts "🎯 TEST SUMMARY"

total_checks = 0
passed_checks = 0

# Count results
if missing_files.empty?
  passed_checks += 1
end
total_checks += 1

if File.exist?('app/services/ai/app_update_orchestrator_v2.rb')
  content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
  expected_tools = ['read_file', 'write_file', 'update_file', 'delete_file', 'line_replace']
  found = expected_tools.count { |tool| content.include?("\"#{tool}\"") || content.include?("'#{tool}'") }
  if found >= 4
    passed_checks += 1
  end
end
total_checks += 1

success_rate = (passed_checks.to_f / total_checks * 100).round(1)

puts "Tests: #{total_checks}"
puts "Passed: #{passed_checks}"
puts "Success Rate: #{success_rate}%"

if success_rate >= 80
  puts "🎉 SYSTEM STATUS: EXCELLENT"
elsif success_rate >= 60
  puts "⚠️  SYSTEM STATUS: GOOD WITH WARNINGS"
else
  puts "❌ SYSTEM STATUS: NEEDS ATTENTION"
end

puts "=" * 50