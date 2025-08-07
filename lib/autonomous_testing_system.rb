#!/usr/bin/env ruby
require 'json'
require 'fileutils'

module AutonomousTestingSystem
  class TestRunner
    attr_reader :results_history, :metrics

    def initialize
      @results_history = []
      @metrics = {
        total_tests: 0,
        successful_tests: 0,
        avg_generation_time: 0.0,
        gpt5_usage_rate: 0.0,
        quality_score: 0.0
      }
      
      # Ensure results directory exists
      FileUtils.mkdir_p('test_results')
      
      Rails.logger.info "[AutonomousTestingSystem] Initialized"
    end

    def run_continuous_monitoring(options = {})
      interval_minutes = options[:interval] || 60
      Rails.logger.info "[AutonomousTestingSystem] Starting continuous monitoring every #{interval_minutes} minutes"
      
      loop do
        begin
          result = run_health_check_test
          log_result(result)
          update_metrics(result)
          
          # Alert if quality drops
          if @metrics[:quality_score] < 0.7
            Rails.logger.warn "[AutonomousTestingSystem] Quality score dropped to #{@metrics[:quality_score]}"
            send_alert("Quality score below threshold: #{@metrics[:quality_score]}")
          end
          
          Rails.logger.info "[AutonomousTestingSystem] Health check complete. Success rate: #{@metrics[:successful_tests]}/#{@metrics[:total_tests]}"
          
        rescue => e
          Rails.logger.error "[AutonomousTestingSystem] Error in monitoring: #{e.message}"
        end
        
        sleep(interval_minutes * 60)
      end
    end

    def run_comprehensive_test_suite
      Rails.logger.info "[AutonomousTestingSystem] Running comprehensive test suite"
      
      test_scenarios = [
        {
          name: "Counter App",
          prompt: "Create a React counter with + and - buttons. Use useState. Single index.html file only.",
          expected_patterns: ["React", "useState", "counter", "button"],
          complexity: "simple",
          timeout: 30
        },
        {
          name: "Todo List App", 
          prompt: "Create a React todo list. Add/remove todos, mark complete. Single index.html file.",
          expected_patterns: ["React", "useState", "todo", "input", "map"],
          complexity: "medium",
          timeout: 45
        },
        {
          name: "Calculator App",
          prompt: "Create a React calculator with +,-,*,/ operations. Single index.html file.",
          expected_patterns: ["React", "useState", "calculator", "eval"],
          complexity: "medium", 
          timeout: 45
        },
        {
          name: "Weather App",
          prompt: "Create a simple weather display app. Mock data is fine. React single file.",
          expected_patterns: ["React", "useState", "weather"],
          complexity: "complex",
          timeout: 60
        }
      ]

      suite_results = []
      
      test_scenarios.each_with_index do |scenario, i|
        Rails.logger.info "[AutonomousTestingSystem] Running test #{i+1}/#{test_scenarios.length}: #{scenario[:name]}"
        
        result = run_single_test(scenario)
        suite_results << result
        log_result(result)
        
        # Brief pause between tests
        sleep(3)
      end
      
      # Generate comprehensive report
      generate_test_report(suite_results)
      update_metrics_from_suite(suite_results)
      
      suite_results
    end

    def run_single_test(scenario)
      start_time = Time.current
      
      result = {
        timestamp: start_time,
        name: scenario[:name],
        prompt: scenario[:prompt],
        complexity: scenario[:complexity],
        expected_patterns: scenario[:expected_patterns],
        success: false,
        files_generated: 0,
        patterns_found: [],
        generation_time: 0.0,
        ai_model_used: nil,
        gpt5_used: false,
        total_chars: 0,
        errors: []
      }

      begin
        Timeout::timeout(scenario[:timeout]) do
          test_result = generate_app_with_gpt5(scenario[:prompt], scenario[:expected_patterns])
          
          result[:success] = test_result[:success]
          result[:files_generated] = test_result[:files] || 0
          result[:patterns_found] = test_result[:patterns_found] || []
          result[:ai_model_used] = test_result[:ai_model] || "GPT-5"
          result[:gpt5_used] = true # We're using direct GPT-5
          result[:total_chars] = test_result[:total_chars] || 0
          result[:generated_content] = test_result[:content] if test_result[:content]
        end
        
      rescue Timeout::Error
        result[:errors] << "Test timed out after #{scenario[:timeout]} seconds"
        Rails.logger.warn "[AutonomousTestingSystem] Test '#{scenario[:name]}' timed out"
        
      rescue => e
        result[:errors] << e.message
        Rails.logger.error "[AutonomousTestingSystem] Test '#{scenario[:name]}' failed: #{e.message}"
      end
      
      result[:generation_time] = Time.current - start_time
      result
    end

    def run_health_check_test
      Rails.logger.info "[AutonomousTestingSystem] Running health check"
      
      health_scenario = {
        name: "Health Check Counter",
        prompt: "Create a minimal React counter with + and - buttons. Single index.html file.",
        expected_patterns: ["React", "useState", "counter"],
        complexity: "simple",
        timeout: 30
      }
      
      run_single_test(health_scenario)
    end

    private

    def generate_app_with_gpt5(prompt, expected_patterns = [])
      # Use the proven GPT-5 generation approach
      tools = [
        {
          type: "function",
          function: {
            name: "create_file",
            description: "Create a new app file with content",
            parameters: {
              type: "object",
              properties: {
                filename: { type: "string", description: "File name (e.g. 'index.html')" },
                content: { type: "string", description: "File content" }
              },
              required: ["filename", "content"]
            }
          }
        },
        {
          type: "function", 
          function: {
            name: "complete_app",
            description: "Mark the app as complete",
            parameters: {
              type: "object",
              properties: {
                summary: { type: "string", description: "Brief summary" }
              },
              required: ["summary"]
            }
          }
        }
      ]

      messages = [
        {
          role: "system",
          content: "You are an expert React developer. Create complete, functional apps using CDN React. Always create working applications, then call complete_app when done."
        },
        {
          role: "user", 
          content: prompt
        }
      ]

      client = Ai::OpenRouterClient.new
      files_created = []
      max_iterations = 5
      iteration = 0
      
      while iteration < max_iterations
        iteration += 1
        
        response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
        
        unless response[:success]
          return { success: false, error: response[:error] }
        end
        
        messages << {
          role: "assistant",
          content: response[:content],
          tool_calls: response[:tool_calls]
        }
        
        if response[:tool_calls]
          tool_results = []
          
          response[:tool_calls].each do |tool_call|
            function_name = tool_call["function"]["name"]
            args = JSON.parse(tool_call["function"]["arguments"])
            
            case function_name
            when "create_file"
              filename = args["filename"]
              content = args["content"]
              files_created << { filename: filename, content: content }
              
              tool_results << {
                tool_call_id: tool_call["id"],
                role: "tool",
                content: JSON.generate({ success: true, message: "File #{filename} created" })
              }
              
            when "complete_app"
              tool_results << {
                tool_call_id: tool_call["id"],
                role: "tool", 
                content: JSON.generate({ success: true, message: "App completed" })
              }
              iteration = max_iterations # Exit loop
            end
          end
          
          messages.concat(tool_results)
        else
          break
        end
      end
      
      # Analyze generated content
      all_content = files_created.map { |f| f[:content] }.join(" ")
      patterns_found = expected_patterns.select do |pattern|
        all_content.downcase.include?(pattern.downcase)
      end
      
      total_chars = files_created.sum { |f| f[:content].length }
      
      {
        success: files_created.any?,
        files: files_created.length,
        patterns_found: patterns_found,
        total_chars: total_chars,
        content: files_created,
        ai_model: "GPT-5"
      }
    end

    def log_result(result)
      # Log to file for persistence
      log_entry = {
        timestamp: result[:timestamp],
        name: result[:name],
        success: result[:success],
        generation_time: result[:generation_time],
        files_generated: result[:files_generated],
        patterns_found: result[:patterns_found],
        ai_model: result[:ai_model_used],
        gpt5_used: result[:gpt5_used],
        errors: result[:errors]
      }
      
      File.open("test_results/autonomous_tests.jsonl", "a") do |f|
        f.puts(log_entry.to_json)
      end
      
      @results_history << result
      
      # Keep only last 100 results in memory
      @results_history = @results_history.last(100) if @results_history.length > 100
    end

    def update_metrics(result)
      @metrics[:total_tests] += 1
      @metrics[:successful_tests] += 1 if result[:success]
      
      # Update success rate
      success_rate = @metrics[:successful_tests].to_f / @metrics[:total_tests]
      
      # Update average generation time
      @metrics[:avg_generation_time] = (
        @metrics[:avg_generation_time] * (@metrics[:total_tests] - 1) + result[:generation_time]
      ) / @metrics[:total_tests]
      
      # Update GPT-5 usage rate
      gpt5_count = @results_history.count { |r| r[:gpt5_used] }
      @metrics[:gpt5_usage_rate] = gpt5_count.to_f / @results_history.length if @results_history.any?
      
      # Calculate quality score (success rate * pattern match rate)
      if @results_history.any?
        pattern_match_rate = @results_history.map { |r| 
          expected = r[:expected_patterns]&.length || 1
          found = r[:patterns_found]&.length || 0
          found.to_f / expected
        }.sum / @results_history.length
        
        @metrics[:quality_score] = success_rate * pattern_match_rate
      end
    end

    def update_metrics_from_suite(suite_results)
      suite_results.each { |result| update_metrics(result) }
    end

    def generate_test_report(suite_results)
      report = {
        timestamp: Time.current,
        total_tests: suite_results.length,
        successful_tests: suite_results.count { |r| r[:success] },
        success_rate: (suite_results.count { |r| r[:success] }.to_f / suite_results.length * 100).round(2),
        avg_generation_time: (suite_results.sum { |r| r[:generation_time] } / suite_results.length).round(2),
        total_files_generated: suite_results.sum { |r| r[:files_generated] },
        total_chars_generated: suite_results.sum { |r| r[:total_chars] },
        gpt5_usage: suite_results.count { |r| r[:gpt5_used] },
        results: suite_results
      }
      
      # Save detailed report
      File.open("test_results/test_report_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json", "w") do |f|
        f.puts(JSON.pretty_generate(report))
      end
      
      Rails.logger.info "[AutonomousTestingSystem] Test report generated: #{report[:success_rate]}% success rate"
      
      report
    end

    def send_alert(message)
      Rails.logger.warn "[AutonomousTestingSystem] ALERT: #{message}"
      
      # Could integrate with Slack, email, etc. here
      # For now, just log prominently
      puts "🚨 AUTONOMOUS TESTING ALERT: #{message}".colorize(:red)
    end

    public

    # API for getting current status
    def current_status
      {
        metrics: @metrics,
        recent_results: @results_history.last(10),
        last_test_time: @results_history.last&.dig(:timestamp),
        health_status: @metrics[:quality_score] >= 0.7 ? "healthy" : "degraded"
      }
    end

    # API for manual test trigger
    def trigger_health_check
      Rails.logger.info "[AutonomousTestingSystem] Manual health check triggered"
      result = run_health_check_test
      log_result(result)
      update_metrics(result)
      result
    end
  end

  # Singleton access
  def self.instance
    @instance ||= TestRunner.new
  end

  # Convenience methods
  def self.run_health_check
    instance.trigger_health_check
  end

  def self.current_status
    instance.current_status
  end

  def self.start_monitoring(interval_minutes = 60)
    Thread.new do
      instance.run_continuous_monitoring(interval: interval_minutes)
    end
  end
end