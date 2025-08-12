#!/usr/bin/env rails runner

require 'net/http'
require 'uri'
require 'json'

app = App.find(109)
puts "Testing publish action for app: #{app.name}"
puts "Current status: #{app.status}"
puts "Can publish?: #{app.can_publish?}"

if app.can_publish?
  puts "\nTriggering publish via controller action..."
  
  # Simulate the controller action
  user = app.creator.user
  team = app.team
  
  puts "User: #{user.email}"
  puts "Team: #{team.name}"
  
  # Call the publish method directly (simulating controller)
  begin
    # The controller would normally do this
    if app.published?
      puts "App is already published at: #{app.production_url}"
    else
      puts "Publishing app to production..."
      
      # Queue the job
      job = PublishAppToProductionJob.perform_later(app)
      puts "Job queued: #{job.job_id}"
      
      # Wait a moment for job to start
      sleep 2
      
      # Check job status
      require 'sidekiq/api'
      
      # Check if job is processing
      workers = Sidekiq::Workers.new
      processing = workers.any? { |process_id, thread_id, work| 
        work['payload']['class'] == 'PublishAppToProductionJob'
      }
      
      if processing
        puts "Job is processing..."
      else
        puts "Job not found in workers, checking queues..."
        
        # Check deployments queue
        queue = Sidekiq::Queue.new('deployments')
        puts "Deployments queue size: #{queue.size}"
        
        queue.each do |job|
          if job.klass == 'Sidekiq::ActiveJob::Wrapper'
            puts "Found job: #{job.args.first['job_class'] rescue 'unknown'}"
          end
        end
      end
    end
  rescue => e
    puts "Error: #{e.message}"
    puts e.backtrace.first(3)
  end
else
  puts "\nApp cannot be published. Requirements:"
  puts "- Status must be 'ready': #{app.status == 'ready' ? '✓' : '✗'} (current: #{app.status})"
  puts "- Must have preview URL: #{app.preview_url.present? ? '✓' : '✗'}"
  puts "- Must have files: #{app.app_files.exists? ? '✓' : '✗'} (#{app.app_files.count} files)"
end