module Ai
  # AppQualityBenchmark - Comprehensive quality control and benchmarking system
  # Tests app generation and updating with multiple AI models for quality assurance
  class AppQualityBenchmark
    attr_reader :results, :app, :team
    
    # Our single, optimized tech stack
    TECH_STACK = {
      framework: "react",
      runtime: "nodejs",
      deployment: "cloudflare-workers",
      database: "supabase",
      auth: "supabase-auth",
      payments: "stripe-connect",
      features: [
        "Server-side rendering",
        "Row-level security",
        "OAuth/social logins",
        "Real-time collaboration",
        "Stripe Connect integration",
        "Responsive design",
        "PWA capabilities"
      ]
    }.freeze
    
    # Models for evaluation
    EVALUATION_MODELS = {
      primary: :claude_4,           # Main generation model
      reviewer: :claude_opus_4_1,    # High-quality review model
      alternative: :openai_o4_mini   # Alternative perspective
    }.freeze
    
    # Sample prompts for testing
    TEST_PROMPTS = [
      "Create a team collaboration tool like Slack but simpler",
      "Build a marketplace for freelance services",
      "Make a social learning platform for coding",
      "Design a personal finance tracker with goals",
      "Create a recipe sharing community app"
    ].freeze
    
    def initialize(team = nil)
      @team = team || Team.first
      @results = []
      @client = OpenRouterClient.new
    end
    
    def run_full_benchmark(iterations: 3)
      puts "\n🚀 Starting Full Quality Benchmark"
      puts "="*60
      
      iterations.times do |i|
        puts "\n📊 Iteration #{i+1}/#{iterations}"
        
        # Test generation
        generation_result = test_generation(TEST_PROMPTS.sample)
        @results << generation_result
        
        # Test updating
        if generation_result[:success]
          update_result = test_update(generation_result[:app])
          @results << update_result
        end
        
        # Clean up
        generation_result[:app]&.destroy if ENV['CLEANUP_AFTER_TEST'] == 'true'
      end
      
      # Generate report
      generate_report
    end
    
    def test_generation(prompt = nil)
      prompt ||= TEST_PROMPTS.sample
      
      puts "\n🎯 Testing Generation"
      puts "Prompt: #{prompt}"
      
      start_time = Time.current
      
      # Create app
      app = create_test_app(prompt)
      
      # Generate with primary model
      generation_result = generate_app(app, prompt)
      
      # Evaluate quality
      quality_scores = evaluate_quality(app) if generation_result[:success]
      
      # Get improvement suggestions
      suggestions = get_improvement_suggestions(app, quality_scores) if quality_scores
      
      duration = Time.current - start_time
      
      {
        type: :generation,
        success: generation_result[:success],
        app: app,
        prompt: prompt,
        duration: duration,
        quality_scores: quality_scores,
        suggestions: suggestions,
        files_created: app.app_files.count,
        errors: generation_result[:errors]
      }
    end
    
    def test_update(app)
      puts "\n✏️ Testing Update"
      
      update_prompts = [
        "Add a dark mode toggle",
        "Improve the mobile responsiveness",
        "Add loading states to all buttons",
        "Implement error boundaries",
        "Add accessibility features"
      ]
      
      prompt = update_prompts.sample
      puts "Update: #{prompt}"
      
      start_time = Time.current
      
      # Create update message
      message = app.app_chat_messages.create!(
        role: "user",
        content: prompt,
        user: User.first
      )
      
      # Process update
      update_result = process_update(app, message)
      
      # Evaluate update quality
      quality_scores = evaluate_update_quality(app, message) if update_result[:success]
      
      duration = Time.current - start_time
      
      {
        type: :update,
        success: update_result[:success],
        app: app,
        prompt: prompt,
        duration: duration,
        quality_scores: quality_scores,
        files_modified: update_result[:files_modified],
        errors: update_result[:errors]
      }
    end
    
    private
    
    def create_test_app(prompt)
      App.create!(
        team: @team,
        creator: @team.memberships.first,
        name: "Benchmark Test #{Time.current.to_i}",
        slug: "benchmark-#{Time.current.to_i}",
        prompt: prompt,
        app_type: "saas",  # Single type
        framework: TECH_STACK[:framework],
        status: "draft",
        base_price: 0,
        visibility: "private"
      )
    end
    
    def generate_app(app, prompt)
      enhanced_prompt = build_enhanced_prompt(prompt)
      
      begin
        result = @client.generate_app(enhanced_prompt, 
          framework: TECH_STACK[:framework],
          app_type: "saas"
        )
        
        if result[:success] && result[:tool_calls]
          # Process the generation
          process_generation_result(app, result)
          { success: true }
        else
          { success: false, errors: [result[:error]] }
        end
      rescue => e
        { success: false, errors: [e.message] }
      end
    end
    
    def build_enhanced_prompt(user_prompt)
      <<~PROMPT
        Create a modern SaaS application based on this description:
        #{user_prompt}
        
        REQUIRED TECH STACK:
        - Framework: React 18+ with TypeScript
        - Runtime: Node.js with Cloudflare Workers
        - Database: Supabase with Row-Level Security
        - Auth: Supabase Auth with OAuth providers
        - Payments: Stripe Connect
        
        REQUIRED FEATURES:
        #{TECH_STACK[:features].map { |f| "- #{f}" }.join("\n")}
        
        QUALITY REQUIREMENTS:
        - Production-ready code
        - Comprehensive error handling
        - Loading states for all async operations
        - Mobile-first responsive design
        - Accessibility (WCAG 2.1 AA)
        - Security best practices
        - Performance optimized
        
        Include all necessary files for a complete, working application.
      PROMPT
    end
    
    def evaluate_quality(app)
      puts "\n🔍 Evaluating Quality..."
      
      scores = {}
      
      # Code quality check
      scores[:code_quality] = evaluate_code_quality(app)
      
      # Completeness check
      scores[:completeness] = evaluate_completeness(app)
      
      # Security check
      scores[:security] = evaluate_security(app)
      
      # Performance check
      scores[:performance] = evaluate_performance(app)
      
      # Get second opinion from reviewer model
      scores[:reviewer_opinion] = get_reviewer_opinion(app)
      
      # Get alternative perspective
      scores[:alternative_opinion] = get_alternative_opinion(app)
      
      # Calculate overall score
      scores[:overall] = calculate_overall_score(scores)
      
      scores
    end
    
    def evaluate_code_quality(app)
      checks = {
        has_error_handling: false,
        has_loading_states: false,
        has_typescript: false,
        has_tests: false,
        follows_conventions: false
      }
      
      app.app_files.each do |file|
        content = file.content
        
        # Check for error handling
        checks[:has_error_handling] = true if content.match?(/try\s*{|\.catch\(|error boundary/i)
        
        # Check for loading states
        checks[:has_loading_states] = true if content.match?(/loading|isLoading|pending/i)
        
        # Check for TypeScript
        checks[:has_typescript] = true if file.path.match?(/\.tsx?$/)
        
        # Check for tests
        checks[:has_tests] = true if file.path.match?(/\.test\.|\.spec\.|__tests__/)
        
        # Check conventions
        checks[:follows_conventions] = true if content.match?(/^import|^export|^const|^function/m)
      end
      
      score = checks.values.count(true) * 20  # Each check worth 20 points
      { score: score, checks: checks }
    end
    
    def evaluate_completeness(app)
      required_files = [
        'index.html',
        'package.json',
        'src/App.tsx',
        'src/index.tsx',
        '.env.example',
        'README.md'
      ]
      
      existing = app.app_files.pluck(:path)
      missing = required_files - existing
      
      score = ((required_files.size - missing.size) * 100.0 / required_files.size).round
      { score: score, missing_files: missing }
    end
    
    def evaluate_security(app)
      vulnerabilities = []
      
      app.app_files.each do |file|
        content = file.content
        
        # Check for common vulnerabilities
        vulnerabilities << "SQL injection risk" if content.match?(/query.*\+.*user/i)
        vulnerabilities << "XSS risk" if content.match?(/innerHTML|dangerouslySetInnerHTML/) && !content.match?(/sanitize/)
        vulnerabilities << "Exposed secrets" if content.match?(/api[_-]?key\s*[:=]\s*["'][\w]+["']/i)
        vulnerabilities << "Missing CORS config" if file.path.match?(/server/) && !content.match?(/cors/i)
      end
      
      score = vulnerabilities.empty? ? 100 : [0, 100 - (vulnerabilities.size * 25)].max
      { score: score, vulnerabilities: vulnerabilities.uniq }
    end
    
    def evaluate_performance(app)
      issues = []
      
      app.app_files.each do |file|
        content = file.content
        
        # Check for performance issues
        issues << "Missing React.memo" if file.path.match?(/component/i) && !content.match?(/React\.memo|useMemo/)
        issues << "No lazy loading" if file.path.match?(/App/) && !content.match?(/lazy|Suspense/)
        issues << "Large bundle" if file.path == 'package.json' && content.match?(/moment|lodash[^-]/)
      end
      
      score = issues.empty? ? 100 : [0, 100 - (issues.size * 20)].max
      { score: score, issues: issues.uniq }
    end
    
    def get_reviewer_opinion(app)
      prompt = <<~PROMPT
        Review this generated application code and provide a quality score (0-100) and specific feedback.
        
        Files:
        #{app.app_files.map { |f| "#{f.path}:\n#{f.content[0..500]}..." }.join("\n\n")}
        
        Evaluate:
        1. Code quality and best practices
        2. Security
        3. Performance
        4. Completeness
        5. User experience
        
        Provide a JSON response with score and feedback.
      PROMPT
      
      begin
        response = @client.chat(
          [{ role: "user", content: prompt }],
          model: EVALUATION_MODELS[:reviewer],
          temperature: 0.3,
          max_tokens: 1000
        )
        
        if response[:success]
          parse_json_response(response[:content])
        else
          { score: 0, error: response[:error] }
        end
      rescue => e
        { score: 0, error: e.message }
      end
    end
    
    def get_alternative_opinion(app)
      # Similar to reviewer but with different model for perspective
      prompt = <<~PROMPT
        Analyze this application from a user experience and business value perspective.
        Rate 0-100 and explain.
        
        App purpose: #{app.prompt}
        Tech stack: #{TECH_STACK.to_json}
        
        Brief file overview:
        #{app.app_files.pluck(:path).join(", ")}
        
        Return JSON with score and analysis.
      PROMPT
      
      begin
        response = @client.chat(
          [{ role: "user", content: prompt }],
          model: EVALUATION_MODELS[:alternative],
          temperature: 0.3,
          max_tokens: 500
        )
        
        if response[:success]
          parse_json_response(response[:content])
        else
          { score: 0, error: response[:error] }
        end
      rescue => e
        { score: 0, error: e.message }
      end
    end
    
    def get_improvement_suggestions(app, quality_scores)
      return [] unless quality_scores
      
      suggestions = []
      
      # Based on scores, suggest improvements
      if quality_scores[:code_quality][:score] < 80
        suggestions << "Improve code quality: Add error handling, loading states, and TypeScript"
      end
      
      if quality_scores[:security][:score] < 100
        suggestions << "Fix security issues: #{quality_scores[:security][:vulnerabilities].join(', ')}"
      end
      
      if quality_scores[:performance][:score] < 80
        suggestions << "Optimize performance: Add memoization, lazy loading, and bundle optimization"
      end
      
      # Get AI suggestions for prompt improvements
      ai_suggestions = get_ai_prompt_suggestions(app, quality_scores)
      suggestions.concat(ai_suggestions) if ai_suggestions
      
      suggestions
    end
    
    def get_ai_prompt_suggestions(app, scores)
      prompt = <<~PROMPT
        Based on these quality scores for a generated app:
        #{scores.to_json}
        
        Original prompt: #{app.prompt}
        
        Suggest 3 specific improvements to the generation prompt that would result in higher quality output.
        Return as a JSON array of strings.
      PROMPT
      
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :claude_4,
        temperature: 0.5,
        max_tokens: 500
      )
      
      if response[:success]
        result = parse_json_response(response[:content])
        result.is_a?(Array) ? result : []
      else
        []
      end
    rescue
      []
    end
    
    def calculate_overall_score(scores)
      weights = {
        code_quality: 0.3,
        completeness: 0.2,
        security: 0.25,
        performance: 0.15,
        reviewer_opinion: 0.05,
        alternative_opinion: 0.05
      }
      
      total = 0
      weights.each do |key, weight|
        if scores[key] && scores[key][:score]
          total += scores[key][:score] * weight
        end
      end
      
      total.round
    end
    
    def process_generation_result(app, result)
      # Extract and create files from AI response
      tool_call = result[:tool_calls].first
      return unless tool_call
      
      args = tool_call.dig('function', 'arguments')
      data = args.is_a?(String) ? JSON.parse(args) : args
      
      if data['files']
        data['files'].each do |file_info|
          app.app_files.create!(
            team: app.team,
            path: file_info['path'],
            content: file_info['content'],
            file_type: file_info['path'].split('.').last
          )
        end
      end
      
      app.update!(status: 'generated')
    end
    
    def process_update(app, message)
      # Simplified update processing
      coordinator = UnifiedAiCoordinator.new(app, message)
      
      begin
        coordinator.execute!
        { success: true, files_modified: app.app_files.count }
      rescue => e
        { success: false, errors: [e.message], files_modified: 0 }
      end
    end
    
    def evaluate_update_quality(app, message)
      # Similar to evaluate_quality but focused on the update
      {
        score: 80,  # Placeholder
        update_successful: true
      }
    end
    
    def generate_report
      puts "\n" + "="*60
      puts "📊 BENCHMARK REPORT"
      puts "="*60
      
      successful = @results.select { |r| r[:success] }
      failed = @results.reject { |r| r[:success] }
      
      puts "\n✅ Success Rate: #{successful.size}/#{@results.size}"
      puts "⏱️ Average Duration: #{@results.map { |r| r[:duration] }.sum / @results.size}s"
      
      if successful.any?
        avg_quality = successful.map { |r| r[:quality_scores]&.dig(:overall) || 0 }.sum / successful.size
        puts "⭐ Average Quality Score: #{avg_quality}/100"
      end
      
      puts "\n📝 Common Issues:"
      all_errors = @results.flat_map { |r| r[:errors] || [] }.compact
      all_errors.group_by(&:itself).transform_values(&:count).each do |error, count|
        puts "  - #{error} (#{count}x)"
      end
      
      puts "\n💡 Top Suggestions:"
      all_suggestions = @results.flat_map { |r| r[:suggestions] || [] }.compact
      all_suggestions.uniq.first(5).each do |suggestion|
        puts "  - #{suggestion}"
      end
      
      # Save detailed report
      save_detailed_report
    end
    
    def save_detailed_report
      report_path = Rails.root.join('tmp', "benchmark_#{Time.current.to_i}.json")
      File.write(report_path, JSON.pretty_generate({
        timestamp: Time.current,
        tech_stack: TECH_STACK,
        results: @results,
        summary: {
          total_tests: @results.size,
          successful: @results.count { |r| r[:success] },
          average_quality: @results.map { |r| r[:quality_scores]&.dig(:overall) || 0 }.sum / @results.size
        }
      }))
      
      puts "\n📁 Detailed report saved to: #{report_path}"
    end
    
    def parse_json_response(content)
      return {} unless content
      
      # Try to extract JSON from response
      json_match = content.match(/```(?:json)?\n?(.*?)```/m) || content.match(/\{.*\}/m)
      return {} unless json_match
      
      JSON.parse(json_match[1] || json_match[0])
    rescue JSON::ParserError
      {}
    end
  end
end