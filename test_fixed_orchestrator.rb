#!/usr/bin/env ruby
# Test the fixed orchestrator end-to-end
# Run with: bin/rails runner test_fixed_orchestrator.rb

ENV["VERBOSE_AI_LOGGING"] = "true"

puts "=" * 70
puts "🚀 TESTING FIXED ORCHESTRATOR END-TO-END"
puts "=" * 70

begin
  # Create fresh test app
  team = Team.find_by(name: "AI Test Team")
  user = team&.memberships&.first&.user
  
  if !team || !user
    puts "❌ No test setup found. Run setup first."
    exit 1
  end
  
  # Create new test app
  app = team.apps.create!(
    name: "Fixed Test #{Time.current.to_i}",
    prompt: "Create a React counter app with increment and decrement buttons",
    status: 'generating',
    app_type: 'tool',
    framework: 'react', 
    creator: team.memberships.first
  )
  
  puts "✅ Created fresh app: #{app.name} (ID: #{app.id})"
  
  # Create message
  message = app.app_chat_messages.create!(
    user: user,
    role: 'user',
    content: "Create a simple React counter app with increment and decrement buttons. Use TypeScript and Tailwind CSS."
  )
  
  puts "✅ Created message: #{message.id}"
  puts "🤖 Testing fixed orchestrator with improved token allocation..."
  
  start_time = Time.current
  
  begin
    # Test the orchestrator with timeout
    Timeout.timeout(180) do
      orchestrator = Ai::AppUpdateOrchestratorV2.new(message)
      orchestrator.execute!
    end
    
    duration = Time.current - start_time
    app.reload
    
    puts "✅ Orchestrator completed in #{duration.round(1)}s"
    puts "   App status: #{app.status}"
    puts "   Files created: #{app.app_files.count}"
    
    if app.app_files.any?
      puts "   Created files:"
      app.app_files.order(:path).each { |f| puts "     - #{f.path} (#{f.content.length} chars)" }
      
      # Check if we have essential React files
      essential_files = ['index.html', 'package.json', 'src/App.tsx', 'src/main.tsx']
      found_files = app.app_files.pluck(:path)
      
      puts "\n   Essential file check:"
      essential_files.each do |file|
        status = found_files.include?(file) ? "✅" : "❌"
        puts "     #{status} #{file}"
      end
      
      # Check if App.tsx contains counter logic
      app_tsx = app.app_files.find_by(path: "src/App.tsx")
      if app_tsx
        content = app_tsx.content
        counter_checks = {
          "useState hook" => content.include?("useState"),
          "increment function" => content.match?(/increment|[+]{2}|\+\s*1/i),
          "decrement function" => content.match?(/decrement|--|[-]\s*1/i),
          "button elements" => content.match?(/<button/i),
          "TypeScript" => content.include?("React.") || content.include?(": number") || content.include?("interface")
        }
        
        puts "\n   Counter functionality check:"
        counter_checks.each do |check, passed|
          status = passed ? "✅" : "❌"
          puts "     #{status} #{check}"
        end
      end
      
    else
      puts "   ❌ No files were created!"
    end
    
    # Check messages for errors
    puts "\n   Message analysis:"
    recent_messages = app.app_chat_messages.order(created_at: :desc).limit(10)
    error_count = 0
    success_count = 0
    
    recent_messages.each do |msg|
      if msg.status == 'failed'
        error_count += 1
        puts "     ❌ Failed: #{msg.content[0..60]}..."
      elsif msg.status == 'completed'
        success_count += 1
        puts "     ✅ Success: #{msg.content[0..60]}..."
      end
    end
    
    puts "   Summary: #{success_count} successful, #{error_count} failed messages"
    
  rescue Timeout::Error
    puts "❌ Orchestrator timed out after 3 minutes"
    app.reload
    puts "   Status at timeout: #{app.status}"
    puts "   Files at timeout: #{app.app_files.count}"
  rescue => e
    puts "❌ Orchestrator error: #{e.message}"
    puts e.backtrace.first(3).join("\n")
  end
  
rescue => e
  puts "❌ Test error: #{e.message}"
  puts e.backtrace.first(3).join("\n")
end

puts "\n" + "=" * 70
puts "Fixed orchestrator test completed"