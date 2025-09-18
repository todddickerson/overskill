#!/usr/bin/env rails runner

app = App.find(109)
puts "Debugging 'undefined method apps for nil' error"

# Test each step of the deployment process
begin
  puts "1. Creating ProductionDeploymentService..."
  service = Deployment::ProductionDeploymentService.new(app)
  puts "   ✓ Service created"

  puts "2. Testing can_deploy_to_production?..."
  can_deploy = service.send(:can_deploy_to_production?)
  puts "   ✓ Can deploy: #{can_deploy}"

  puts "3. Testing ensure_unique_subdomain..."
  subdomain = service.send(:ensure_unique_subdomain)
  puts "   ✓ Subdomain: #{subdomain}"

  puts "4. Testing build_for_production..."
  build_result = service.send(:build_for_production)
  puts "   Build result: #{build_result[:success] ? "success" : build_result[:error]}"

  if build_result[:success]
    puts "5. Testing deploy_production_worker..."
    deploy_result = service.send(:deploy_production_worker, build_result[:built_code])
    puts "   Deploy result: #{deploy_result[:success] ? "success" : deploy_result[:error]}"
  end
rescue => e
  puts "ERROR at step: #{e.message}"
  puts "Backtrace:"
  puts e.backtrace.first(5).join("\n")
end
