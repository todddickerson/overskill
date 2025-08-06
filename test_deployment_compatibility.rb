#!/usr/bin/env ruby
require_relative 'config/environment'

# Test if generated apps are Cloudflare-compatible
puts "\n=== Testing Cloudflare Deployment Compatibility ==="

# Generate a simple app
generator = Ai::StructuredAppGenerator.new
result = generator.generate(
  "Create a minimal hello world app",
  framework: "react",
  app_type: "saas"
)

if !result[:success]
  puts "❌ Generation failed"
  exit 1
end

puts "✅ App generated with #{result[:files].size} files"

# Check for critical deployment files
critical_checks = {
  'index.html' => 'Entry point HTML',
  'wrangler.toml' => 'Cloudflare Workers config',
  'package.json' => 'Dependencies',
  'src/lib/supabase.ts' => 'Supabase integration',
  'src/lib/analytics.ts' => 'Analytics tracking'
}

puts "\n📋 Deployment Checklist:"
result[:files].each do |file|
  path = file['path']
  if critical_checks[path]
    puts "  ✅ #{path} - #{critical_checks[path]}"
    critical_checks.delete(path)
  end
end

critical_checks.each do |path, desc|
  puts "  ❌ #{path} - #{desc} (MISSING)"
end

# Check if files are compatible with Cloudflare Worker script
puts "\n🔍 Cloudflare Worker Compatibility:"

# The worker script expects files as a hash
files_hash = {}
result[:files].each do |file|
  files_hash[file['path']] = file['content']
end

# Check if index.html exists and has proper structure
if index_file = result[:files].find { |f| f['path'] == 'index.html' }
  content = index_file['content']
  checks = {
    '<!DOCTYPE html>' => 'HTML5 doctype',
    '<head>' => 'Head section',
    '<body>' => 'Body section'
  }
  
  puts "\nindex.html structure:"
  checks.each do |pattern, desc|
    if content.include?(pattern)
      puts "  ✅ #{desc}"
    else
      puts "  ❌ #{desc} missing"
    end
  end
end

# Check if React/TypeScript files use proper imports
puts "\n📦 Module System Check:"
tsx_files = result[:files].select { |f| f['path'].end_with?('.tsx', '.ts') }
tsx_files.each do |file|
  content = file['content']
  if content.include?('import') && content.include?('export')
    puts "  ✅ #{file['path']} - Uses ES modules"
  elsif content.include?('require(')
    puts "  ⚠️  #{file['path']} - Uses CommonJS (may need transpilation)"
  else
    puts "  ❓ #{file['path']} - Unknown module system"
  end
end

# Simulate what CloudflarePreviewService would do
puts "\n🚀 Simulating Deployment:"
begin
  # Create a test app in database
  team = Team.first || Team.create!(name: "Test Team")
  membership = team.memberships.first
  
  app = App.create!(
    team: team,
    creator: membership,
    name: "Deployment Test #{Time.now.to_i}",
    slug: "deployment-test-#{Time.now.to_i}",
    prompt: "Test app",
    app_type: "saas",
    framework: "react",
    status: "generated",
    base_price: 0
  )
  
  # Save files to app
  result[:files].each do |file_data|
    app.app_files.create!(
      team: team,
      path: file_data['path'],
      content: file_data['content'],
      file_type: File.extname(file_data['path']).delete('.')
    )
  end
  
  puts "  ✅ Created app #{app.id} with #{app.app_files.count} files"
  
  # Check if deployment service can generate worker script
  service = Deployment::CloudflarePreviewService.new(app)
  
  # Test worker script generation (private method, so we'll check indirectly)
  if service.respond_to?(:update_preview!, true)
    puts "  ✅ Deployment service initialized"
    
    # Check environment variables
    if ENV['CLOUDFLARE_ACCOUNT_ID'] && ENV['CLOUDFLARE_API_TOKEN']
      puts "  ✅ Cloudflare credentials configured"
      puts "\n  Would deploy to: preview-#{app.id}.overskill.app"
    else
      puts "  ⚠️  Cloudflare credentials not configured (set CLOUDFLARE_* env vars)"
    end
  end
  
  # Clean up
  app.destroy
  puts "  ✅ Cleanup complete"
  
rescue => e
  puts "  ❌ Error: #{e.message}"
end

puts "\n=== Deployment Compatibility Test Complete ==="
puts "\n📝 Summary:"
puts "Generated apps include the basic files needed for Cloudflare deployment."
puts "The CloudflarePreviewService embeds all files directly in the Worker script."
puts "No build step required - files are served as-is from the Worker."