#!/usr/bin/env ruby

# Test script for logo generation functionality
require_relative 'config/environment'

# Find a test app or create one
app = App.first || begin
  team = Team.first
  if team
    App.create!(
      name: "Test Logo App",
      description: "A test application for logo generation",
      team: team,
      creator: team.memberships.first,
      prompt: "Create a todo list app with categories and due dates",
      app_type: "tool",
      framework: "react",
      status: "published"
    )
  else
    puts "❌ No team found. Please create a team first."
    exit 1
  end
end

puts "🧪 Testing logo generation for app: #{app.name}"
puts "📝 App description: #{app.description}"
puts "🔧 App prompt: #{app.prompt}"
puts

# Test the OpenAI client directly
puts "1️⃣ Testing OpenAI client initialization..."
begin
  client = Ai::OpenaiClient.new
  puts "✅ OpenAI client initialized successfully"
rescue => e
  puts "❌ Failed to initialize OpenAI client: #{e.message}"
  exit 1
end

# Test prompt building
puts "\n2️⃣ Testing logo prompt generation..."
begin
  # Access the private method for testing
  prompt = client.send(:build_logo_prompt, app.name, app.description)
  puts "✅ Logo prompt generated successfully"
  puts "📋 Generated prompt:"
  puts "=" * 50
  puts prompt
  puts "=" * 50
rescue => e
  puts "❌ Failed to generate logo prompt: #{e.message}"
  exit 1
end

# Test the logo generator service
puts "\n3️⃣ Testing logo generator service..."
begin
  service = Ai::LogoGeneratorService.new(app)
  puts "✅ Logo generator service initialized"
  
  # Check if we already have a logo
  if app.logo.attached?
    puts "⚠️  App already has a logo attached. Removing for test..."
    app.logo.purge
  end
  
  puts "🎨 Starting logo generation (this may take 30-60 seconds)..."
  result = service.generate_logo
  
  if result[:success]
    puts "✅ Logo generation completed successfully!"
    puts "💾 Logo attached to app: #{app.logo.attached?}"
    puts "📏 Logo filename: #{app.logo.filename}" if app.logo.attached?
    puts "🏷️  Logo content type: #{app.logo.content_type}" if app.logo.attached?
    
    if app.logo_prompt.present?
      puts "📝 Revised AI prompt:"
      puts app.logo_prompt
    end
  else
    puts "❌ Logo generation failed: #{result[:error]}"
    exit 1
  end
  
rescue => e
  puts "❌ Logo generation service error: #{e.message}"
  puts "🔍 Backtrace:"
  puts e.backtrace.first(5).join("\n")
  exit 1
end

puts "\n🎉 Logo generation test completed successfully!"
puts "🌐 You can view the app at: http://localhost:3000/account/apps/#{app.id}/editor"