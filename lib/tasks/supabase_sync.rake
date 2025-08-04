namespace :supabase do
  desc "Sync all Rails users to Supabase"
  task sync_all_users: :environment do
    puts "Starting Supabase user sync..."
    puts "Total users to sync: #{User.count}"
    
    # Queue the sync job
    job = SyncUsersToSupabaseJob.perform_later
    
    puts "Sync job queued with ID: #{job.job_id}"
    puts "Check Sidekiq dashboard or logs for progress"
    puts "You can also monitor progress at: /account/supabase_sync"
  end
  
  desc "Check sync status"
  task sync_status: :environment do
    total = User.count
    synced = User.where(supabase_sync_status: 'synced').count
    pending = User.where(supabase_user_id: nil).count
    failed = User.where(supabase_sync_status: ['failed', 'error']).count
    
    puts "Supabase Sync Status:"
    puts "===================="
    puts "Total users:   #{total}"
    puts "Synced:        #{synced} (#{(synced.to_f / total * 100).round(1)}%)"
    puts "Pending:       #{pending}"
    puts "Failed:        #{failed}"
    
    if failed > 0
      puts "\nFailed users:"
      User.where(supabase_sync_status: ['failed', 'error']).each do |user|
        puts "  - #{user.email} (#{user.supabase_sync_status})"
      end
    end
  end
  
  desc "Reset sync status for all users"
  task reset_sync: :environment do
    puts "Are you sure you want to reset sync status? This will clear all Supabase IDs. (yes/no)"
    confirm = STDIN.gets.chomp
    
    if confirm.downcase == 'yes'
      User.update_all(
        supabase_user_id: nil,
        supabase_sync_status: nil,
        supabase_last_synced_at: nil
      )
      puts "Sync status reset for all users"
    else
      puts "Operation cancelled"
    end
  end
  
  desc "Sync a specific user by email"
  task :sync_user, [:email] => :environment do |t, args|
    user = User.find_by(email: args[:email])
    
    if user
      puts "Syncing user: #{user.email}"
      job = SupabaseAuthSyncJob.perform_later(user, :create)
      puts "Sync job queued with ID: #{job.job_id}"
    else
      puts "User not found: #{args[:email]}"
    end
  end
  
  desc "Generate webhook secret"
  task generate_webhook_secret: :environment do
    secret = SecureRandom.hex(32)
    puts "Generated webhook secret:"
    puts secret
    puts "\nAdd this to your .env file:"
    puts "SUPABASE_WEBHOOK_SECRET=#{secret}"
  end
end