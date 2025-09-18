namespace :shards do
  desc "List all database shards"
  task list: :environment do
    puts "\nDatabase Shards:"
    puts "-" * 80
    puts "%-5s %-20s %-10s %-10s %-40s" % ["#", "Name", "Status", "Apps", "URL"]
    puts "-" * 80

    DatabaseShard.order(:shard_number).each do |shard|
      puts "%-5s %-20s %-10s %-10s %-40s" % [
        shard.shard_number,
        shard.name,
        shard.status,
        "#{shard.app_count}/#{DatabaseShard::APPS_PER_SHARD}",
        shard.supabase_url
      ]
    end

    puts "-" * 80
    puts "Total shards: #{DatabaseShard.count}"
    puts "Total capacity: #{DatabaseShard.sum(:app_count)}/#{DatabaseShard.count * DatabaseShard::APPS_PER_SHARD}"
    puts
  end

  desc "Add a new database shard"
  task :add, [:name, :url, :anon_key, :service_key, :project_id] => :environment do |t, args|
    unless args[:name] && args[:url] && args[:anon_key] && args[:service_key]
      puts "Usage: rails shards:add[name,url,anon_key,service_key,project_id]"
      puts "Example: rails shards:add[shard-002,https://xyz.supabase.co,anon_key,service_key,project_xyz]"
      exit 1
    end

    shard_number = DatabaseShard.maximum(:shard_number).to_i + 1

    shard = DatabaseShard.new(
      name: args[:name],
      shard_number: shard_number,
      supabase_project_id: args[:project_id] || args[:name],
      supabase_url: args[:url],
      supabase_anon_key: args[:anon_key],
      supabase_service_key: args[:service_key],
      app_count: 0,
      status: "available"
    )

    if shard.save
      puts "✅ Successfully created shard ##{shard_number}: #{shard.name}"
      puts "   URL: #{shard.supabase_url}"
      puts "   Status: #{shard.status}"
    else
      puts "❌ Failed to create shard: #{shard.errors.full_messages.join(", ")}"
    end
  end

  desc "Update shard status"
  task :update_status, [:shard_name, :status] => :environment do |t, args|
    unless args[:shard_name] && args[:status]
      puts "Usage: rails shards:update_status[shard_name,status]"
      puts "Valid statuses: #{DatabaseShard.statuses.keys.join(", ")}"
      exit 1
    end

    shard = DatabaseShard.find_by(name: args[:shard_name])

    if shard
      if shard.update(status: args[:status])
        puts "✅ Updated #{shard.name} status to: #{args[:status]}"
      else
        puts "❌ Failed to update status: #{shard.errors.full_messages.join(", ")}"
      end
    else
      puts "❌ Shard not found: #{args[:shard_name]}"
    end
  end

  desc "Initialize default shard from environment variables"
  task init_default: :environment do
    if ENV["SUPABASE_URL"].present? && ENV["SUPABASE_ANON_KEY"].present?
      default_shard = DatabaseShard.find_or_initialize_by(shard_number: 0)

      default_shard.assign_attributes(
        name: ENV.fetch("DEFAULT_SHARD_NAME", "default-shard"),
        supabase_project_id: ENV.fetch("SUPABASE_PROJECT_ID", "default-project"),
        supabase_url: ENV["SUPABASE_URL"],
        supabase_anon_key: ENV["SUPABASE_ANON_KEY"],
        supabase_service_key: ENV["SUPABASE_SERVICE_KEY"],
        status: "available"
      )

      default_shard.app_count = 0 if default_shard.new_record?

      if default_shard.save
        puts "✅ Default shard initialized: #{default_shard.name}"
        puts "   URL: #{default_shard.supabase_url}"
        puts "   Apps: #{default_shard.app_count}/#{DatabaseShard::APPS_PER_SHARD}"
      else
        puts "❌ Failed to initialize default shard: #{default_shard.errors.full_messages.join(", ")}"
      end
    else
      puts "❌ Missing required environment variables: SUPABASE_URL, SUPABASE_ANON_KEY"
    end
  end

  desc "Show shard configuration template"
  task config_template: :environment do
    puts "\n# Add these to your .env file for the default shard:"
    puts "SUPABASE_URL=https://your-project.supabase.co"
    puts "SUPABASE_ANON_KEY=your-anon-key"
    puts "SUPABASE_SERVICE_KEY=your-service-key"
    puts "SUPABASE_PROJECT_ID=your-project-id"
    puts "DEFAULT_SHARD_NAME=main-shard\n\n"

    puts "# For additional shards, use the rake task:"
    puts "rails shards:add[shard-name,url,anon-key,service-key,project-id]\n\n"
  end

  desc "Sync all users to a specific shard"
  task :sync_users, [:shard_name] => :environment do |t, args|
    unless args[:shard_name]
      puts "Usage: rails shards:sync_users[shard_name]"
      exit 1
    end

    shard = DatabaseShard.find_by(name: args[:shard_name])

    unless shard
      puts "❌ Shard not found: #{args[:shard_name]}"
      exit 1
    end

    puts "Syncing all users to shard: #{shard.name}"

    User.find_each do |user|
      mapping = user.user_shard_mappings.find_or_initialize_by(database_shard: shard)

      if mapping.synced?
        print "."
      else
        # Queue sync job for this user
        SupabaseAuthSyncJob.perform_later(user, "create")
        print "+"
      end
    end

    puts "\n✅ Sync jobs queued for all users"
  end
end
