#!/usr/bin/env ruby
require_relative 'config/environment'

puts "\n🔧 Simple Generation Test"
puts "="*40

# Create test app with user
user = User.first
if !user
  puts "❌ No users found. Creating test user..."
  user = User.create!(
    email: "test@example.com",
    password: "password123",
    password_confirmation: "password123",
    first_name: "Test",
    last_name: "User"
  )
end

team = user.teams.first || Team.create!(name: "Test Team")
membership = team.memberships.find_by(user: user)
if !membership
  membership = team.memberships.create!(user: user, role_ids: ['admin'])
end

app = App.create!(
  name: "Test App #{Time.current.to_i}",
  prompt: "Simple todo app with React and TypeScript",
  team: team,
  creator: membership,
  status: 'draft'
)

puts "📝 Created test app: #{app.id}"

# Test StructuredAppGenerator
puts "\n🤖 Testing StructuredAppGenerator..."
generator = Ai::StructuredAppGenerator.new
result = generator.generate("Create a simple todo app with add/delete functionality", app_type: "tool")

puts "\nResult:"
puts "Success: #{result[:success]}"
puts "Error: #{result[:error]}" if result[:error]
puts "Files: #{result[:files]&.size || 0}"

if result[:success] && result[:files]
  puts "\n📁 Generated Files:"
  result[:files].first(3).each do |file|
    puts "  - #{file['path']} (#{file['content']&.size || 0} chars)"
  end
  
  # Test creating app files
  puts "\n💾 Creating app files..."
  result[:files].each do |file_data|
    app.app_files.create!(
      path: file_data['path'],
      content: file_data['content'],
      file_type: File.extname(file_data['path']).sub('.', ''),
      team: team
    )
  end
  
  puts "✅ Created #{app.app_files.count} app files"
  
  # Test FastPreviewService
  puts "\n🚀 Testing FastPreviewService..."
  preview_service = Deployment::FastPreviewService.new(app)
  
  # Check if Cloudflare credentials are available
  if ENV['CLOUDFLARE_ACCOUNT_ID'] && ENV['CLOUDFLARE_API_TOKEN']
    begin
      deploy_result = preview_service.deploy_instant_preview!
      puts "Deploy Result: #{deploy_result[:success] ? '✅' : '❌'}"
      puts "Preview URL: #{deploy_result[:preview_url]}" if deploy_result[:preview_url]
      puts "Error: #{deploy_result[:error]}" if deploy_result[:error]
      
      if deploy_result[:success]
        puts "🎉 FULL DEPLOYMENT SUCCESSFUL!"
        puts "   Worker deployed and accessible at: #{deploy_result[:preview_url]}"
      end
    rescue => e
      puts "❌ Deployment exception: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join("\n   ")}"
    end
  else
    puts "⚠️  Cloudflare credentials not configured - skipping deployment test"
    puts "   Worker script size: #{preview_service.send(:generate_fast_preview_worker).size} chars"
  end
else
  puts "\n❌ Generation failed!"
end

puts "\n✅ Test complete!"