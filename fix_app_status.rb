#!/usr/bin/env rails runner

app = App.find(109)
puts "Current app status: #{app.status}"

if app.status == 'generating'
  app.update!(status: 'ready')
  puts "Updated app status to: ready"
else
  puts "App status is already: #{app.status}"
end

puts "Can publish?: #{app.can_publish?}"
puts "Preview URL: #{app.preview_url}"
puts "Production URL: #{app.production_url}"
puts "Subdomain: #{app.subdomain}"

# Clear any stuck jobs
require 'sidekiq/api'

# Check default queue
default_queue = Sidekiq::Queue.new('default')
puts "\nDefault queue size: #{default_queue.size}"

# Check deployment queue  
deployment_queue = Sidekiq::Queue.new('deployment')
puts "Deployment queue size: #{deployment_queue.size}"

# Check deployments queue (our new one)
deployments_queue = Sidekiq::Queue.new('deployments')
puts "Deployments queue size: #{deployments_queue.size}"

# Check retries
retries = Sidekiq::RetrySet.new
puts "Retry set size: #{retries.size}"

# Check dead jobs
dead = Sidekiq::DeadSet.new
puts "Dead set size: #{dead.size}"