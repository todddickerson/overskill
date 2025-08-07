#!/usr/bin/env ruby
# Final test of the completely fixed orchestrator
# Run with: bin/rails runner test_final_fix.rb

ENV["VERBOSE_AI_LOGGING"] = "true"

puts "=" * 70
puts "🎉 FINAL TEST: COMPLETE ORCHESTRATOR FIX"
puts "=" * 70

begin
  # Get test setup
  team = Team.find_by(name: "AI Test Team")
  user = team&.memberships&.first&.user
  
  # Create final test app
  app = team.apps.create!(
    name: "Final Fix Test #{Time.current.to_i}",
    prompt: "Create a React counter app",
    status: 'generating',
    app_type: 'tool',
    framework: 'react',
    creator: team.memberships.first
  )
  
  puts "✅ Created final test app: #{app.name} (ID: #{app.id})"
  
  # Create message
  message = app.app_chat_messages.create!(
    user: user,
    role: 'user',
    content: "Create a simple React counter app with increment/decrement buttons, using TypeScript and Tailwind CSS."
  )
  
  puts "✅ Created message: #{message.id}"
  puts "🚀 Running FINAL TEST with all fixes..."
  
  start_time = Time.current
  
  begin
    Timeout.timeout(180) do
      orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
      orchestrator.execute!
    end
    
    duration = Time.current - start_time
    app.reload
    
    puts "\n🎯 FINAL RESULTS:"
    puts "=" * 50
    puts "⏱️  Duration: #{duration.round(1)}s"
    puts "📱 App status: #{app.status}"
    puts "📁 Files created: #{app.app_files.count}"
    
    if app.app_files.any?
      puts "\n✅ SUCCESS! Files created:"
      app.app_files.order(:path).each do |f|
        puts "   📄 #{f.path} (#{f.content.length} chars)"
      end
      
      # Check for React counter essentials
      essential_checks = {
        "HTML entry point" => app.app_files.exists?(path: "index.html"),
        "Package.json" => app.app_files.exists?(path: "package.json"),
        "Main TypeScript component" => app.app_files.exists?(path: "src/App.tsx"),
        "Entry point" => app.app_files.exists?(path: "src/main.tsx")
      }
      
      puts "\n📋 Essential Files Check:"
      essential_checks.each do |check, passed|
        status = passed ? "✅" : "❌"
        puts "   #{status} #{check}"
      end
      
      # Check App.tsx for counter functionality
      app_tsx = app.app_files.find_by(path: "src/App.tsx")
      if app_tsx
        content = app_tsx.content
        
        functionality_checks = {
          "useState hook" => content.include?("useState"),
          "Increment function" => content.match?(/increment|[+]{2}|\+\s*1/i),
          "Decrement function" => content.match?(/decrement|--|[-]\s*1/i),
          "Button elements" => content.match?(/<button/i),
          "TypeScript types" => content.include?(": number") || content.include?("React.")
        }
        
        puts "\n⚙️  Counter Functionality Check:"
        functionality_checks.each do |check, passed|
          status = passed ? "✅" : "❌"
          puts "   #{status} #{check}"
        end
        
        total_passed = essential_checks.values.count(true) + functionality_checks.values.count(true)
        total_checks = essential_checks.count + functionality_checks.count
        success_rate = (total_passed.to_f / total_checks * 100).round(1)
        
        puts "\n🎯 Overall Success Rate: #{success_rate}% (#{total_passed}/#{total_checks})"
        
        if success_rate >= 80
          puts "🏆 EXCELLENT! The orchestrator is working properly!"
        elsif success_rate >= 60
          puts "✅ GOOD! Minor issues but functional."
        else
          puts "⚠️  NEEDS IMPROVEMENT! Some functionality missing."
        end
        
      end
      
    else
      puts "❌ FAILED! No files were created."
    end
    
  rescue Timeout::Error
    puts "❌ Timed out after 3 minutes"
    app.reload
    puts "   Files at timeout: #{app.app_files.count}"
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
  
rescue => e
  puts "❌ Setup error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 70
puts "🏁 FINAL TEST COMPLETED"
puts "=" * 70