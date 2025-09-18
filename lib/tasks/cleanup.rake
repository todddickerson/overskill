namespace :cleanup do
  desc "Remove orphaned Sidekiq jobs for deleted users"
  task orphaned_jobs: :environment do
    require "sidekiq/api"

    cleaned = 0

    # Clean retry set
    Sidekiq::RetrySet.new.each do |job|
      # Try to deserialize arguments to check if user exists
      args = job.args
      if args&.first.is_a?(Integer)
        User.find(args.first)
      end
    rescue ActiveRecord::RecordNotFound
      job.delete
      cleaned += 1
      puts "Deleted orphaned job: #{job.klass} for user_id: #{args&.first}"
    rescue
      # Skip jobs we can't process
    end

    # Clean dead set
    Sidekiq::DeadSet.new.each do |job|
      args = job.args
      if args&.first.is_a?(Integer)
        User.find(args.first)
      end
    rescue ActiveRecord::RecordNotFound
      job.delete
      cleaned += 1
      puts "Deleted dead job: #{job.klass} for user_id: #{args&.first}"
    rescue
      # Skip
    end

    puts "✅ Cleaned #{cleaned} orphaned jobs"
  end

  desc "Clean stale ActiveStorage blobs"
  task storage_blobs: :environment do
    # Find unattached blobs older than 1 day
    unattached = ActiveStorage::Blob.unattached.where("active_storage_blobs.created_at < ?", 1.day.ago)
    count = unattached.count

    if count > 0
      puts "Found #{count} unattached blobs to clean..."
      unattached.find_each(&:purge_later)
      puts "✅ Scheduled #{count} blobs for purging"
    else
      puts "✅ No unattached blobs to clean"
    end
  end

  desc "Run all cleanup tasks"
  task all: [:orphaned_jobs, :storage_blobs] do
    puts "✅ All cleanup tasks completed"
  end
end
