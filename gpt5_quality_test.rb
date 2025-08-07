#!/usr/bin/env ruby
require_relative 'config/environment'
require 'json'
require 'colorize'

puts "🎯 GPT-5 Quality Test - Professional Standards".colorize(:green)
puts "=" * 50

# Ensure OpenAI API key is configured  
unless ENV['OPENAI_API_KEY'] && ENV['OPENAI_API_KEY'] != "dummy-key"
  puts "❌ Please set OPENAI_API_KEY environment variable"
  exit 1
end

def test_professional_quality(app_type, prompt)
  puts "\n📝 Testing: #{app_type}".colorize(:cyan)
  puts "🎯 Prompt: #{prompt}".colorize(:blue)
  puts "⏱️  Starting professional generation...".colorize(:blue)
  
  start_time = Time.current
  
  # Professional-grade tools matching AI standards
  tools = [
    {
      type: "function",
      function: {
        name: "create_file",
        description: "Create a professional app file following OverSkill standards",
        parameters: {
          type: "object",
          properties: {
            filename: { type: "string", description: "File path (e.g. 'index.html', 'src/App.jsx', 'src/components/Counter.jsx')" },
            content: { type: "string", description: "Professional-grade file content" }
          },
          required: ["filename", "content"]
        }
      }
    },
    {
      type: "function",
      function: {
        name: "finish_app", 
        description: "Mark professional app as complete",
        parameters: {
          type: "object",
          properties: {
            summary: { type: "string", description: "Summary of professional features implemented" },
            quality_score: { type: "integer", minimum: 1, maximum: 10, description: "Self-assessed quality score (1-10)" }
          },
          required: ["summary", "quality_score"]
        }
      }
    }
  ]

  # Load AI standards
  ai_standards = File.read('/Users/todddickerson/src/GitHub/overskill/AI_APP_STANDARDS.md')
  
  messages = [
    {
      role: "system",
      content: """You are building PROFESSIONAL-GRADE web applications for OverSkill.app that rival Lovable.dev and Claude Code in quality.

#{ai_standards}

CRITICAL REQUIREMENTS:
1. Create proper multi-file React architecture (NOT single HTML file)
2. Use Tailwind CSS for professional design with sophisticated color palettes
3. Include loading states, error handling, and smooth animations  
4. Implement accessibility-first approach with semantic HTML
5. Add mobile-first responsive design
6. Include Supabase integration architecture when needed
7. Use Lucide icons and professional typography (Inter font)

QUALITY STANDARDS:
- Every component must be production-ready, not a prototype
- Design should be visually sophisticated with modern UI patterns
- Code architecture should be clean and feature-based
- User experience should be smooth with proper state management"""
    },
    {
      role: "user",
      content: prompt
    }
  ]

  begin
    client = Ai::OpenRouterClient.new
    files_created = []
    max_iterations = 8
    iteration = 0
    quality_score = nil
    
    while iteration < max_iterations
      iteration += 1
      puts "   Professional iteration #{iteration}...".colorize(:light_blue)
      
      response = client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
      
      unless response[:success]
        puts "❌ GPT-5 failed: #{response[:error]}".colorize(:red)
        return { success: false, error: response[:error] }
      end
      
      # Add response to conversation
      messages << {
        role: "assistant",
        content: response[:content],
        tool_calls: response[:tool_calls]
      }
      
      # Process tool calls
      if response[:tool_calls]
        tool_results = []
        
        response[:tool_calls].each do |tool_call|
          function_name = tool_call["function"]["name"]
          args = JSON.parse(tool_call["function"]["arguments"])
          
          case function_name
          when "create_file"
            filename = args["filename"]
            content = args["content"]
            files_created << { filename: filename, content: content, size: content.length }
            puts "     ✅ Created: #{filename} (#{content.length} chars)".colorize(:green)
            
            tool_results << {
              tool_call_id: tool_call["id"],
              role: "tool",
              content: JSON.generate({ success: true, message: "Professional file created: #{filename}" })
            }
            
          when "finish_app"
            quality_score = args["quality_score"]
            puts "     🎯 Quality Score: #{quality_score}/10".colorize(quality_score >= 8 ? :green : :yellow)
            puts "     ✅ App completed: #{args['summary']}".colorize(:green)
            tool_results << {
              tool_call_id: tool_call["id"],
              role: "tool",
              content: JSON.generate({ success: true, message: "Professional app marked complete" })
            }
          end
        end
        
        # Add tool results to conversation
        messages += tool_results
      else
        # No tool calls, done
        break
      end
    end
    
    elapsed = Time.current - start_time
    
    # Quality Analysis
    puts "\n📊 Professional Quality Analysis:".colorize(:cyan)
    puts "   ⏱️  Time: #{elapsed.round(2)}s".colorize(:blue)
    puts "   📁 Files: #{files_created.length}".colorize(:blue)
    puts "   🎯 AI Quality Score: #{quality_score || 'N/A'}/10".colorize(:blue)
    
    # Architecture analysis
    has_proper_structure = files_created.any? { |f| f[:filename].include?('src/') }
    has_components = files_created.any? { |f| f[:filename].include?('components/') }  
    has_styles = files_created.any? { |f| f[:filename].include?('.css') }
    total_chars = files_created.sum { |f| f[:size] }
    
    puts "   🏗️  Multi-file architecture: #{has_proper_structure ? '✅' : '❌'}".colorize(:blue)
    puts "   🧩 Component organization: #{has_components ? '✅' : '❌'}".colorize(:blue)
    puts "   🎨 Dedicated styles: #{has_styles ? '✅' : '❌'}".colorize(:blue)
    puts "   📈 Total code: #{total_chars} characters".colorize(:blue)
    
    # Check for professional features in code
    all_content = files_created.map { |f| f[:content] }.join(" ").downcase
    
    quality_indicators = {
      'tailwind_css' => all_content.include?('tailwind'),
      'lucide_icons' => all_content.include?('lucide'),
      'loading_states' => all_content.include?('loading'),
      'error_handling' => all_content.include?('error'),
      'accessibility' => all_content.include?('aria-') || all_content.include?('role='),
      'animations' => all_content.include?('transition') || all_content.include?('animate'),
      'responsive' => all_content.include?('sm:') || all_content.include?('md:') || all_content.include?('lg:'),
      'supabase_ready' => all_content.include?('supabase')
    }
    
    puts "\n🎯 Professional Features Analysis:".colorize(:cyan)
    quality_indicators.each do |feature, present|
      status = present ? "✅" : "❌"
      color = present ? :green : :red
      puts "   #{status} #{feature.humanize}".colorize(color)
    end
    
    # Overall quality assessment
    quality_percentage = (quality_indicators.values.count(true) / quality_indicators.length.to_f * 100).round(1)
    architecture_score = [has_proper_structure, has_components, has_styles].count(true) * 33.33
    
    overall_quality = (quality_percentage + architecture_score) / 2
    
    puts "\n🏆 OVERALL QUALITY ASSESSMENT:".colorize(:yellow)
    puts "   Professional Features: #{quality_percentage}%".colorize(:blue)
    puts "   Architecture Score: #{architecture_score.round(1)}%".colorize(:blue) 
    puts "   📊 Combined Quality: #{overall_quality.round(1)}%".colorize(overall_quality >= 80 ? :green : :red)
    
    if files_created.any?
      puts "   ✅ SUCCESS: Professional app generated!".colorize(:green)
      return { 
        success: true, 
        files: files_created.length, 
        time: elapsed,
        quality_score: quality_score,
        architecture_quality: architecture_score,
        feature_quality: quality_percentage,
        overall_quality: overall_quality,
        files_data: files_created
      }
    else
      puts "   ❌ FAILURE: No professional files created".colorize(:red)
      return { success: false }
    end
    
  rescue => e
    puts "❌ Exception: #{e.message}".colorize(:red)
    return { success: false, error: e.message }
  end
