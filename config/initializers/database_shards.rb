# Initialize default database shard from environment variables
Rails.application.config.after_initialize do
  # Skip if we're in a rake task context (to avoid issues during rake db:migrate, etc.)
  next if defined?(Rake.application) && Rake.application.top_level_tasks.any?
  
  # Skip completely in test environment to avoid connection issues
  next if Rails.env.test?
  
  # Check if we have Supabase credentials in ENV
  if ENV['SUPABASE_URL'].present? && ENV['SUPABASE_ANON_KEY'].present?
    begin
      # Use ActiveRecord connection to check if the table exists
      if ActiveRecord::Base.connection.table_exists?('database_shards')
        # Find or create the default shard
        default_shard = DatabaseShard.find_or_initialize_by(shard_number: 0)
        
        # Update with current ENV values
        default_shard.assign_attributes(
          name: ENV.fetch('DEFAULT_SHARD_NAME', 'default-shard'),
          supabase_project_id: ENV.fetch('SUPABASE_PROJECT_ID', 'default-project'),
          supabase_url: ENV['SUPABASE_URL'],
          supabase_anon_key: ENV['SUPABASE_ANON_KEY'],
          supabase_service_key: ENV['SUPABASE_SERVICE_KEY'],
          status: 'available'
        )
        
        # Only update app_count if it's a new record
        default_shard.app_count = 0 if default_shard.new_record?
        
        if default_shard.save
          Rails.logger.info "[DatabaseShards] Default shard initialized from environment variables: #{default_shard.name}"
        else
          Rails.logger.error "[DatabaseShards] Failed to initialize default shard: #{default_shard.errors.full_messages.join(', ')}"
        end
      else
        Rails.logger.info "[DatabaseShards] Database shards table doesn't exist yet. Skipping initialization."
      end
    rescue => e
      Rails.logger.error "[DatabaseShards] Error initializing default shard: #{e.message}"
    end
  else
    Rails.logger.info "[DatabaseShards] No Supabase credentials found in environment variables. Run 'rails shards:init_default' to create default shard when credentials are available."
  end
end
