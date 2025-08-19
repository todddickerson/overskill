#!/usr/bin/env ruby
require_relative 'config/environment'
require_relative 'lib/patches/cloudflare_preview_service_r2_patch'

app = App.find(1027)
puts "=" * 80
puts "DEPLOYING PAGEFORGE WITH SELF-HEALING BUILD SYSTEM"
puts "=" * 80
puts "App: #{app.name} (ID: #{app.id})"
puts "Files: #{app.app_files.count}"
puts ""

# Use the self-healing build service
require_relative 'app/services/deployment/self_healing_build_service'
builder = Deployment::SelfHealingBuildService.new(app)
puts "Starting self-healing build..."
puts "This will automatically retry and fix common TypeScript errors"
puts ""

result = builder.build_with_retry!

if result[:success]
  puts ""
  puts "✅ BUILD SUCCEEDED!"
  puts "Files generated: #{result[:files].keys.count}"
  puts ""
  
  # Deploy to staging with integrated R2 asset offloading
  puts "Deploying to Cloudflare with R2 asset offloading..."
  require_relative 'app/services/deployment/cloudflare_preview_service'
  
  deployer = Deployment::CloudflarePreviewService.new(app)
  deploy_result = deployer.deploy_staging!  # This now includes R2 integration
  
  if deploy_result[:success]
    puts ""
    puts "🚀 DEPLOYMENT SUCCESSFUL!"
    puts "URL: #{deploy_result[:url]}"
    puts "Assets uploaded to R2: #{deploy_result[:r2_assets_count] || 0}"
    puts "Worker size: #{deploy_result[:worker_size] || 'unknown'}"
  else
    puts ""
    puts "❌ DEPLOYMENT FAILED"
    puts "Error: #{deploy_result[:error]}"
  end
else
  puts ""
  puts "❌ BUILD FAILED after #{result[:attempts]} attempts"
  puts "Error: #{result[:error]}"
  
  if result[:error_analysis]
    puts ""
    puts "ERROR ANALYSIS:"
    puts "Total errors: #{result[:error_analysis][:total_errors]}"
    puts "Files affected: #{result[:error_analysis][:files_affected]}"
    puts ""
    puts "Error summary:"
    result[:error_analysis][:errors_summary].each do |summary|
      puts "  - #{summary}"
    end
    
    if result[:error_analysis][:strategies].any?
      puts ""
      puts "Suggested fixes:"
      result[:error_analysis][:strategies].each_with_index do |strategy, i|
        puts "  #{i + 1}. #{strategy[:description]}"
      end
    end
  end
end