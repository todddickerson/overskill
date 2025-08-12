puts "🌱 Generating development environment seeds."

# Initialize default database shard from environment variables
if ENV['SUPABASE_URL'].present? && ENV['SUPABASE_ANON_KEY'].present?
  puts "  → Initializing default database shard..."
  
  default_shard = DatabaseShard.find_or_initialize_by(shard_number: 0)
  default_shard.assign_attributes(
    name: ENV.fetch('DEFAULT_SHARD_NAME', 'development-shard'),
    supabase_project_id: ENV.fetch('SUPABASE_PROJECT_ID', 'development-project'),
    supabase_url: ENV['SUPABASE_URL'],
    supabase_anon_key: ENV['SUPABASE_ANON_KEY'],
    supabase_service_key: ENV['SUPABASE_SERVICE_KEY'],
    status: 'available',
    app_count: default_shard.new_record? ? 0 : default_shard.app_count
  )
  
  if default_shard.save
    puts "    ✅ Default shard configured: #{default_shard.name}"
  else
    puts "    ❌ Failed to configure default shard: #{default_shard.errors.full_messages.join(', ')}"
  end
else
  puts "  ⚠️  No Supabase credentials found in ENV. Skipping shard initialization."
  puts "     Add SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_KEY to your .env file."
end
