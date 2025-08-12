puts "🌱 Generating production environment seeds."

# Initialize default database shard from environment variables
if ENV['SUPABASE_URL'].present? && ENV['SUPABASE_ANON_KEY'].present?
  puts "  → Initializing default database shard..."
  
  default_shard = DatabaseShard.find_or_initialize_by(shard_number: 0)
  default_shard.assign_attributes(
    name: ENV.fetch('DEFAULT_SHARD_NAME', 'primary-shard'),
    supabase_project_id: ENV.fetch('SUPABASE_PROJECT_ID', 'overskill-production'),
    supabase_url: ENV['SUPABASE_URL'],
    supabase_anon_key: ENV['SUPABASE_ANON_KEY'],
    supabase_service_key: ENV['SUPABASE_SERVICE_KEY'],
    status: 'available',
    app_count: default_shard.new_record? ? 0 : default_shard.app_count
  )
  
  if default_shard.save
    puts "    ✅ Default shard configured: #{default_shard.name}"
    puts "    📊 Capacity: #{default_shard.app_count}/#{DatabaseShard::APPS_PER_SHARD} apps"
  else
    puts "    ❌ Failed to configure default shard: #{default_shard.errors.full_messages.join(', ')}"
  end
else
  Rails.logger.error "[Seeds] No Supabase credentials found in production environment!"
  puts "  ❌ CRITICAL: No Supabase credentials found in ENV!"
  puts "     Production requires SUPABASE_URL, SUPABASE_ANON_KEY, and SUPABASE_SERVICE_KEY"
end
