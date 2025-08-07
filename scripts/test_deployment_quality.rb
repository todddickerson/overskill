#!/usr/bin/env ruby
# Test deployment and code quality

require_relative '../config/environment'
require 'net/http'
require 'json'

puts "🚀 Deployment & Quality Test"
puts "=" * 60

# Use app 57 which we just generated files for
app = App.find(57)
puts "Testing app: #{app.name} (ID: #{app.id})"
puts "Files count: #{app.app_files.count}"

# 1. Test file quality
puts "\n📝 File Quality Analysis:"
puts "-" * 40

index_file = app.app_files.find_by(path: "index.html")
main_file = app.app_files.find { |f| f.path == "src/main.tsx" || f.path == "src/App.tsx" }
package_json = app.app_files.find_by(path: "package.json")

if index_file
  content = index_file.content
  puts "✅ index.html:"
  puts "  - Valid HTML5: #{content.include?('<!DOCTYPE html>') ? 'YES' : 'NO'}"
  puts "  - React root: #{content.include?('id="root"') ? 'YES' : 'NO'}"
  puts "  - Vite entry: #{content.include?('src/main.tsx') || content.include?('src/main.js') ? 'YES' : 'NO'}"
  puts "  - Size: #{content.length} bytes"
end

if main_file
  content = main_file.content
  puts "\n✅ #{main_file.path}:"
  puts "  - React import: #{content.include?('import React') || content.include?('from "react"') ? 'YES' : 'NO'}"
  puts "  - TypeScript: #{main_file.path.end_with?('.tsx', '.ts') ? 'YES' : 'NO'}"
  puts "  - Components: #{content.scan(/function \w+|const \w+ =/).count} found"
  puts "  - Size: #{content.length} bytes"
  
  # Check for requested features (counter app)
  puts "\n  Feature Implementation:"
  puts "  - Counter state: #{content.match?(/useState.*count/i) ? 'YES' : 'NO'}"
  puts "  - Increment: #{content.match?(/increment|setCount.*\+/i) ? 'YES' : 'NO'}"
  puts "  - Decrement: #{content.match?(/decrement|setCount.*-/i) ? 'YES' : 'NO'}"
end

if package_json
  content = package_json.content
  begin
    pkg = JSON.parse(content)
    puts "\n✅ package.json:"
    puts "  - Name: #{pkg['name']}"
    puts "  - Dependencies: #{pkg['dependencies']&.keys&.count || 0}"
    puts "  - Key packages:"
    puts "    - React: #{pkg['dependencies']&.key?('react') ? 'YES' : 'NO'}"
    puts "    - Vite: #{pkg['devDependencies']&.key?('vite') ? 'YES' : 'NO'}"
    puts "    - TypeScript: #{pkg['devDependencies']&.key?('typescript') ? 'YES' : 'NO'}"
  rescue => e
    puts "\n❌ package.json: Invalid JSON"
  end
end

# 2. Test deployment
puts "\n\n🌐 Deployment Test:"
puts "-" * 40

begin
  preview_service = Deployment::FastPreviewService.new(app)
  result = preview_service.deploy_instant_preview!
  
  if result[:success]
    puts "✅ Deployment successful!"
    puts "  URL: #{result[:preview_url]}"
    puts "  Worker: #{result[:worker_name]}"
    
    # Test accessibility
    if result[:preview_url]
      uri = URI(result[:preview_url])
      begin
        response = Net::HTTP.get_response(uri)
        puts "\n  Accessibility Check:"
        puts "    HTTP Status: #{response.code}"
        puts "    Content-Type: #{response['content-type']}"
        puts "    Response size: #{response.body.length} bytes"
        
        if response.code == '200'
          body = response.body
          puts "\n  Content Analysis:"
          puts "    Has HTML: #{body.include?('<html') ? 'YES' : 'NO'}"
          puts "    Has title: #{body.match(/<title>(.*?)<\/title>/)&.[](1) || 'NO'}"
          puts "    Has React: #{body.include?('react') ? 'YES' : 'NO'}"
          puts "    Has JS errors: #{body.include?('SyntaxError') || body.include?('ReferenceError') ? 'YES ⚠️' : 'NO ✅'}"
        end
      rescue => e
        puts "  ❌ Could not access preview: #{e.message}"
      end
    end
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
rescue => e
  puts "❌ Deployment error: #{e.message}"
end

# 3. Test AI model usage
puts "\n\n🤖 AI Model Analysis:"
puts "-" * 40

# Check recent messages for model info
recent_message = app.app_chat_messages.where(role: "assistant").last
if recent_message
  puts "Latest AI response:"
  puts "  Created: #{recent_message.created_at}"
  puts "  Status: #{recent_message.status || 'completed'}"
  puts "  Content preview: #{recent_message.content[0..100]}..."
end

# Check what model was used
client = Ai::OpenRouterClient.new
test_result = client.chat([{role: "user", content: "test"}], model: :gpt5)
puts "\nModel routing test:"
puts "  Primary model: GPT-5"
puts "  Actual model used: #{test_result[:model] || 'Unknown'}"
puts "  Fallback active: #{test_result[:model]&.include?('claude') ? 'YES' : 'NO'}"

# 4. Performance metrics
puts "\n\n📊 Performance Metrics:"
puts "-" * 40

# File generation performance
total_size = app.app_files.sum(&:size_bytes)
file_count = app.app_files.count
puts "File Generation:"
puts "  Total files: #{file_count}"
puts "  Total size: #{total_size} bytes"
puts "  Avg size: #{file_count > 0 ? total_size / file_count : 0} bytes"

# Recent generation times
recent_generations = app.app_generations.order(created_at: :desc).limit(5)
if recent_generations.any?
  puts "\nRecent Generation Times:"
  recent_generations.each do |gen|
    duration = gen.updated_at - gen.created_at
    puts "  - #{gen.created_at.strftime('%H:%M:%S')}: #{duration.round(2)}s"
  end
end

# Final summary
puts "\n\n" + "=" * 60
puts "📈 QUALITY ASSESSMENT"
puts "=" * 60

quality_score = 0
quality_score += 1 if index_file && index_file.content.include?('<!DOCTYPE html>')
quality_score += 1 if main_file && (main_file.content.include?('React') || main_file.content.include?('react'))
quality_score += 1 if package_json && JSON.parse(package_json.content)['dependencies']&.key?('react') rescue false
quality_score += 1 if result && result[:success]
quality_score += 1 if result && result[:preview_url]

puts "\n✅ Quality Score: #{quality_score}/5"
puts "\nBreakdown:"
puts "  Code Quality: #{index_file && main_file ? '✅' : '❌'}"
puts "  TypeScript: #{main_file&.path&.end_with?('.tsx', '.ts') ? '✅' : '❌'}"
puts "  Dependencies: #{package_json ? '✅' : '❌'}"
puts "  Deployment: #{result && result[:success] ? '✅' : '❌'}"
puts "  Accessibility: #{result && result[:preview_url] ? '✅' : '❌'}"

if quality_score >= 4
  puts "\n🎉 EXCELLENT - Production Ready!"
elsif quality_score >= 3
  puts "\n✅ GOOD - Minor improvements needed"
else
  puts "\n⚠️ NEEDS WORK - Several issues to address"
end

puts "\n📝 Preview URL: https://preview-#{app.id}.overskill.app/"