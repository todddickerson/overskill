# Singleton service for managing Supabase interactions across multiple shards
class SupabaseService
  include Singleton
  
  # Create a new auth user across all relevant shards
  def create_user(email, password = nil, metadata = {})
    password ||= SecureRandom.hex(16)
    results = []
    
    # Get shards where this user's apps might be deployed
    shards_to_sync = get_relevant_shards_for_user(email)
    
    # If no specific shards, sync to all available shards
    shards_to_sync = DatabaseShard.available if shards_to_sync.empty?
    
    # Sync user to each shard
    shards_to_sync.each do |shard|
      shard_service = SupabaseShardService.new(shard)
      result = shard_service.create_user(email, password, metadata)
      results << result
      
      Rails.logger.info "[SupabaseService] Create user on #{shard.name}: #{result[:success] ? 'success' : result[:error]}"
    end
    
    # Return overall success if at least one shard succeeded
    successful_shards = results.select { |r| r[:success] }
    if successful_shards.any?
      # Use the first successful shard's user ID as the primary one
      primary_result = successful_shards.first
      { 
        success: true, 
        data: primary_result[:data],
        synced_shards: successful_shards.map { |r| r[:shard] },
        failed_shards: results.reject { |r| r[:success] }.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    else
      { 
        success: false, 
        error: "Failed to create user on all shards",
        failed_shards: results.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Update existing Supabase user across all shards
  def update_user(supabase_user_id, attributes)
    results = []
    
    # Update on all shards where user exists
    DatabaseShard.available.each do |shard|
      shard_service = SupabaseShardService.new(shard)
      result = shard_service.update_user(supabase_user_id, attributes)
      results << result
      
      Rails.logger.info "[SupabaseService] Update user on #{shard.name}: #{result[:success] ? 'success' : result[:error]}"
    end
    
    # Return overall success if at least one shard succeeded
    successful_shards = results.select { |r| r[:success] }
    if successful_shards.any?
      { 
        success: true, 
        data: successful_shards.first[:data],
        synced_shards: successful_shards.map { |r| r[:shard] },
        failed_shards: results.reject { |r| r[:success] }.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    else
      { 
        success: false, 
        error: "Failed to update user on all shards",
        failed_shards: results.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Create or update user profile across all shards
  def create_profile(user)
    results = []
    
    # Create profile on all shards where user exists
    user_shard_mappings = get_user_shard_mappings(user)
    
    user_shard_mappings.each do |mapping|
      shard = mapping[:shard]
      shard_user_id = mapping[:supabase_user_id]
      
      shard_service = SupabaseShardService.new(shard)
      result = shard_service.create_profile(user, shard_user_id)
      results << result
      
      Rails.logger.info "[SupabaseService] Create profile on #{shard.name}: #{result[:success] ? 'success' : result[:error]}"
    end
    
    # Return overall success if at least one shard succeeded
    successful_shards = results.select { |r| r[:success] }
    if successful_shards.any?
      { 
        success: true, 
        data: successful_shards.first[:data],
        synced_shards: successful_shards.map { |r| r[:shard] },
        failed_shards: results.reject { |r| r[:success] }.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    else
      { 
        success: false, 
        error: "Failed to create profile on all shards",
        failed_shards: results.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Delete user from all shards
  def delete_user(supabase_user_id)
    results = []
    
    # Delete from all shards
    DatabaseShard.available.each do |shard|
      shard_service = SupabaseShardService.new(shard)
      result = shard_service.delete_user(supabase_user_id)
      results << result
      
      Rails.logger.info "[SupabaseService] Delete user on #{shard.name}: #{result[:success] ? 'success' : result[:error]}"
    end
    
    # Return overall success if at least one shard succeeded
    successful_shards = results.select { |r| r[:success] }
    if successful_shards.any?
      { 
        success: true,
        synced_shards: successful_shards.map { |r| r[:shard] },
        failed_shards: results.reject { |r| r[:success] }.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    else
      { 
        success: false, 
        error: "Failed to delete user on all shards",
        failed_shards: results.map { |r| { shard: r[:shard], error: r[:error] } }
      }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Verify webhook signature (webhook might come from any shard)
  def verify_webhook_signature(payload, signature, shard_name = nil)
    # If shard specified, use its secret
    if shard_name
      shard = DatabaseShard.find_by(name: shard_name)
      secret = shard&.webhook_secret
    else
      # Fall back to global webhook secret
      secret = ENV['SUPABASE_WEBHOOK_SECRET']
    end
    
    return false unless secret
    
    expected_signature = OpenSSL::HMAC.hexdigest(
      'SHA256',
      secret,
      payload
    )
    
    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end
  
  private
  
  # Get shards where user's apps are deployed
  def get_relevant_shards_for_user(email)
    # Find user by email
    user = User.find_by(email: email)
    return [] unless user
    
    # Get all shards where user has apps
    shards = user.teams
                 .joins(apps: :database_shard)
                 .select('DISTINCT database_shards.*')
                 .map(&:database_shard)
                 .compact
                 .uniq
    
    shards
  end
  
  # Get user's Supabase user IDs for each shard
  def get_user_shard_mappings(user)
    # In the future, we might store per-shard user IDs
    # For now, assume same user ID across all shards
    shards = get_relevant_shards_for_user(user.email)
    shards = DatabaseShard.available if shards.empty?
    
    shards.map do |shard|
      {
        shard: shard,
        supabase_user_id: user.supabase_user_id
      }
    end
  end
end