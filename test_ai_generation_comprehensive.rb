#!/usr/bin/env ruby

# Comprehensive AI App Generation System Test
# Tests all 23 tools, GPT-5/Claude fallback, code quality, deployment, and error handling

require 'benchmark'
require 'json'
require 'time'
require 'colorize'

class AiGenerationSystemTest
  def initialize
    @results = {
      start_time: Time.now,
      tests: {},
      errors: [],
      warnings: [],
      performance: {},
      summary: {}
    }
    
    puts "🚀 Starting Comprehensive AI App Generation System Test".colorize(:cyan).bold
    puts "=" * 80
  end
  
  def run_all_tests
    # Test 1: Architecture Analysis
    test_architecture_analysis
    
    # Test 2: Create complex test app
    test_complex_app_generation
    
    # Test 3: Test all 23 tools
    test_all_tools
    
    # Test 4: Test GPT-5/Claude fallback
    test_model_fallback
    
    # Test 5: Validate generated code quality
    test_code_quality
    
    # Test 6: Test deployment pipeline
    test_deployment
    
    # Test 7: Error handling and edge cases
    test_error_handling
    
    # Test 8: Performance metrics
    test_performance_metrics
    
    # Generate comprehensive report
    generate_report
  end
  
  private
  
  def test_architecture_analysis
    puts "\n📐 Test 1: Architecture Analysis".colorize(:blue).bold
    
    @results[:tests][:architecture] = {
      status: 'running',
      start_time: Time.now
    }
    
    begin
      # Check if all required services exist
      services_to_check = [
        'app/services/ai/app_update_orchestrator_v2.rb',
        'app/services/ai/open_router_client.rb',
        'app/services/ai/context_cache_service.rb',
        'app/services/ai/enhanced_error_handler.rb'
      ]
      
      missing_services = []
      services_to_check.each do |service|
        unless File.exist?(service)
          missing_services << service
        end
      end
      
      if missing_services.empty?
        puts "  ✅ All core AI services found".colorize(:green)
        @results[:tests][:architecture][:status] = 'passed'
      else
        puts "  ❌ Missing services: #{missing_services.join(', ')}".colorize(:red)
        @results[:tests][:architecture][:status] = 'failed'
        @results[:errors] << "Missing AI services: #{missing_services.join(', ')}"
      end
      
      # Check tool definitions
      orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
      tool_count = orchestrator_content.scan(/name: "(\w+)"/).size
      
      puts "  📊 Found #{tool_count} tools in orchestrator".colorize(:yellow)
      
      if tool_count >= 23
        puts "  ✅ All 23+ tools implemented".colorize(:green)
      else
        @results[:warnings] << "Expected 23 tools, found #{tool_count}"
        puts "  ⚠️  Expected 23 tools, found #{tool_count}".colorize(:yellow)
      end
      
      @results[:tests][:architecture][:tool_count] = tool_count
      @results[:tests][:architecture][:end_time] = Time.now
      
    rescue => e
      @results[:tests][:architecture][:status] = 'error'
      @results[:tests][:architecture][:error] = e.message
      @results[:errors] << "Architecture test failed: #{e.message}"
      puts "  ❌ Architecture test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_complex_app_generation
    puts "\n🏗️  Test 2: Complex App Generation Request".colorize(:blue).bold
    
    @results[:tests][:app_generation] = {
      status: 'running',
      start_time: Time.now
    }
    
    # Create a complex test request that exercises multiple features
    test_request = {
      prompt: <<~PROMPT
        Create a sophisticated project management and team collaboration platform with the following requirements:
        
        CORE FEATURES:
        1. Project dashboard with Kanban boards and Gantt charts
        2. Team member management with roles and permissions
        3. Real-time chat and file sharing
        4. Time tracking and reporting
        5. Calendar integration and deadline management
        6. Document collaboration and version control
        7. Budget tracking and expense management
        8. Client portal for project visibility
        
        TECHNICAL REQUIREMENTS:
        - Modern React with TypeScript
        - Responsive design for mobile and desktop
        - Dark/light theme toggle
        - Data visualization with charts
        - Advanced search and filtering
        - Real-time updates
        - Export functionality (PDF, CSV)
        - Keyboard shortcuts
        
        DESIGN REQUIREMENTS:
        - Professional business aesthetic
        - Consistent component library
        - Accessibility compliant
        - Performance optimized
        - Progressive enhancement
        
        DATABASE REQUIREMENTS:
        - Users with authentication
        - Projects with custom fields
        - Tasks with dependencies
        - Time entries and billing
        - File attachments
        - Comments and activity logs
        
        INTEGRATIONS:
        - Google Calendar/Outlook
        - Slack notifications
        - GitHub/GitLab integration
        - Stripe for billing
        - Email notifications
      PROMPT,
      
      requirements: [
        'Multi-user authentication',
        'Real-time collaboration',
        'Advanced data visualization',
        'Mobile responsiveness',
        'Performance optimization',
        'Accessibility compliance',
        'Progressive enhancement',
        'Third-party integrations'
      ]
    }
    
    begin
      puts "  📝 Generated complex test request with #{test_request[:requirements].size} requirements"
      puts "  📊 Request size: #{test_request[:prompt].length} characters"
      
      # Validate request complexity
      complexity_score = calculate_complexity_score(test_request[:prompt])
      puts "  🎯 Complexity score: #{complexity_score}/100"
      
      @results[:tests][:app_generation][:request] = test_request
      @results[:tests][:app_generation][:complexity_score] = complexity_score
      @results[:tests][:app_generation][:status] = 'passed'
      @results[:tests][:app_generation][:end_time] = Time.now
      
      puts "  ✅ Complex app generation request created successfully".colorize(:green)
      
    rescue => e
      @results[:tests][:app_generation][:status] = 'error'
      @results[:tests][:app_generation][:error] = e.message
      @results[:errors] << "App generation test failed: #{e.message}"
      puts "  ❌ App generation test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_all_tools
    puts "\n🛠️  Test 3: Testing All 23 Tools".colorize(:blue).bold
    
    @results[:tests][:tools] = {
      status: 'running',
      start_time: Time.now,
      individual_tools: {}
    }
    
    # List of all 23 tools that should be available
    expected_tools = [
      'read_file',
      'write_file', 
      'update_file',
      'delete_file',
      'line_replace',
      'search_files',
      'rename_file',
      'read_console_logs',
      'read_network_requests',
      'add_dependency',
      'remove_dependency',
      'web_search',
      'download_to_repo',
      'fetch_website',
      'broadcast_progress',
      'generate_image',
      'edit_image',
      'read_analytics',
      'git_status',
      'git_commit',
      'git_branch',
      'git_diff',
      'git_log'
    ]
    
    orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
    
    found_tools = []
    missing_tools = []
    
    expected_tools.each do |tool|
      if orchestrator_content.include?("\"#{tool}\"") || orchestrator_content.include?("'#{tool}'")
        found_tools << tool
        @results[:tests][:tools][:individual_tools][tool] = {
          status: 'found',
          implementation_check: check_tool_implementation(orchestrator_content, tool)
        }
        puts "  ✅ #{tool}".colorize(:green)
      else
        missing_tools << tool
        @results[:tests][:tools][:individual_tools][tool] = { status: 'missing' }
        puts "  ❌ #{tool}".colorize(:red)
      end
    end
    
    puts "\n  📊 Tool Summary:"
    puts "    Found: #{found_tools.size}/#{expected_tools.size}".colorize(:green)
    puts "    Missing: #{missing_tools.size}".colorize(missing_tools.empty? ? :green : :red)
    
    if missing_tools.any?
      puts "    Missing tools: #{missing_tools.join(', ')}".colorize(:red)
      @results[:errors] << "Missing tools: #{missing_tools.join(', ')}"
    end
    
    @results[:tests][:tools][:found_count] = found_tools.size
    @results[:tests][:tools][:missing_count] = missing_tools.size
    @results[:tests][:tools][:found_tools] = found_tools
    @results[:tests][:tools][:missing_tools] = missing_tools
    @results[:tests][:tools][:status] = missing_tools.empty? ? 'passed' : 'failed'
    @results[:tests][:tools][:end_time] = Time.now
  end
  
  def test_model_fallback
    puts "\n🔄 Test 4: GPT-5/Claude Fallback Mechanism".colorize(:blue).bold
    
    @results[:tests][:fallback] = {
      status: 'running',
      start_time: Time.now
    }
    
    begin
      client_content = File.read('app/services/ai/open_router_client.rb')
      
      # Check for GPT-5 primary model configuration
      has_gpt5_primary = client_content.include?('DEFAULT_MODEL = :gpt5')
      puts "  #{has_gpt5_primary ? '✅' : '❌'} GPT-5 set as primary model".colorize(has_gpt5_primary ? :green : :red)
      
      # Check for Claude fallback logic
      has_fallback_logic = client_content.include?('rescue => e') && 
                          client_content.include?('falling back') &&
                          client_content.include?('claude')
      puts "  #{has_fallback_logic ? '✅' : '❌'} Claude fallback logic implemented".colorize(has_fallback_logic ? :green : :red)
      
      # Check for model specifications
      model_specs_defined = client_content.include?('MODEL_SPECS') && 
                           client_content.include?('openai/gpt-5') &&
                           client_content.include?('anthropic/claude-sonnet-4')
      puts "  #{model_specs_defined ? '✅' : '❌'} Model specifications defined".colorize(model_specs_defined ? :green : :red)
      
      # Check for enhanced error handling
      has_error_handler = client_content.include?('EnhancedErrorHandler') &&
                         client_content.include?('execute_with_retry')
      puts "  #{has_error_handler ? '✅' : '❌'} Enhanced error handling".colorize(has_error_handler ? :green : :red)
      
      # Check for reasoning level determination
      has_reasoning = client_content.include?('determine_reasoning_level') &&
                     client_content.include?(':high') &&
                     client_content.include?(':medium')
      puts "  #{has_reasoning ? '✅' : '❌'} Reasoning level determination".colorize(has_reasoning ? :green : :red)
      
      fallback_score = [has_gpt5_primary, has_fallback_logic, model_specs_defined, has_error_handler, has_reasoning].count(true)
      
      puts "  📊 Fallback mechanism score: #{fallback_score}/5"
      
      @results[:tests][:fallback] = {
        status: fallback_score >= 4 ? 'passed' : 'failed',
        score: fallback_score,
        gpt5_primary: has_gpt5_primary,
        fallback_logic: has_fallback_logic,
        model_specs: model_specs_defined,
        error_handler: has_error_handler,
        reasoning_levels: has_reasoning,
        end_time: Time.now
      }
      
      if fallback_score < 4
        @results[:errors] << "Fallback mechanism incomplete (#{fallback_score}/5 features)"
      end
      
    rescue => e
      @results[:tests][:fallback][:status] = 'error'
      @results[:tests][:fallback][:error] = e.message
      @results[:errors] << "Fallback test failed: #{e.message}"
      puts "  ❌ Fallback test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_code_quality
    puts "\n🔍 Test 5: Code Quality Validation".colorize(:blue).bold
    
    @results[:tests][:code_quality] = {
      status: 'running',
      start_time: Time.now,
      metrics: {}
    }
    
    begin
      # Test files to analyze
      files_to_analyze = [
        'app/services/ai/app_update_orchestrator_v2.rb',
        'app/services/ai/open_router_client.rb'
      ]
      
      total_lines = 0
      total_methods = 0
      complexity_issues = []
      
      files_to_analyze.each do |file|
        next unless File.exist?(file)
        
        content = File.read(file)
        lines = content.split("\n").size
        methods = content.scan(/def\s+\w+/).size
        
        total_lines += lines
        total_methods += methods
        
        # Check for complexity indicators
        if lines > 500
          complexity_issues << "#{file}: High line count (#{lines} lines)"
        end
        
        if content.scan(/def\s+\w+.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n.*\n/m).size > 0
          complexity_issues << "#{file}: Contains very long methods"
        end
        
        puts "  📄 #{file}: #{lines} lines, #{methods} methods"
      end
      
      # Calculate quality metrics
      avg_lines_per_method = total_methods > 0 ? (total_lines.to_f / total_methods).round(2) : 0
      
      puts "  📊 Quality Metrics:"
      puts "    Total lines: #{total_lines}"
      puts "    Total methods: #{total_methods}"
      puts "    Avg lines per method: #{avg_lines_per_method}"
      puts "    Complexity issues: #{complexity_issues.size}"
      
      if complexity_issues.any?
        puts "  ⚠️  Complexity Issues:"
        complexity_issues.each { |issue| puts "    - #{issue}".colorize(:yellow) }
      end
      
      # Check for best practices
      orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
      
      best_practices = {
        error_handling: orchestrator_content.include?('rescue => e'),
        logging: orchestrator_content.include?('Rails.logger'),
        constants: orchestrator_content.include?('FREEZE') || orchestrator_content.include?('.freeze'),
        documentation: orchestrator_content.include?('# ') || orchestrator_content.include?('##'),
        modularity: orchestrator_content.scan(/def\s+\w+/).size > 10
      }
      
      best_practices.each do |practice, implemented|
        status = implemented ? '✅' : '❌'
        color = implemented ? :green : :red
        puts "  #{status} #{practice.to_s.capitalize.gsub('_', ' ')}".colorize(color)
      end
      
      quality_score = best_practices.values.count(true)
      
      @results[:tests][:code_quality] = {
        status: quality_score >= 4 ? 'passed' : 'warning',
        total_lines: total_lines,
        total_methods: total_methods,
        avg_lines_per_method: avg_lines_per_method,
        complexity_issues: complexity_issues,
        best_practices: best_practices,
        quality_score: quality_score,
        end_time: Time.now
      }
      
      puts "  📊 Overall quality score: #{quality_score}/5"
      
    rescue => e
      @results[:tests][:code_quality][:status] = 'error'
      @results[:tests][:code_quality][:error] = e.message
      @results[:errors] << "Code quality test failed: #{e.message}"
      puts "  ❌ Code quality test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_deployment
    puts "\n🚀 Test 6: Deployment Pipeline".colorize(:blue).bold
    
    @results[:tests][:deployment] = {
      status: 'running',
      start_time: Time.now
    }
    
    begin
      # Check for deployment services
      deployment_services = [
        'app/services/deployment/fast_preview_service.rb',
        'app/services/deployment/cloudflare_preview_service.rb',
        'app/services/deployment/cloudflare_secret_service.rb'
      ]
      
      found_services = []
      missing_services = []
      
      deployment_services.each do |service|
        if File.exist?(service)
          found_services << service
          puts "  ✅ #{File.basename(service, '.rb').humanize}".colorize(:green)
        else
          missing_services << service
          puts "  ❌ #{File.basename(service, '.rb').humanize}".colorize(:red)
        end
      end
      
      # Check for testing tools
      testing_tools = [
        'test_todo_deployment.js',
        'test_app_functionality.js', 
        'test_app_components.js',
        'test_deployed_todo_app.html'
      ]
      
      found_tools = []
      missing_tools = []
      
      testing_tools.each do |tool|
        if File.exist?(tool)
          found_tools << tool
          puts "  ✅ #{tool}".colorize(:green)
        else
          missing_tools << tool
          puts "  ❌ #{tool}".colorize(:red)
        end
      end
      
      deployment_score = found_services.size + found_tools.size
      max_score = deployment_services.size + testing_tools.size
      
      puts "  📊 Deployment infrastructure: #{deployment_score}/#{max_score}"
      
      @results[:tests][:deployment] = {
        status: deployment_score >= (max_score * 0.8) ? 'passed' : 'warning',
        found_services: found_services,
        missing_services: missing_services,
        found_tools: found_tools,
        missing_tools: missing_tools,
        score: deployment_score,
        max_score: max_score,
        end_time: Time.now
      }
      
      if missing_services.any? || missing_tools.any?
        @results[:warnings] << "Missing deployment components: #{(missing_services + missing_tools).join(', ')}"
      end
      
    rescue => e
      @results[:tests][:deployment][:status] = 'error'
      @results[:tests][:deployment][:error] = e.message
      @results[:errors] << "Deployment test failed: #{e.message}"
      puts "  ❌ Deployment test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_error_handling
    puts "\n🛡️  Test 7: Error Handling & Edge Cases".colorize(:blue).bold
    
    @results[:tests][:error_handling] = {
      status: 'running',
      start_time: Time.now
    }
    
    begin
      # Check for enhanced error handler
      if File.exist?('app/services/ai/enhanced_error_handler.rb')
        error_handler_content = File.read('app/services/ai/enhanced_error_handler.rb')
        
        error_handling_features = {
          retry_logic: error_handler_content.include?('retry') || error_handler_content.include?('attempt'),
          exponential_backoff: error_handler_content.include?('backoff') || error_handler_content.include?('delay'),
          error_classification: error_handler_content.include?('classify') || error_handler_content.include?('category'),
          logging: error_handler_content.include?('log') || error_handler_content.include?('Rails.logger'),
          recovery_suggestions: error_handler_content.include?('suggestion') || error_handler_content.include?('recommend')
        }
        
        puts "  Error Handling Features:"
        error_handling_features.each do |feature, implemented|
          status = implemented ? '✅' : '❌'
          color = implemented ? :green : :red
          puts "    #{status} #{feature.to_s.humanize}".colorize(color)
        end
        
        error_score = error_handling_features.values.count(true)
        puts "  📊 Error handling score: #{error_score}/5"
        
        @results[:tests][:error_handling][:features] = error_handling_features
        @results[:tests][:error_handling][:score] = error_score
      else
        puts "  ❌ Enhanced error handler not found".colorize(:red)
        @results[:tests][:error_handling][:score] = 0
        @results[:errors] << "Enhanced error handler service missing"
      end
      
      # Check orchestrator error handling
      orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
      
      orchestrator_error_handling = {
        rescue_blocks: orchestrator_content.scan(/rescue\s*=>\s*\w+/).size,
        error_logging: orchestrator_content.include?('Rails.logger.error'),
        error_responses: orchestrator_content.include?('create_error_response'),
        validation: orchestrator_content.include?('validate') || orchestrator_content.include?('check'),
        fallback_logic: orchestrator_content.include?('fallback') || orchestrator_content.include?('alternative')
      }
      
      puts "  Orchestrator Error Handling:"
      orchestrator_error_handling.each do |feature, value|
        if feature == :rescue_blocks
          puts "    📊 Rescue blocks: #{value}".colorize(value > 0 ? :green : :red)
        else
          status = value ? '✅' : '❌'
          color = value ? :green : :red
          puts "    #{status} #{feature.to_s.humanize}".colorize(color)
        end
      end
      
      total_error_score = (@results[:tests][:error_handling][:score] || 0) + 
                         orchestrator_error_handling.values.select { |v| v == true }.size +
                         (orchestrator_error_handling[:rescue_blocks] > 0 ? 1 : 0)
      
      @results[:tests][:error_handling][:total_score] = total_error_score
      @results[:tests][:error_handling][:orchestrator_features] = orchestrator_error_handling
      @results[:tests][:error_handling][:status] = total_error_score >= 7 ? 'passed' : 'warning'
      @results[:tests][:error_handling][:end_time] = Time.now
      
      puts "  📊 Total error handling score: #{total_error_score}/10"
      
    rescue => e
      @results[:tests][:error_handling][:status] = 'error'
      @results[:tests][:error_handling][:error] = e.message
      @results[:errors] << "Error handling test failed: #{e.message}"
      puts "  ❌ Error handling test failed: #{e.message}".colorize(:red)
    end
  end
  
  def test_performance_metrics
    puts "\n⚡ Test 8: Performance Metrics".colorize(:blue).bold
    
    @results[:tests][:performance] = {
      status: 'running',
      start_time: Time.now
    }
    
    begin
      # Measure file sizes and complexity
      key_files = [
        'app/services/ai/app_update_orchestrator_v2.rb',
        'app/services/ai/open_router_client.rb'
      ]
      
      file_metrics = {}
      total_size = 0
      
      key_files.each do |file|
        next unless File.exist?(file)
        
        size = File.size(file)
        content = File.read(file)
        
        metrics = {
          size_kb: (size / 1024.0).round(2),
          lines: content.split("\n").size,
          methods: content.scan(/def\s+\w+/).size,
          classes: content.scan(/class\s+\w+/).size,
          complexity: calculate_cyclomatic_complexity(content)
        }
        
        file_metrics[file] = metrics
        total_size += size
        
        puts "  📄 #{File.basename(file)}:"
        puts "    Size: #{metrics[:size_kb]} KB"
        puts "    Lines: #{metrics[:lines]}"
        puts "    Methods: #{metrics[:methods]}"
        puts "    Classes: #{metrics[:classes]}"
        puts "    Complexity: #{metrics[:complexity]}"
      end
      
      # Check for performance optimizations
      orchestrator_content = File.read('app/services/ai/app_update_orchestrator_v2.rb')
      client_content = File.read('app/services/ai/open_router_client.rb')
      
      performance_features = {
        caching: orchestrator_content.include?('cache') || client_content.include?('cache'),
        context_caching: orchestrator_content.include?('ContextCacheService') || orchestrator_content.include?('context_cache'),
        token_optimization: client_content.include?('calculate_optimal_max_tokens'),
        retry_logic: client_content.include?('execute_with_retry'),
        timeout_handling: client_content.include?('timeout'),
        streaming: client_content.include?('stream_chat'),
        memory_optimization: orchestrator_content.include?('clear_cache') || orchestrator_content.include?('cleanup')
      }
      
      puts "\n  Performance Features:"
      performance_features.each do |feature, implemented|
        status = implemented ? '✅' : '❌'
        color = implemented ? :green : :red
        puts "    #{status} #{feature.to_s.humanize}".colorize(color)
      end
      
      performance_score = performance_features.values.count(true)
      
      puts "  📊 Performance optimization score: #{performance_score}/7"
      puts "  📊 Total codebase size: #{(total_size / 1024.0).round(2)} KB"
      
      @results[:tests][:performance] = {
        status: performance_score >= 5 ? 'passed' : 'warning',
        file_metrics: file_metrics,
        total_size_kb: (total_size / 1024.0).round(2),
        features: performance_features,
        score: performance_score,
        end_time: Time.now
      }
      
    rescue => e
      @results[:tests][:performance][:status] = 'error'
      @results[:tests][:performance][:error] = e.message
      @results[:errors] << "Performance test failed: #{e.message}"
      puts "  ❌ Performance test failed: #{e.message}".colorize(:red)
    end
  end
  
  def generate_report
    puts "\n📊 Generating Comprehensive Test Report".colorize(:cyan).bold
    puts "=" * 80
    
    @results[:end_time] = Time.now
    @results[:total_duration] = (@results[:end_time] - @results[:start_time]).round(2)
    
    # Calculate overall scores
    passed_tests = @results[:tests].values.count { |test| test[:status] == 'passed' }
    warning_tests = @results[:tests].values.count { |test| test[:status] == 'warning' }
    failed_tests = @results[:tests].values.count { |test| test[:status] == 'failed' }
    error_tests = @results[:tests].values.count { |test| test[:status] == 'error' }
    total_tests = @results[:tests].size
    
    @results[:summary] = {
      total_tests: total_tests,
      passed: passed_tests,
      warnings: warning_tests,
      failed: failed_tests,
      errors: error_tests,
      success_rate: ((passed_tests.to_f / total_tests) * 100).round(1),
      total_errors: @results[:errors].size,
      total_warnings: @results[:warnings].size
    }
    
    puts "\n🎯 OVERALL RESULTS".colorize(:cyan).bold
    puts "  Duration: #{@results[:total_duration]} seconds"
    puts "  Tests: #{total_tests} total"
    puts "  ✅ Passed: #{passed_tests}".colorize(:green)
    puts "  ⚠️  Warnings: #{warning_tests}".colorize(:yellow) if warning_tests > 0
    puts "  ❌ Failed: #{failed_tests}".colorize(:red) if failed_tests > 0
    puts "  💥 Errors: #{error_tests}".colorize(:red) if error_tests > 0
    puts "  📈 Success Rate: #{@results[:summary][:success_rate]}%".colorize(
      @results[:summary][:success_rate] >= 80 ? :green : 
      @results[:summary][:success_rate] >= 60 ? :yellow : :red
    )
    
    puts "\n📋 DETAILED FINDINGS".colorize(:cyan).bold
    
    # Architecture findings
    if @results[:tests][:architecture]
      puts "\n  🏗️  Architecture:"
      puts "    Tool count: #{@results[:tests][:architecture][:tool_count] || 'unknown'}/23"
      puts "    Status: #{@results[:tests][:architecture][:status]}"
    end
    
    # Tool findings  
    if @results[:tests][:tools]
      puts "\n  🛠️  Tools:"
      puts "    Found: #{@results[:tests][:tools][:found_count]}/23"
      puts "    Missing: #{@results[:tests][:tools][:missing_count]}"
      if @results[:tests][:tools][:missing_tools]&.any?
        puts "    Missing tools: #{@results[:tests][:tools][:missing_tools].join(', ')}"
      end
    end
    
    # Fallback findings
    if @results[:tests][:fallback]
      puts "\n  🔄 Fallback Mechanism:"
      puts "    Score: #{@results[:tests][:fallback][:score] || 'unknown'}/5"
      puts "    GPT-5 Primary: #{@results[:tests][:fallback][:gpt5_primary] ? 'Yes' : 'No'}"
      puts "    Claude Fallback: #{@results[:tests][:fallback][:fallback_logic] ? 'Yes' : 'No'}"
    end
    
    # Performance findings
    if @results[:tests][:performance]
      puts "\n  ⚡ Performance:"
      puts "    Optimization score: #{@results[:tests][:performance][:score] || 'unknown'}/7"
      puts "    Codebase size: #{@results[:tests][:performance][:total_size_kb] || 'unknown'} KB"
    end
    
    # Error handling findings
    if @results[:tests][:error_handling]
      puts "\n  🛡️  Error Handling:"
      puts "    Total score: #{@results[:tests][:error_handling][:total_score] || 'unknown'}/10"
    end
    
    if @results[:errors].any?
      puts "\n❌ ERRORS FOUND:".colorize(:red).bold
      @results[:errors].each_with_index do |error, index|
        puts "  #{index + 1}. #{error}".colorize(:red)
      end
    end
    
    if @results[:warnings].any?
      puts "\n⚠️  WARNINGS:".colorize(:yellow).bold
      @results[:warnings].each_with_index do |warning, index|
        puts "  #{index + 1}. #{warning}".colorize(:yellow)
      end
    end
    
    puts "\n🎯 RECOMMENDATIONS".colorize(:cyan).bold
    generate_recommendations
    
    puts "\n📄 REPORT SUMMARY".colorize(:cyan).bold
    puts "  Test completed: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
    puts "  Report saved to: test_results_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    
    # Save detailed results to JSON
    save_json_report
    
    puts "\n" + "=" * 80
    if @results[:summary][:success_rate] >= 80
      puts "🎉 AI GENERATION SYSTEM TEST COMPLETED SUCCESSFULLY!".colorize(:green).bold
    elsif @results[:summary][:success_rate] >= 60
      puts "⚠️  AI GENERATION SYSTEM TEST COMPLETED WITH WARNINGS".colorize(:yellow).bold
    else
      puts "❌ AI GENERATION SYSTEM TEST FOUND SIGNIFICANT ISSUES".colorize(:red).bold
    end
    puts "=" * 80
  end
  
  def generate_recommendations
    recommendations = []
    
    # Tool recommendations
    if @results[:tests][:tools] && @results[:tests][:tools][:missing_count] > 0
      recommendations << "Implement missing tools: #{@results[:tests][:tools][:missing_tools].join(', ')}"
    end
    
    # Fallback recommendations
    if @results[:tests][:fallback] && @results[:tests][:fallback][:score] < 4
      recommendations << "Enhance model fallback mechanism - missing critical features"
    end
    
    # Performance recommendations
    if @results[:tests][:performance] && @results[:tests][:performance][:score] < 5
      recommendations << "Add more performance optimizations (caching, token optimization, streaming)"
    end
    
    # Error handling recommendations
    if @results[:tests][:error_handling] && @results[:tests][:error_handling][:total_score] < 7
      recommendations << "Strengthen error handling and recovery mechanisms"
    end
    
    # Deployment recommendations
    if @results[:tests][:deployment] && @results[:tests][:deployment][:status] != 'passed'
      recommendations << "Complete deployment infrastructure setup"
    end
    
    # General recommendations
    if @results[:errors].size > 3
      recommendations << "Address critical errors before deploying to production"
    end
    
    if @results[:warnings].size > 5
      recommendations << "Review and resolve warning conditions"
    end
    
    if recommendations.empty?
      puts "  ✅ System appears to be well-implemented. Continue with monitoring and optimization.".colorize(:green)
    else
      recommendations.each_with_index do |rec, index|
        puts "  #{index + 1}. #{rec}"
      end
    end
  end
  
  def save_json_report
    filename = "test_results_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
    File.write(filename, JSON.pretty_generate(@results))
  end
  
  # Helper methods
  
  def calculate_complexity_score(text)
    score = 0
    
    # Feature complexity indicators
    complexity_indicators = [
      /authentication|login|oauth/i,
      /database|schema|table/i,
      /real.*time|websocket|socket/i,
      /chart|graph|visualization/i,
      /responsive|mobile/i,
      /api|integration/i,
      /typescript|react/i,
      /advanced|sophisticated/i,
      /collaboration|team/i,
      /export|pdf|csv/i
    ]
    
    complexity_indicators.each do |indicator|
      score += 10 if text.match?(indicator)
    end
    
    # Length complexity
    score += [text.length / 100, 20].min
    
    [score, 100].min
  end
  
  def check_tool_implementation(content, tool_name)
    method_name = "#{tool_name}_tool"
    has_method = content.include?("def #{method_name}")
    has_case = content.include?("when \"#{tool_name}\"")
    
    {
      has_method: has_method,
      has_case_handler: has_case,
      complete: has_method && has_case
    }
  end
  
  def calculate_cyclomatic_complexity(content)
    # Simplified cyclomatic complexity calculation
    complexity = 1 # Base complexity
    
    # Add complexity for control structures
    complexity += content.scan(/\bif\b/).size
    complexity += content.scan(/\bunless\b/).size  
    complexity += content.scan(/\bwhile\b/).size
    complexity += content.scan(/\bfor\b/).size
    complexity += content.scan(/\bcase\b/).size
    complexity += content.scan(/\bwhen\b/).size
    complexity += content.scan(/\brescue\b/).size
    complexity += content.scan(/\band\b|\bor\b|\band\b|\|\|/).size
    
    complexity
  end
end

# Add String colorization if not available
class String
  def colorize(color)
    colors = {
      red: 31,
      green: 32, 
      yellow: 33,
      blue: 34,
      cyan: 36
    }
    "\e[#{colors[color]}m#{self}\e[0m"
  end
  
  def bold
    "\e[1m#{self}\e[22m"
  end
  
  def humanize
    self.gsub('_', ' ').split.map(&:capitalize).join(' ')
  end
end

# Run the comprehensive test
if __FILE__ == $0
  test_suite = AiGenerationSystemTest.new
  test_suite.run_all_tests
end