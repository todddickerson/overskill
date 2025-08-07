#!/usr/bin/env ruby
# Fix white-on-white text issue in Auth component
# Run with: bin/rails runner scripts/fix_auth_colors.rb

app = App.find(57)
auth = app.app_files.find_by(path: 'src/components/Auth.tsx')

if auth
  puts "Fixing Auth component input colors..."
  
  # Fix the className for inputs to include text color
  fixed_content = auth.content.gsub(
    'className="w-full px-3 py-2 border border-gray-300 rounded-md"',
    'className="w-full px-3 py-2 border border-gray-300 rounded-md text-gray-900 placeholder-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500"'
  )
  
  auth.update!(content: fixed_content)
  puts "✅ Fixed Auth component input colors"
  
  # Trigger redeployment
  puts "\nRedeploying app..."
  deploy_service = Deployment::CloudflarePreviewService.new(app)
  result = deploy_service.update_preview!
  
  if result[:success]
    puts "✅ Redeployed app with fix"
    puts "URL: #{result[:preview_url]}"
  else
    puts "❌ Deployment failed: #{result[:error]}"
  end
else
  puts "❌ Auth.tsx not found"
end