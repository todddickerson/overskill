#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

class AutonomousTestingFramework
  attr_reader :results, :apps_tested, :success_rate
  
  def initialize
    @results = []
    @apps_tested = 0
    @success_rate = 0.0
    @test_app_id = 59  # Use our test app
    puts "🤖 Autonomous Testing Framework Initialized".colorize(:cyan)
    puts "=" * 60
  end

  def run_comprehensive_test_suite
    puts "🚀 Starting Comprehensive Test Suite".colorize(:green)
    
    # Test different app types
    test_scenarios = [
      {
        name: "Counter App (Simple)",
        prompt: "Create a simple counter app with increment and decrement buttons. Use React with useState.",
        expected_files: ["index.html", "src/App.jsx", "src/main.jsx"],
        expected_features: ["useState", "increment", "decrement", "counter"]
      },
      {
        name: "Todo App (CRUD)",
        prompt: "Create a todo list app with add, delete, and mark complete functionality. Use React with localStorage.",
        expected_files: ["index.html", "src/App.jsx", "src/main.jsx", "src/components/TodoList.jsx"],
        expected_features: ["localStorage", "useState", "useEffect", "todo", "add", "delete"]
      },
      {
        name: "Calculator App (Complex)",
        prompt: "Create a calculator app with basic arithmetic operations. Use React with clean design.",
        expected_files: ["index.html", "src/App.jsx", "src/main.jsx"],
        expected_features: ["calculator", "arithmetic", "+", "-", "*", "/"]
      }
    ]

    test_scenarios.each_with_index do |scenario, index|
      puts "\n#{'-' * 40}".colorize(:yellow)
      puts "Test #{index + 1}/#{test_scenarios.length}: #{scenario[:name]}".colorize(:yellow)
      puts "#{'-' * 40}".colorize(:yellow)
      
      result = run_single_test(scenario)
      @results << result
      @apps_tested += 1
      
      display_test_result(result)
    end

    calculate_success_rate
    display_final_report
  end

  def run_single_test(scenario)
    start_time = Time.current
    test_app = App.find(@test_app_id)
    
    # Clear previous files
    test_app.app_files.destroy_all
    
    result = {
      name: scenario[:name],
      prompt: scenario[:prompt],
      start_time: start_time,
      success: false,
      files_generated: [],
      features_found: [],
      errors: [],
      deployment_status: nil,
      gpt5_used: false,
      anthropic_fallback: false,
      total_time: 0,
      ai_model_used: nil
    }

    begin
      # Create test message
      message = test_app.app_chat_messages.create!(
        role: "user",
        content: scenario[:prompt]
      )

      puts "📝 Prompt: #{scenario[:prompt]}".colorize(:light_blue)
      
      # Run orchestrator with performance monitoring
      puts "🔄 Running AppUpdateOrchestratorV2...".colorize(:light_blue)
      orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
      
      # Monitor which AI model is used
      start_log_position = File.size("log/development.log") rescue 0
      
      orchestrator_result = orchestrator.execute!
      
      # Check logs for AI model usage
      check_ai_model_usage(result, start_log_position)
      
      # Analyze results
      test_app.reload
      result[:files_generated] = test_app.app_files.map(&:path)
      
      # Check for expected files
      files_match = scenario[:expected_files].all? do |expected_file|
        result[:files_generated].any? { |file| file.include?(expected_file) }
      end
      
      # Check for expected features in code
      all_content = test_app.app_files.map(&:content).join(" ")
      result[:features_found] = scenario[:expected_features].select do |feature|
        all_content.downcase.include?(feature.downcase)
      end
      
      # Determine success
      result[:success] = files_match && 
                        result[:features_found].length >= (scenario[:expected_features].length * 0.7) &&
                        result[:files_generated].length > 0

      # Test deployment if successful
      if result[:success]
        result[:deployment_status] = test_deployment(test_app)
      end

    rescue => e
      result[:errors] << e.message
      puts "❌ Error: #{e.message}".colorize(:red)
    ensure
      result[:total_time] = Time.current - start_time
    end

    result
  end

  def test_deployment(app)
    puts "🚀 Testing deployment...".colorize(:light_blue)
    
    begin
      preview_service = Deployment::FastPreviewService.new(app)
      deployment_result = preview_service.deploy_instant_preview!
      
      if deployment_result[:success]
        # Test if the URL is accessible
        preview_url = deployment_result[:preview_url]
        puts "✅ Deployed to: #{preview_url}".colorize(:green)
        
        # You could add HTTP checks here if needed
        # For now, assume deployment success means it's working
        "SUCCESS"
      else
        "FAILED"
      end
    rescue => e
      puts "❌ Deployment failed: #{e.message}".colorize(:red)
      "ERROR"
    end
  end

  def check_ai_model_usage(result, start_log_position)
    begin
      log_content = File.read("log/development.log", offset: start_log_position)
      
      if log_content.include?("Using OpenAI GPT-5 direct API")
        result[:gpt5_used] = true
        result[:ai_model_used] = "GPT-5"
      end
      
      if log_content.include?("Using Anthropic direct API")
        result[:anthropic_fallback] = true
        result[:ai_model_used] = "Claude Sonnet-4 (fallback)" if result[:ai_model_used].nil?
      end
      
    rescue => e
      puts "Warning: Could not check log file: #{e.message}".colorize(:yellow)
    end
  end

  def display_test_result(result)
    puts "\n📊 Test Results:".colorize(:cyan)
    puts "   Success: #{result[:success] ? '✅ YES' : '❌ NO'}".colorize(result[:success] ? :green : :red)
    puts "   AI Model: #{result[:ai_model_used] || 'Unknown'}".colorize(:blue)
    puts "   GPT-5 Used: #{result[:gpt5_used] ? '✅' : '❌'}".colorize(result[:gpt5_used] ? :green : :red)
    puts "   Files Generated: #{result[:files_generated].length}".colorize(:blue)
    puts "   Features Found: #{result[:features_found].length}/#{result[:features_found].length}".colorize(:blue)
    puts "   Time Taken: #{result[:total_time].round(2)}s".colorize(:blue)
    
    if result[:deployment_status]
      puts "   Deployment: #{result[:deployment_status]}".colorize(result[:deployment_status] == 'SUCCESS' ? :green : :red)
    end
    
    if result[:files_generated].any?
      puts "   Generated Files:".colorize(:light_blue)
      result[:files_generated].each { |file| puts "     - #{file}".colorize(:light_cyan) }
    end
    
    if result[:features_found].any?
      puts "   Features Found:".colorize(:light_blue)
      result[:features_found].each { |feature| puts "     - #{feature}".colorize(:light_cyan) }
    end
    
    if result[:errors].any?
      puts "   Errors:".colorize(:red)
      result[:errors].each { |error| puts "     - #{error}".colorize(:light_red) }
    end
  end

  def calculate_success_rate
    successful_tests = @results.count { |r| r[:success] }
    @success_rate = (@apps_tested > 0) ? (successful_tests.to_f / @apps_tested * 100).round(2) : 0.0
  end

  def display_final_report
    puts "\n" + "=" * 60
    puts "🎯 FINAL TEST REPORT".colorize(:cyan)
    puts "=" * 60
    
    puts "📈 Overall Statistics:".colorize(:green)
    puts "   Apps Tested: #{@apps_tested}".colorize(:blue)
    puts "   Success Rate: #{@success_rate}%".colorize(@success_rate >= 70 ? :green : :red)
    puts "   Total Tests: #{@results.length}".colorize(:blue)
    
    # AI Model usage statistics
    gpt5_usage = @results.count { |r| r[:gpt5_used] }
    anthropic_usage = @results.count { |r| r[:anthropic_fallback] }
    
    puts "\n🤖 AI Model Usage:".colorize(:green)
    puts "   GPT-5 Usage: #{gpt5_usage}/#{@results.length} (#{(gpt5_usage.to_f/@results.length*100).round(1)}%)".colorize(:blue)
    puts "   Anthropic Fallback: #{anthropic_usage}/#{@results.length} (#{(anthropic_usage.to_f/@results.length*100).round(1)}%)".colorize(:blue)
    
    # Performance statistics
    avg_time = @results.map { |r| r[:total_time] }.sum / @results.length
    puts "\n⏱️  Performance:".colorize(:green)
    puts "   Average Generation Time: #{avg_time.round(2)}s".colorize(:blue)
    puts "   Fastest: #{@results.min_by { |r| r[:total_time] }[:total_time].round(2)}s".colorize(:blue)
    puts "   Slowest: #{@results.max_by { |r| r[:total_time] }[:total_time].round(2)}s".colorize(:blue)
    
    # Quality analysis
    puts "\n📝 Quality Analysis:".colorize(:green)
    successful_results = @results.select { |r| r[:success] }
    if successful_results.any?
      avg_files = successful_results.map { |r| r[:files_generated].length }.sum.to_f / successful_results.length
      avg_features = successful_results.map { |r| r[:features_found].length }.sum.to_f / successful_results.length
      puts "   Avg Files per Successful App: #{avg_files.round(1)}".colorize(:blue)
      puts "   Avg Features per Successful App: #{avg_features.round(1)}".colorize(:blue)
    end
    
    # Recommendations
    puts "\n💡 Recommendations:".colorize(:green)
    if @success_rate >= 80
      puts "   ✅ Excellent performance! System is working well.".colorize(:green)
    elsif @success_rate >= 60
      puts "   ⚠️  Good performance, minor improvements needed.".colorize(:yellow)
    else
      puts "   🚨 Performance needs improvement. Check error logs.".colorize(:red)
    end
    
    if gpt5_usage < @results.length
      puts "   🔧 Consider investigating why GPT-5 isn't used 100% of the time.".colorize(:yellow)
    end
    
    puts "\n" + "=" * 60
  end

  # Continuous monitoring mode
  def start_continuous_monitoring(interval_minutes = 30)
    puts "🔄 Starting continuous monitoring every #{interval_minutes} minutes...".colorize(:cyan)
    
    loop do
      puts "\n⏰ Running scheduled test at #{Time.current}".colorize(:yellow)
      
      # Run a single quick test
      quick_scenario = {
        name: "Health Check Counter",
        prompt: "Create a simple counter app with + and - buttons. Use React.",
        expected_files: ["index.html", "src/App.jsx"],
        expected_features: ["useState", "counter"]
      }
      
      result = run_single_test(quick_scenario)
      display_test_result(result)
      
      # Log result to file for tracking
      log_monitoring_result(result)
      
      puts "😴 Sleeping for #{interval_minutes} minutes...".colorize(:blue)
      sleep(interval_minutes * 60)
    end
  end

  def log_monitoring_result(result)
    log_data = {
      timestamp: Time.current,
      success: result[:success],
      ai_model: result[:ai_model_used],
      gpt5_used: result[:gpt5_used],
      files_count: result[:files_generated].length,
      time_taken: result[:total_time]
    }
    
    File.open("autonomous_test_log.jsonl", "a") do |f|
      f.puts(log_data.to_json)
    end
  end
end

# CLI Interface
if __FILE__ == $0
  framework = AutonomousTestingFramework.new
  
  case ARGV[0]
  when "suite"
    framework.run_comprehensive_test_suite
  when "monitor"
    interval = ARGV[1]&.to_i || 30
    framework.start_continuous_monitoring(interval)
  when "single"
    prompt = ARGV[1] || "Create a simple counter app with + and - buttons"
    scenario = {
      name: "Custom Test",
      prompt: prompt,
      expected_files: ["index.html"],
      expected_features: ["React"]
    }
    result = framework.run_single_test(scenario)
    framework.display_test_result(result)
  else
    puts "Usage:"
    puts "  ruby autonomous_testing_framework.rb suite    # Run full test suite"
    puts "  ruby autonomous_testing_framework.rb monitor [minutes]  # Continuous monitoring"
    puts "  ruby autonomous_testing_framework.rb single 'prompt'    # Single test"
  end
end