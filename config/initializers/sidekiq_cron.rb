require 'sidekiq-cron'

# Schedule cleanup of stuck chat messages every 5 minutes
Sidekiq::Cron::Job.create(
  name: 'Cleanup Stuck Messages',
  cron: '*/5 * * * *', # Every 5 minutes
  class: 'CleanupStuckMessagesJob',
  active_job: true  # This tells sidekiq-cron to use ActiveJob
)