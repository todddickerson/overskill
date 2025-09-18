puts "🌱 Generating development environment seeds."

# Initialize default database shard from environment variables
if ENV["SUPABASE_URL"].present? && ENV["SUPABASE_ANON_KEY"].present?
  puts "  → Initializing default database shard..."

  begin
    # Try using the model first
    default_shard = DatabaseShard.find_or_initialize_by(shard_number: 1)
    default_shard.assign_attributes(
      name: ENV.fetch("DEFAULT_SHARD_NAME", "shard-001"),
      supabase_project_id: ENV.fetch("SUPABASE_PROJECT_ID", "bsbgwixlklvgeoxvjmtb"),
      supabase_url: ENV["SUPABASE_URL"],
      supabase_anon_key: ENV["SUPABASE_ANON_KEY"],
      supabase_service_key: ENV["SUPABASE_SERVICE_KEY"],
      status: "available",
      app_count: default_shard.new_record? ? 0 : default_shard.app_count
    )

    if default_shard.save
      puts "    ✅ Default shard configured: #{default_shard.name}"
    else
      puts "    ❌ Failed to configure default shard: #{default_shard.errors.full_messages.join(", ")}"
    end
  rescue => e
    # Fallback to SQL if model has issues
    puts "    ⚠️  Model error, using SQL fallback: #{e.message}"

    existing = ActiveRecord::Base.connection.execute("SELECT id FROM database_shards WHERE shard_number = 1").first

    if existing
      puts "    ✅ Default shard already exists"
    else
      ActiveRecord::Base.connection.execute("
        INSERT INTO database_shards (
          name, shard_number, supabase_project_id, supabase_url,
          supabase_anon_key, supabase_service_key, status, app_count,
          metadata, created_at, updated_at
        ) VALUES (
          '#{ENV.fetch("DEFAULT_SHARD_NAME", "shard-001")}',
          1,
          '#{ENV.fetch("SUPABASE_PROJECT_ID", "bsbgwixlklvgeoxvjmtb")}',
          '#{ENV["SUPABASE_URL"]}',
          '#{ENV["SUPABASE_ANON_KEY"]}',
          '#{ENV["SUPABASE_SERVICE_KEY"]}',
          1, 0, '{}', NOW(), NOW()
        )
      ")
      puts "    ✅ Default shard created via SQL"
    end
  end
else
  puts "  ⚠️  No Supabase credentials found in ENV. Skipping shard initialization."
  puts "     Add SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_KEY to your .env file."
end
