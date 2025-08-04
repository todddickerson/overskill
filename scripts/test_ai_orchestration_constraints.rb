#!/usr/bin/env ruby
# Test script to verify AI orchestration properly understands OverSkill platform constraints

require_relative '../config/environment'

class AiOrchestrationConstraintsTest
  def initialize
    @client = Ai::OpenRouterClient.new
    @test_results = []
  end

  def run_all_tests
    puts "🧪 Testing AI Orchestration Platform Constraints Understanding"
    puts "=" * 60
    
    # Test 1: Analysis prompt should understand file-based constraints
    test_analysis_constraints
    
    # Test 2: Execution prompt should enforce vanilla technologies
    test_execution_constraints
    
    # Test 3: Fix prompt should use client-side debugging
    test_fix_constraints
    
    # Summary
    print_summary
  end

  private

  def test_analysis_constraints
    puts "\n📋 Test 1: Analysis Prompt - Platform Constraints Understanding"
    puts "-" * 50
    
    # Simulate a request that might tempt the AI to suggest forbidden approaches
    test_request = "The app isn't working and I'm getting JavaScript errors. Can you help me debug and fix it?"
    
    current_files = [
      { path: "index.html", type: "html" },
      { path: "app.js", type: "javascript" },
      { path: "styles.css", type: "css" }
    ]
    
    app_context = {
      name: "Test App",
      type: "tool", 
      framework: "react"
    }
    
    puts "Request: #{test_request}"
    puts "Sending analysis request..."
    
    begin
      response = @client.analyze_app_update_request(
        request: test_request,
        current_files: current_files,
        app_context: app_context
      )
      
      if response[:success]
        plan = response[:plan]
        
        puts "✅ Analysis successful"
        puts "Analysis: #{plan[:analysis]}"
        puts "Approach: #{plan[:approach]}"
        
        # Check if the response contains forbidden approaches (excluding legitimate exceptions)
        forbidden_terms = ["npm install", "package.json", "node_modules", "webpack", "build process", "git clone", "dev server"]
        approved_terms = ["tailwind", "cdn", "vanilla", "client-side"]
        
        approach_text = plan[:approach].to_s.downcase
        analysis_text = plan[:analysis].to_s.downcase
        combined_text = "#{approach_text} #{analysis_text}"
        
        forbidden_found = forbidden_terms.any? { |term| combined_text.include?(term) }
        has_approved_approaches = approved_terms.any? { |term| combined_text.include?(term) }
        
        if forbidden_found
          puts "❌ FAILURE: Response contains forbidden approaches"
          @test_results << { test: "Analysis Constraints", status: "FAILED", reason: "Contains forbidden terms" }
        else
          puts "✅ SUCCESS: Response adheres to platform constraints"
          @test_results << { test: "Analysis Constraints", status: "PASSED", reason: "No forbidden approaches detected" }
        end
        
        # Check if debugging approach is client-side focused
        if approach_text.include?("console") || approach_text.include?("browser") || approach_text.include?("devtools")
          puts "✅ Good: Mentions client-side debugging techniques"
        else
          puts "⚠️  Warning: Doesn't explicitly mention client-side debugging"
        end
        
      else
        puts "❌ Analysis failed: #{response[:error]}"
        @test_results << { test: "Analysis Constraints", status: "ERROR", reason: response[:error] }
      end
      
    rescue => e
      puts "❌ Exception during analysis test: #{e.message}"
      @test_results << { test: "Analysis Constraints", status: "ERROR", reason: e.message }
    end
  end

  def test_execution_constraints
    puts "\n⚙️  Test 2: Execution Prompt - Vanilla Technology Enforcement"
    puts "-" * 50
    
    # Create a plan that might tempt the AI to use forbidden technologies
    test_plan = {
      analysis: "User wants to add interactive features to their app",
      approach: "Add client-side interactivity using vanilla JavaScript",
      steps: [
        { description: "Add event listeners for user interactions", files_affected: ["app.js"] },
        { description: "Update UI with DOM manipulation", files_affected: ["app.js", "styles.css"] }
      ]
    }
    
    puts "Plan: #{test_plan[:analysis]}"
    puts "Sending execution request..."
    
    begin
      response = @client.execute_app_update(test_plan)
      
      if response[:success]
        changes = response[:changes]
        
        puts "✅ Execution successful"
        puts "Summary: #{changes[:summary]}"
        
        # Check generated files for forbidden content (but allow approved CDN usage)
        forbidden_patterns = [
          /import\s+.+\s+from\s+['"][^h]/,  # ES6 imports (but not from https:// CDNs)
          /require\s*\(/,
          /npm\s+install/,
          /package\.json/,
          /webpack/,
          /babel/,
          /typescript/,
          /@import\s+url\([^h]/  # CSS imports (but not from https:// CDNs)
        ]
        
        # Approved patterns that are allowed
        approved_patterns = [
          /https:\/\/cdn\.tailwindcss\.com/,
          /https:\/\/fonts\.googleapis\.com/,
          /https:\/\/unpkg\.com/,
          /https:\/\/cdn\.jsdelivr\.net/
        ]
        
        files_content = changes[:files]&.map { |f| f[:content] }&.join(" ") || ""
        
        forbidden_found = forbidden_patterns.any? { |pattern| files_content.match?(pattern) }
        has_approved_cdns = approved_patterns.any? { |pattern| files_content.match?(pattern) }
        
        if forbidden_found
          puts "❌ FAILURE: Generated code contains forbidden patterns"
          @test_results << { test: "Execution Constraints", status: "FAILED", reason: "Contains forbidden code patterns" }
        else
          puts "✅ SUCCESS: Generated code uses only vanilla technologies"
          @test_results << { test: "Execution Constraints", status: "PASSED", reason: "Clean vanilla code generated" }
        end
        
        # Check for proper error handling
        if files_content.include?("try") && files_content.include?("catch")
          puts "✅ Good: Includes error handling"
        else
          puts "⚠️  Warning: No explicit error handling detected"
        end
        
      else
        puts "❌ Execution failed: #{response[:error]}"
        @test_results << { test: "Execution Constraints", status: "ERROR", reason: response[:error] }
      end
      
    rescue => e
      puts "❌ Exception during execution test: #{e.message}"
      @test_results << { test: "Execution Constraints", status: "ERROR", reason: e.message }
    end
  end

  def test_fix_constraints
    puts "\n🔧 Test 3: Fix Prompt - Client-Side Debugging Focus"
    puts "-" * 50
    
    # Simulate issues that should be fixed with client-side approaches
    test_issues = [
      {
        severity: :error,
        title: "JavaScript Reference Error",
        description: "Cannot read property of undefined",
        file: "app.js"
      },
      {
        severity: :warning,
        title: "Missing DOM element",
        description: "Element with ID 'container' not found",
        file: "app.js"
      }
    ]
    
    current_files = [
      {
        path: "app.js",
        content: "function initApp() { document.getElementById('container').innerHTML = 'Hello'; }"
      }
    ]
    
    puts "Issues: #{test_issues.length} JavaScript errors"
    puts "Sending fix request..."
    
    begin
      response = @client.fix_app_issues(
        issues: test_issues,
        current_files: current_files
      )
      
      if response[:success]
        changes = response[:changes]
        
        puts "✅ Fix successful"
        puts "Summary: #{changes[:summary]}"
        
        # Check that fixes use client-side debugging approaches
        fixes_text = changes[:fixes]&.map { |f| f[:solution] }&.join(" ").to_s.downcase
        files_content = changes[:files]&.map { |f| f[:content] }&.join(" ") || ""
        
        client_side_approaches = ["console.log", "try-catch", "if (", "document.", "error handling"]
        forbidden_approaches = ["npm install", "build", "server", "node", "git"]
        
        has_client_side = client_side_approaches.any? { |approach| fixes_text.include?(approach) || files_content.include?(approach) }
        has_forbidden = forbidden_approaches.any? { |approach| fixes_text.include?(approach) }
        
        if has_forbidden
          puts "❌ FAILURE: Fix suggestions contain forbidden approaches"
          @test_results << { test: "Fix Constraints", status: "FAILED", reason: "Contains forbidden fix approaches" }
        elsif has_client_side
          puts "✅ SUCCESS: Fixes use appropriate client-side debugging"
          @test_results << { test: "Fix Constraints", status: "PASSED", reason: "Uses client-side debugging approaches" }
        else
          puts "⚠️  WARNING: Fixes don't explicitly mention client-side debugging"
          @test_results << { test: "Fix Constraints", status: "WARNING", reason: "No clear client-side debugging mentioned" }
        end
        
      else
        puts "❌ Fix failed: #{response[:error]}"
        @test_results << { test: "Fix Constraints", status: "ERROR", reason: response[:error] }
      end
      
    rescue => e
      puts "❌ Exception during fix test: #{e.message}"
      @test_results << { test: "Fix Constraints", status: "ERROR", reason: e.message }
    end
  end

  def print_summary
    puts "\n📊 Test Results Summary"
    puts "=" * 60
    
    passed = @test_results.count { |r| r[:status] == "PASSED" }
    failed = @test_results.count { |r| r[:status] == "FAILED" }
    warnings = @test_results.count { |r| r[:status] == "WARNING" }
    errors = @test_results.count { |r| r[:status] == "ERROR" }
    
    @test_results.each do |result|
      status_emoji = case result[:status]
                     when "PASSED" then "✅"
                     when "FAILED" then "❌"
                     when "WARNING" then "⚠️"
                     when "ERROR" then "💥"
                     end
      
      puts "#{status_emoji} #{result[:test]}: #{result[:status]} - #{result[:reason]}"
    end
    
    puts "\nOverall Results:"
    puts "✅ Passed: #{passed}"
    puts "❌ Failed: #{failed}"
    puts "⚠️  Warnings: #{warnings}"
    puts "💥 Errors: #{errors}"
    
    if failed == 0 && errors == 0
      puts "\n🎉 SUCCESS: AI orchestration properly understands OverSkill constraints!"
    elsif failed > 0
      puts "\n⚠️  ISSUES FOUND: AI orchestration needs further constraint refinement"
    else
      puts "\n💥 ERRORS: Technical issues prevent proper testing"
    end
    
    puts "\n💡 Recommendations:"
    if failed > 0
      puts "- Review and strengthen constraint prompts in OpenRouterClient"
      puts "- Add more explicit forbidden approach examples"
      puts "- Consider adding validation layer to catch forbidden suggestions"
    end
    
    if warnings > 0
      puts "- Consider adding more specific client-side debugging guidance"
      puts "- Include more examples of proper debugging approaches"
    end
    
    if passed > 0
      puts "- Working constraints should be maintained and monitored"
      puts "- Consider adding automated tests to prevent regression"
    end
  end
end

# Run the test if this script is executed directly
if __FILE__ == $0
  test_runner = AiOrchestrationConstraintsTest.new
  test_runner.run_all_tests
end