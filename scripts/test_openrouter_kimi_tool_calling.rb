#!/usr/bin/env ruby
# Test script to check if OpenRouter + Kimi K2 tool calling is working
# Run with: ruby scripts/test_openrouter_kimi_tool_calling.rb

require_relative '../config/environment'

class OpenRouterKimiToolCallTest
  def initialize
    @client = Ai::OpenRouterClient.new
    @results = {
      timestamp: Time.current,
      tests: [],
      summary: {
        total: 0,
        passed: 0,
        failed: 0,
        tool_calls_working: false
      }
    }
  end
  
  def run_all_tests
    puts "🧪 Testing OpenRouter + Kimi K2 Tool Calling Status"
    puts "=" * 50
    
    test_simple_tool_call
    test_multiple_tools
    test_json_in_text_fallback
    
    generate_summary
    save_results
    
    @results
  end
  
  private
  
  def test_simple_tool_call
    test_name = "Simple Tool Call Test"
    puts "\n🔬 #{test_name}"
    
    tools = [{
      type: 'function',
      function: {
        name: 'get_weather',
        description: 'Get weather information for a location',
        parameters: {
          type: 'object',
          properties: {
            location: { type: 'string', description: 'City name' }
          },
          required: ['location']
        }
      }
    }]
    
    messages = [{
      role: 'user',
      content: 'What is the weather like in San Francisco?'
    }]
    
    begin
      response = @client.chat(
        messages,
        model: :kimi_k2,
        tools: tools,
        max_tokens: 500
      )
      
      result = analyze_tool_call_response(response, test_name)
      @results[:tests] << result
      
      if result[:status] == :passed
        puts "✅ Tool calling working properly"
      else
        puts "❌ #{result[:error]}"
      end
      
    rescue => e
      puts "❌ Request failed: #{e.message}"
      @results[:tests] << {
        name: test_name,
        status: :error,
        error: e.message,
        timestamp: Time.current
      }
    end
  end
  
  def test_multiple_tools
    test_name = "Multiple Tools Test"
    puts "\n🔬 #{test_name}"
    
    tools = [
      {
        type: 'function',
        function: {
          name: 'create_file',
          description: 'Create a new file',
          parameters: {
            type: 'object',
            properties: {
              filename: { type: 'string', description: 'Name of the file' },
              content: { type: 'string', description: 'File content' }
            },
            required: ['filename', 'content']
          }
        }
      },
      {
        type: 'function',
        function: {
          name: 'get_time',
          description: 'Get current time',
          parameters: {
            type: 'object',
            properties: {
              timezone: { type: 'string', description: 'Timezone (optional)' }
            }
          }
        }
      }
    ]
    
    messages = [{
      role: 'user',
      content: 'Create a file called hello.txt with the content "Hello World" and then tell me what time it is.'
    }]
    
    begin
      response = @client.chat(
        messages,
        model: :kimi_k2,
        tools: tools,
        max_tokens: 500
      )
      
      result = analyze_tool_call_response(response, test_name)
      @results[:tests] << result
      
      if result[:status] == :passed
        puts "✅ Multiple tools working"
      else
        puts "❌ #{result[:error]}"
      end
      
    rescue => e
      puts "❌ Request failed: #{e.message}"
      @results[:tests] << {
        name: test_name,
        status: :error,
        error: e.message,
        timestamp: Time.current
      }
    end
  end
  
  def test_json_in_text_fallback
    test_name = "JSON-in-Text Parsing Test"
    puts "\n🔬 #{test_name}"
    
    messages = [{
      role: 'user',
      content: 'Please respond with a JSON object containing a tool call to get weather for Paris. Format it as: {"tool_call": {"name": "get_weather", "arguments": {"location": "Paris"}}}'
    }]
    
    begin
      response = @client.chat(
        messages,
        model: :kimi_k2,
        max_tokens: 200
      )
      
      content = response.dig('choices', 0, 'message', 'content')
      
      if content&.include?('tool_call') && content.include?('get_weather')
        puts "✅ JSON-in-text format working as fallback"
        @results[:tests] << {
          name: test_name,
          status: :passed,
          note: "JSON-in-text fallback available",
          timestamp: Time.current
        }
      else
        puts "❌ JSON-in-text format not working"
        @results[:tests] << {
          name: test_name,
          status: :failed,
          error: "Model didn't generate expected JSON format",
          response_preview: content&.first(100),
          timestamp: Time.current
        }
      end
      
    rescue => e
      puts "❌ Request failed: #{e.message}"
      @results[:tests] << {
        name: test_name,
        status: :error,
        error: e.message,
        timestamp: Time.current
      }
    end
  end
  
  def analyze_tool_call_response(response, test_name)
    # Check if response has proper tool_calls structure
    tool_calls = response.dig('choices', 0, 'message', 'tool_calls')
    content = response.dig('choices', 0, 'message', 'content')
    
    if tool_calls && tool_calls.is_a?(Array) && tool_calls.any?
      # Proper tool calling is working!
      {
        name: test_name,
        status: :passed,
        tool_calls_count: tool_calls.size,
        tool_names: tool_calls.map { |tc| tc.dig('function', 'name') },
        timestamp: Time.current
      }
    elsif content&.include?('```json') || content&.include?('tool_call')
      # Still using JSON-in-text format
      {
        name: test_name,
        status: :json_fallback,
        error: "Using JSON-in-text instead of proper tool calls",
        response_preview: content&.first(200),
        timestamp: Time.current
      }
    else
      # No tool calling detected at all
      {
        name: test_name,
        status: :failed,
        error: "No tool calls detected",
        response_preview: content&.first(200),
        timestamp: Time.current
      }
    end
  end
  
  def generate_summary
    @results[:summary][:total] = @results[:tests].size
    @results[:summary][:passed] = @results[:tests].count { |t| t[:status] == :passed }
    @results[:summary][:failed] = @results[:tests].count { |t| t[:status] == :failed || t[:status] == :error }
    @results[:summary][:tool_calls_working] = @results[:tests].any? { |t| t[:status] == :passed }
    
    puts "\n" + "=" * 50
    puts "📊 TEST SUMMARY"
    puts "=" * 50
    puts "Total Tests: #{@results[:summary][:total]}"
    puts "Passed: #{@results[:summary][:passed]}"
    puts "Failed: #{@results[:summary][:failed]}"
    
    if @results[:summary][:tool_calls_working]
      puts "\n🎉 OpenRouter + Kimi K2 tool calling is WORKING!"
      puts "💰 Consider switching from direct Moonshot API to save costs"
    else
      puts "\n⚠️  OpenRouter + Kimi K2 tool calling still NOT working"
      puts "💸 Continue using direct Moonshot API for reliability"
    end
    
    # Check if we should update feature flag
    current_status = FeatureFlag.find_by(name: 'openrouter_kimi_tool_calling')&.enabled?
    should_enable = @results[:summary][:tool_calls_working]
    
    if current_status != should_enable
      puts "\n🚩 Feature flag update recommended:"
      puts "   openrouter_kimi_tool_calling: #{current_status} → #{should_enable}"
    end
  end
  
  def save_results
    # Save to log file for tracking over time
    log_dir = Rails.root.join('log', 'tool_calling_tests')
    FileUtils.mkdir_p(log_dir)
    
    log_file = log_dir.join("#{Date.current}_openrouter_kimi_test.json")
    File.write(log_file, JSON.pretty_generate(@results))
    
    puts "\n📝 Results saved to: #{log_file}"
  end
end

# Run the tests if script is executed directly
if __FILE__ == $0
  tester = OpenRouterKimiToolCallTest.new
  results = tester.run_all_tests
  
  # Exit with appropriate code
  exit(results[:summary][:tool_calls_working] ? 0 : 1)
end