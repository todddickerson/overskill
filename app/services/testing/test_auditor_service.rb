# app/services/testing/test_auditor_service.rb
class Testing::TestAuditorService
  # Golden flows that must be protected
  GOLDEN_FLOWS = {
    'app_generation_flow' => {
      description: 'Prompt → Generate → Preview → Deploy',
      critical: true,
      patterns: [
        'app_generation', 'generate', 'ai_service', 'app_builder',
        'chat_message', 'process_app_update'
      ]
    },
    'user_authentication_flow' => {
      description: 'Registration → Login → Team Management',
      critical: true,
      patterns: [
        'authentication', 'sign_up', 'sign_in', 'password_reset',
        'user_registration', 'devise'
      ]
    },
    'app_publishing_flow' => {
      description: 'Preview → Production → Subdomain Management',
      critical: true,
      patterns: [
        'deploy', 'publish', 'production', 'cloudflare', 'preview',
        'subdomain', 'github_actions'
      ]
    },
    'realtime_chat_flow' => {
      description: 'Message → AI Response → Tool Execution → UI Update',
      critical: true,
      patterns: [
        'chat_message', 'unified_app_channel', 'websocket', 'actioncable',
        'real_time', 'tool_execution'
      ]
    },
    'file_management_flow' => {
      description: 'Create → Edit → Validate → Save',
      critical: true,
      patterns: [
        'app_file', 'app_version', 'file_sync', 'r2_storage',
        'code_validator', 'file_context'
      ]
    }
  }.freeze

  def initialize
    @test_files = []
    @audit_results = {}
    @recommendations = []
  end

  def audit_test_coverage
    puts "🔍 Starting Test Audit & Classification..."
    
    scan_test_files
    classify_tests
    analyze_golden_flow_coverage
    generate_recommendations
    
    create_audit_report
  end

  private

  def scan_test_files
    puts "\n📁 Scanning test files..."
    
    test_directories = [
      'test/system',
      'test/integration', 
      'test/controllers',
      'test/models',
      'test/services',
      'test/jobs'
    ]

    test_directories.each do |dir|
      next unless Dir.exist?(dir)
      
      Dir.glob("#{dir}/**/*_test.rb").each do |file_path|
        @test_files << analyze_test_file(file_path)
      end
    end
    
    puts "   Found #{@test_files.count} test files"
  end

  def analyze_test_file(file_path)
    content = File.read(file_path)
    file_name = File.basename(file_path, '.rb')
    relative_path = file_path.sub(Rails.root.to_s + '/', '')
    
    {
      path: relative_path,
      name: file_name,
      type: determine_test_type(file_path),
      content: content,
      line_count: content.lines.count,
      test_methods: extract_test_methods(content),
      golden_flow_coverage: [],
      priority: :unknown,
      recommendation: :unknown,
      skip_reason: nil
    }
  end

  def determine_test_type(file_path)
    case file_path
    when %r{test/system/}
      :system
    when %r{test/integration/}
      :integration
    when %r{test/controllers/}
      :controller
    when %r{test/models/}
      :model
    when %r{test/services/}
      :service
    when %r{test/jobs/}
      :job
    else
      :unknown
    end
  end

  def extract_test_methods(content)
    content.scan(/test\s+"([^"]+)"/).flatten +
    content.scan(/def\s+test_([^\s\(]+)/).flatten.map { |name| "test_#{name}" }
  end

  def classify_tests
    puts "\n🏷️  Classifying tests by golden flow coverage..."
    
    @test_files.each do |test_file|
      classify_single_test(test_file)
    end
  end

  def classify_single_test(test_file)
    content_lower = test_file[:content].downcase
    path_lower = test_file[:path].downcase
    
    # Check each golden flow
    GOLDEN_FLOWS.each do |flow_name, flow_config|
      if flow_config[:patterns].any? { |pattern| 
           content_lower.include?(pattern) || path_lower.include?(pattern) 
         }
        test_file[:golden_flow_coverage] << flow_name
      end
    end
    
    # Determine priority and recommendation
    if test_file[:golden_flow_coverage].any?
      test_file[:priority] = :high
      test_file[:recommendation] = :keep_and_enhance
    elsif scaffolding_or_boilerplate?(test_file)
      test_file[:priority] = :low
      test_file[:recommendation] = :skip_with_reason
      test_file[:skip_reason] = determine_skip_reason(test_file)
    else
      test_file[:priority] = :medium
      test_file[:recommendation] = :review_manually
    end
  end

  def scaffolding_or_boilerplate?(test_file)
    content = test_file[:content].downcase
    path = test_file[:path].downcase
    
    # Bullet Train scaffolding patterns
    return true if path.include?('scaffolding') && (
      path.include?('tangible_thing') ||
      path.include?('creative_concept') ||
      content.include?('🚅') ||
      content.include?('super_scaffolding')
    )
    
    # Generic CRUD patterns without golden flow relevance
    return true if content.include?('should get index') && 
                   content.include?('should get new') &&
                   content.include?('should create') &&
                   content.include?('should update') &&
                   content.include?('should destroy') &&
                   !test_file[:golden_flow_coverage].any?
    
    # Webhook testing (not core to our flows)
    return true if path.include?('webhook') && !test_file[:golden_flow_coverage].any?
    
    false
  end

  def determine_skip_reason(test_file)
    path = test_file[:path]
    content = test_file[:content]
    
    if path.include?('scaffolding')
      if content.include?('🚅')
        "Bullet Train Super Scaffolding boilerplate - not part of core OverSkill flows"
      else
        "Scaffolding test - not relevant to current OverSkill golden flows"
      end
    elsif path.include?('webhook')
      "Webhook test - not part of core user workflows"
    elsif generic_crud_only?(test_file)
      "Generic CRUD operations - no golden flow coverage identified"
    else
      "Non-critical functionality - focus on golden flows first"
    end
  end

  def generic_crud_only?(test_file)
    content = test_file[:content].downcase
    crud_methods = ['should get index', 'should get new', 'should create', 'should update', 'should destroy']
    
    crud_methods.all? { |method| content.include?(method) } && 
    test_file[:golden_flow_coverage].empty?
  end

  def analyze_golden_flow_coverage
    puts "\n🛡️  Analyzing golden flow coverage..."
    
    GOLDEN_FLOWS.each do |flow_name, flow_config|
      covering_tests = @test_files.select { |t| t[:golden_flow_coverage].include?(flow_name) }
      
      @audit_results[flow_name] = {
        config: flow_config,
        test_count: covering_tests.count,
        test_files: covering_tests.map { |t| t[:path] },
        coverage_level: determine_coverage_level(covering_tests),
        gaps: identify_coverage_gaps(flow_name, covering_tests)
      }
    end
  end

  def determine_coverage_level(covering_tests)
    system_tests = covering_tests.count { |t| t[:type] == :system }
    integration_tests = covering_tests.count { |t| t[:type] == :integration }
    unit_tests = covering_tests.count { |t| [:model, :service, :job].include?(t[:type]) }
    
    if system_tests > 0 && integration_tests > 0 && unit_tests > 2
      :comprehensive
    elsif system_tests > 0 && (integration_tests > 0 || unit_tests > 1)
      :good
    elsif system_tests > 0 || integration_tests > 0
      :basic
    elsif unit_tests > 0
      :minimal
    else
      :none
    end
  end

  def identify_coverage_gaps(flow_name, covering_tests)
    gaps = []
    
    case flow_name
    when 'app_generation_flow'
      gaps << "End-to-end browser testing" unless covering_tests.any? { |t| t[:type] == :system }
      gaps << "Error handling scenarios" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('error') || t[:content].downcase.include?('fail') 
      }
      gaps << "Performance validation" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('performance') || t[:content].downcase.include?('timeout') 
      }
    when 'user_authentication_flow'
      gaps << "OAuth integration testing" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('oauth') || t[:content].downcase.include?('github') 
      }
    when 'app_publishing_flow'
      gaps << "Cloudflare deployment testing" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('cloudflare') || t[:content].downcase.include?('deploy') 
      }
    when 'realtime_chat_flow'
      gaps << "ActionCable WebSocket testing" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('cable') || t[:content].downcase.include?('websocket') 
      }
    when 'file_management_flow'
      gaps << "R2 storage integration testing" unless covering_tests.any? { |t| 
        t[:content].downcase.include?('r2') || t[:content].downcase.include?('storage') 
      }
    end
    
    gaps
  end

  def generate_recommendations
    puts "\n💡 Generating recommendations..."
    
    # Summary statistics
    total_tests = @test_files.count
    high_priority = @test_files.count { |t| t[:priority] == :high }
    skip_recommended = @test_files.count { |t| t[:recommendation] == :skip_with_reason }
    
    @recommendations << {
      type: :summary,
      title: "Test Suite Overview",
      data: {
        total_tests: total_tests,
        golden_flow_tests: high_priority,
        skip_recommended: skip_recommended,
        coverage_percentage: ((high_priority.to_f / total_tests) * 100).round(1)
      }
    }
    
    # Specific recommendations for each golden flow
    GOLDEN_FLOWS.each do |flow_name, flow_config|
      coverage = @audit_results[flow_name][:coverage_level]
      gaps = @audit_results[flow_name][:gaps]
      
      case coverage
      when :none, :minimal
        @recommendations << {
          type: :critical,
          flow: flow_name,
          title: "Missing Golden Flow Coverage",
          message: "#{flow_config[:description]} has insufficient test coverage",
          action: "Create comprehensive test suite starting with integration tests",
          gaps: gaps
        }
      when :basic
        @recommendations << {
          type: :enhancement,
          flow: flow_name,
          title: "Enhance Golden Flow Testing",
          message: "#{flow_config[:description]} needs additional test scenarios",
          action: "Add system tests and error handling scenarios",
          gaps: gaps
        }
      end
    end
  end

  def create_audit_report
    timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
    report_path = "test_audit_report_#{timestamp}.md"
    
    File.open(report_path, 'w') do |f|
      f.puts generate_markdown_report
    end
    
    puts "\n✅ Test audit complete!"
    puts "📊 Report saved to: #{report_path}"
    
    display_summary
    
    report_path
  end

  def generate_markdown_report
    report = []
    report << "# Test Suite Audit Report"
    report << "*Generated: #{Time.current.strftime('%B %d, %Y at %I:%M %p')}*"
    report << ""
    
    # Executive Summary
    summary = @recommendations.find { |r| r[:type] == :summary }[:data]
    report << "## 📊 Executive Summary"
    report << ""
    report << "- **Total Test Files**: #{summary[:total_tests]}"
    report << "- **Golden Flow Coverage**: #{summary[:golden_flow_tests]} tests (#{summary[:coverage_percentage]}%)"
    report << "- **Recommended to Skip**: #{summary[:skip_recommended]} tests"
    report << ""
    
    # Golden Flow Analysis
    report << "## 🛡️ Golden Flow Coverage Analysis"
    report << ""
    
    GOLDEN_FLOWS.each do |flow_name, flow_config|
      result = @audit_results[flow_name]
      report << "### #{flow_name.humanize.titleize}"
      report << "**Description**: #{flow_config[:description]}"
      report << "**Coverage Level**: #{result[:coverage_level].to_s.humanize} (#{result[:test_count]} tests)"
      report << ""
      
      if result[:test_files].any?
        report << "**Covering Tests**:"
        result[:test_files].each { |path| report << "- #{path}" }
        report << ""
      end
      
      if result[:gaps].any?
        report << "**Coverage Gaps**:"
        result[:gaps].each { |gap| report << "- #{gap}" }
        report << ""
      end
    end
    
    # Test Classification Results
    report << "## 🏷️ Test Classification Results"
    report << ""
    
    [:high, :medium, :low].each do |priority|
      tests = @test_files.select { |t| t[:priority] == priority }
      next if tests.empty?
      
      report << "### #{priority.to_s.capitalize} Priority Tests (#{tests.count})"
      report << ""
      
      tests.each do |test|
        report << "**#{test[:name]}** (`#{test[:path]}`)"
        
        if test[:golden_flow_coverage].any?
          report << "- Golden Flows: #{test[:golden_flow_coverage].join(', ')}"
        end
        
        report << "- Recommendation: #{test[:recommendation].to_s.humanize}"
        
        if test[:skip_reason]
          report << "- Skip Reason: #{test[:skip_reason]}"
        end
        
        report << ""
      end
    end
    
    # Action Items
    report << "## 🎯 Recommended Actions"
    report << ""
    
    # Tests to skip
    skip_tests = @test_files.select { |t| t[:recommendation] == :skip_with_reason }
    if skip_tests.any?
      report << "### Tests to Comment Out/Skip"
      report << ""
      report << "```ruby"
      report << "# Add to test files or create test helper method:"
      skip_tests.each do |test|
        report << ""
        report << "# #{test[:path]}"
        report << "# Reason: #{test[:skip_reason]}"
        report << "skip \"#{test[:name]} - #{test[:skip_reason]}\""
      end
      report << "```"
      report << ""
    end
    
    # Critical gaps to address
    critical_recs = @recommendations.select { |r| r[:type] == :critical }
    if critical_recs.any?
      report << "### Critical Coverage Gaps"
      report << ""
      critical_recs.each do |rec|
        report << "**#{rec[:title]}** (#{rec[:flow]})"
        report << "- Issue: #{rec[:message]}"
        report << "- Action: #{rec[:action]}"
        if rec[:gaps]&.any?
          report << "- Specific gaps: #{rec[:gaps].join(', ')}"
        end
        report << ""
      end
    end
    
    report.join("\n")
  end

  def display_summary
    puts "\n" + "="*60
    puts "🎯 TEST AUDIT SUMMARY"
    puts "="*60
    
    summary = @recommendations.find { |r| r[:type] == :summary }[:data]
    puts "Total Tests: #{summary[:total_tests]}"
    puts "Golden Flow Coverage: #{summary[:golden_flow_tests]} (#{summary[:coverage_percentage]}%)"
    puts "Recommended to Skip: #{summary[:skip_recommended]}"
    
    puts "\n🛡️ GOLDEN FLOW STATUS:"
    GOLDEN_FLOWS.each do |flow_name, flow_config|
      result = @audit_results[flow_name]
      status = case result[:coverage_level]
               when :comprehensive then "✅"
               when :good then "🟡"
               when :basic then "⚠️"
               when :minimal, :none then "❌"
               end
      puts "#{status} #{flow_name.humanize.titleize}: #{result[:coverage_level]} (#{result[:test_count]} tests)"
    end
    
    puts "\n💡 NEXT STEPS:"
    puts "1. Review the generated report"
    puts "2. Comment out/skip non-critical tests as recommended"
    puts "3. Address critical coverage gaps for golden flows"
    puts "4. Establish performance baselines for critical workflows"
    puts "="*60
  end
end