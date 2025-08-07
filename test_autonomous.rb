#!/usr/bin/env ruby
require_relative 'config/environment'
require_relative 'lib/autonomous_testing_system'
require 'colorize'

puts "🚀 Autonomous Testing System - Local Commands".colorize(:green)
puts "=" * 50

case ARGV[0]
when "health"
  puts "🏥 Running Health Check Test".colorize(:cyan)
  puts "-" * 30
  
  result = AutonomousTestingSystem.run_health_check
  
  puts "✅ Test Complete!".colorize(:green)
  puts "   Success: #{result[:success] ? 'YES ✅' : 'NO ❌'}".colorize(result[:success] ? :green : :red)
  puts "   Time: #{result[:generation_time].round(2)}s".colorize(:blue)
  puts "   Files: #{result[:files_generated]}".colorize(:blue)
  puts "   Patterns Found: #{result[:patterns_found].join(', ')}".colorize(:blue)
  
  if result[:errors].any?
    puts "   Errors:".colorize(:red)
    result[:errors].each { |e| puts "     - #{e}".colorize(:light_red) }
  end

when "suite"
  puts "📋 Running Full Test Suite".colorize(:cyan)
  puts "-" * 30
  
  system = AutonomousTestingSystem.instance
  results = system.run_comprehensive_test_suite
  
  successful = results.count { |r| r[:success] }
  success_rate = (successful.to_f / results.length * 100).round(1)
  
  puts "\n🎯 SUITE RESULTS".colorize(:cyan)
  puts "=" * 30
  puts "Success Rate: #{success_rate}% (#{successful}/#{results.length})".colorize(success_rate >= 70 ? :green : :red)
  puts "Average Time: #{(results.sum { |r| r[:generation_time] } / results.length).round(2)}s".colorize(:blue)
  puts "Total Files: #{results.sum { |r| r[:files_generated] }}".colorize(:blue)
  puts "GPT-5 Usage: #{results.count { |r| r[:gpt5_used] }}/#{results.length}".colorize(:blue)

when "status"
  puts "📊 Current System Status".colorize(:cyan)
  puts "-" * 30
  
  status = AutonomousTestingSystem.current_status
  
  puts "Health: #{status[:health_status].upcase}".colorize(status[:health_status] == 'healthy' ? :green : :red)
  puts "Total Tests: #{status[:metrics][:total_tests]}".colorize(:blue)
  puts "Success Rate: #{((status[:metrics][:successful_tests].to_f / [status[:metrics][:total_tests], 1].max) * 100).round(1)}%".colorize(:blue)
  puts "Avg Generation Time: #{status[:metrics][:avg_generation_time].round(2)}s".colorize(:blue)
  puts "Quality Score: #{(status[:metrics][:quality_score] * 100).round(1)}%".colorize(:blue)
  puts "GPT-5 Usage Rate: #{(status[:metrics][:gpt5_usage_rate] * 100).round(1)}%".colorize(:blue)
  
  if status[:recent_results].any?
    puts "\nRecent Tests:".colorize(:yellow)
    status[:recent_results].last(5).each do |result|
      status_icon = result[:success] ? "✅" : "❌"
      puts "  #{status_icon} #{result[:name]} - #{result[:generation_time].round(1)}s".colorize(:light_blue)
    end
  end

when "monitor"
  interval = ARGV[1]&.to_i || 30
  puts "🔄 Starting Continuous Monitoring (every #{interval} minutes)".colorize(:cyan)
  puts "Press Ctrl+C to stop".colorize(:yellow)
  puts "-" * 30
  
  AutonomousTestingSystem.start_monitoring(interval)
  
  # Keep main thread alive
  loop { sleep(10) }

when "quick"
  puts "⚡ Quick GPT-5 Test".colorize(:cyan)
  puts "-" * 30
  
  # Use our proven quick test
  system("ruby gpt5_autonomous_demo.rb")

else
  puts "Available Commands:".colorize(:yellow)
  puts ""
  puts "  ruby test_autonomous.rb health       # Single health check test"
  puts "  ruby test_autonomous.rb suite        # Full comprehensive test suite"  
  puts "  ruby test_autonomous.rb status       # Show current system status"
  puts "  ruby test_autonomous.rb monitor [min] # Start continuous monitoring"
  puts "  ruby test_autonomous.rb quick        # Quick GPT-5 demo (fastest)"
  puts ""
  puts "Examples:".colorize(:blue)
  puts "  ruby test_autonomous.rb health       # Test if system is working"
  puts "  ruby test_autonomous.rb quick        # See GPT-5 in action (30 seconds)"
  puts "  ruby test_autonomous.rb suite        # Full quality assessment (5 minutes)"
  puts "  ruby test_autonomous.rb monitor 60   # Monitor every 60 minutes"
  puts ""
  puts "Recommended first test:".colorize(:green)
  puts "  ruby test_autonomous.rb quick        # Start here!"
end