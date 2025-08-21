# frozen_string_literal: true

ActiveJob::Uniqueness.configure do |config|
  # Global default expiration for lock keys. Each job can define its own ttl via :lock_ttl option.
  # Strategy :until_and_while_executing also accepts :on_runtime_ttl option.
  # Set to 1 hour by default for deployment/AI generation jobs
  config.lock_ttl = 1.hour

  # Prefix for lock keys. Can not be set per job.
  config.lock_prefix = 'overskill_jobs'

  # Default action on lock conflict. Can be set per job.
  # Log duplicates by default instead of raising errors
  config.on_conflict = :log

  # Default action on redis connection error. 
  # Continue processing even if Redis is down (fallback to non-unique behavior)
  config.on_redis_connection_error = proc do |job, resource: nil, error: nil|
    Rails.logger.warn "[ActiveJob::Uniqueness] Redis connection error for #{job.class.name}: #{error&.message}"
    Rails.logger.warn "[ActiveJob::Uniqueness] Job will proceed without uniqueness check"
  end

  # Digest method for lock keys generating
  config.digest_method = OpenSSL::Digest::SHA256

  # Array of redis servers for Redlock quorum
  # Use the same Redis as Sidekiq
  config.redlock_servers = [ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')]

  # Custom options for Redlock
  # Retry once on lock conflicts
  config.redlock_options = { 
    retry_count: 1,
    retry_delay: 200 # milliseconds
  }
end
