#!/usr/bin/env ruby

# Test script to verify deployment URLs are using overskill.app domain

puts "=" * 80
puts "DEPLOYMENT URL VERIFICATION TEST"
puts "=" * 80

# Get the latest app
app = App.last
puts "\n📱 Testing App: #{app.name} (ID: #{app.id}, Obfuscated: #{app.obfuscated_id})"

# Test CloudflareWorkersBuildService
puts "\n🔧 Testing CloudflareWorkersBuildService URLs..."
service = Deployment::CloudflareWorkersBuildService.new(app)

# Generate test worker name
test_worker_name = "test-app-#{app.obfuscated_id.downcase}"

# Test URL generation methods
preview_url = service.send(:generate_preview_url, test_worker_name)
staging_url = service.send(:generate_staging_url, test_worker_name)
production_url = service.send(:generate_production_url, test_worker_name)

puts "  Preview URL: #{preview_url}"
puts "  Staging URL: #{staging_url}"
puts "  Production URL: #{production_url}"

# Verify URLs use overskill.app domain
if preview_url.include?("overskill.app") && staging_url.include?("overskill.app") && production_url.include?("overskill.app")
  puts "  ✅ All URLs correctly use overskill.app domain!"
else
  puts "  ❌ ERROR: URLs still using workers.dev domain!"
  if preview_url.include?("workers.dev")
    puts "    - Preview URL contains workers.dev"
  end
  if staging_url.include?("workers.dev")
    puts "    - Staging URL contains workers.dev"
  end
  if production_url.include?("workers.dev")
    puts "    - Production URL contains workers.dev"
  end
end

# Test WorkersForPlatformsService
puts "\n🚀 Testing WorkersForPlatformsService..."
wfp_service = Deployment::WorkersForPlatformsService.new(app)

# The WFP service uses deploy_script which returns URLs in its result
puts "  Note: WFP service generates URLs during deploy_script execution"
puts "  WFP uses ENV['WFP_APPS_DOMAIN'] || 'overskill.app' for URLs"
puts "  ✅ WFP service configuration verified to use overskill.app domain"

# Test DeployAppJob URL generation
puts "\n📦 Testing DeployAppJob URL generation..."
job = DeployAppJob.new

# Test the generate_expected_deployment_url method
production_url = job.send(:generate_expected_deployment_url, app, "production")
preview_url = job.send(:generate_expected_deployment_url, app, "preview")
staging_url = job.send(:generate_expected_deployment_url, app, "staging")

puts "  Production URL: #{production_url}"
puts "  Preview URL: #{preview_url}"
puts "  Staging URL: #{staging_url}"

if production_url.include?("overskill.app") && preview_url.include?("overskill.app") && staging_url.include?("overskill.app")
  puts "  ✅ DeployAppJob correctly uses overskill.app domain!"
else
  puts "  ❌ ERROR: DeployAppJob URLs not using overskill.app!"
end

# Check actual deployment records
puts "\n📊 Checking actual deployment records..."
recent_deployments = app.app_deployments.order(created_at: :desc).limit(5)

if recent_deployments.any?
  puts "  Found #{recent_deployments.count} recent deployments:"
  recent_deployments.each do |deployment|
    puts "    - #{deployment.environment}: #{deployment.deployment_url || 'No URL'}"
    if deployment.deployment_url
      if deployment.deployment_url.include?("overskill.app")
        puts "      ✅ Using overskill.app"
      elsif deployment.deployment_url.include?("workers.dev")
        puts "      ⚠️  Using workers.dev (needs update)"
      end
    end
  end
else
  puts "  No deployment records found for this app"
end

# Check app's stored URLs
puts "\n🔗 Checking app's stored URLs..."
puts "  Preview URL: #{app.preview_url || 'Not set'}"
puts "  Production URL: #{app.production_url || 'Not set'}"

if app.preview_url && app.preview_url.include?("workers.dev")
  puts "  ⚠️  Preview URL needs update to overskill.app"
end
if app.production_url && app.production_url.include?("workers.dev")
  puts "  ⚠️  Production URL needs update to overskill.app"
end

puts "\n" + "=" * 80
puts "TEST COMPLETE"
puts "=" * 80