end

# Test professional-grade apps
puts "🏆 Testing Professional-Grade AI Generation".colorize(:yellow)
puts "-" * 50

# Test 1: Professional Counter App
result1 = test_professional_quality(
  "Professional Counter App",
  "Create a professional-grade counter application with sophisticated design, smooth animations, multiple themes, keyboard shortcuts, and excellent accessibility. This should rival apps from Lovable.dev in quality and visual appeal."
)

# Test 2: Professional Todo App with Auth
result2 = test_professional_quality(
  "Professional Todo with Auth",
  "Create a comprehensive todo list application with user authentication, data persistence via Supabase, advanced filtering, drag-and-drop reordering, categories, due dates, and a beautiful modern interface. Include proper loading states and error handling."
)

# Final Quality Report
puts "\n" + "=" * 60
puts "🎯 PROFESSIONAL QUALITY SUMMARY".colorize(:cyan)
puts "=" * 60

results = [result1, result2].compact.select { |r| r[:success] }

if results.any?
  avg_quality = results.sum { |r| r[:overall_quality] || 0 } / results.length
  avg_time = results.sum { |r| r[:time] } / results.length
  
  puts "📈 Success Rate: #{results.length}/2 (#{results.length * 50}%)".colorize(:blue)
  puts "🎯 Average Professional Quality: #{avg_quality.round(1)}%".colorize(avg_quality >= 80 ? :green : :red)
  puts "⏱️  Average Generation Time: #{avg_time.round(1)}s".colorize(:blue)
  puts "📁 Average Files per App: #{results.sum { |r| r[:files] } / results.length.to_f}".colorize(:blue)
  
  quality_status = case avg_quality
  when 90..100 then "🏆 EXCELLENT"
  when 80..89 then "✅ GOOD" 
  when 70..79 then "⚠️ ACCEPTABLE"
  else "❌ NEEDS IMPROVEMENT"
  end
  
  puts "\n💡 Quality Assessment: #{quality_status}".colorize(:yellow)
else
  puts "❌ No successful professional apps generated".colorize(:red)
end

puts "\n" + "=" * 60