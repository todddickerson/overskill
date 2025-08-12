# Background job to sync users between Rails and Supabase across multiple shards
class SupabaseAuthSyncJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: 5, attempts: 3
  
  def perform(user, action = nil)
    # Normalize action to a simple string to be resilient to
    # ActiveJob serialization differences (symbol/hash/string)
    normalized_action = case action
                        when Hash
                          action[:value] || action['value'] || action[:action] || action['action']
                        else
                          action
                        end

    action_str = normalized_action.to_s

    service = SupabaseService.instance
    
    case action_str
    when 'create'
      create_supabase_user(user, service)
    when 'update'
      update_supabase_user(user, service)
    when 'delete'
      delete_supabase_user(user, service)
    else
      raise ArgumentError, "Unknown action: #{action.inspect}"
    end
  end
  
  private
  
  def create_supabase_user(user, service)
    # Skip if already synced to any shard
    return if user.user_shard_mappings.synced.any?
    
    # Create Supabase auth user with temporary password
    result = service.create_user(
      user.email,
      SecureRandom.hex(16),
      {
        rails_user_id: user.id,
        name: user.name,
        team_ids: user.teams.pluck(:id)
      }
    )
    
    if result[:success]
      # Store the primary Supabase user ID (from first successful shard)
      user.update!(
        supabase_user_id: result[:data]['id'],
        supabase_sync_status: 'synced',
        supabase_last_synced_at: Time.current
      )
      
      # Create user shard mappings for successful syncs
      result[:synced_shards]&.each do |shard_name|
        shard = DatabaseShard.find_by(name: shard_name)
        next unless shard
        
        mapping = user.user_shard_mappings.find_or_initialize_by(database_shard: shard)
        mapping.update!(
          supabase_user_id: result[:data]['id'],
          sync_status: 'synced',
          last_synced_at: Time.current
        )
      end
      
      # Log failed shards for monitoring
      result[:failed_shards]&.each do |failed|
        Rails.logger.error "[SupabaseSync] Failed to sync user #{user.id} to #{failed[:shard]}: #{failed[:error]}"
      end
      
      # Create profile in Supabase across all shards
      profile_result = service.create_profile(user)
      
      unless profile_result[:success]
        Rails.logger.error "Failed to create Supabase profile for user #{user.id}: #{profile_result[:error]}"
      end
    else
      user.update!(supabase_sync_status: 'failed')
      raise "Failed to create Supabase user on any shard: #{result[:error]}"
    end
  end
  
  def update_supabase_user(user, service)
    # Get all shard mappings for this user
    mappings = user.user_shard_mappings.includes(:database_shard)
    return if mappings.empty?
    
    # Use the primary Supabase user ID if available, otherwise use from first mapping
    supabase_user_id = user.supabase_user_id || mappings.first.supabase_user_id
    
    result = service.update_user(supabase_user_id, {
      email: user.email,
      user_metadata: {
        name: user.name,
        team_ids: user.teams.pluck(:id),
        updated_at: Time.current.iso8601
      }
    })
    
    if result[:success]
      user.update!(
        supabase_sync_status: 'synced',
        supabase_last_synced_at: Time.current
      )
      
      # Update shard mappings for successful syncs
      result[:synced_shards]&.each do |shard_name|
        mapping = mappings.find { |m| m.database_shard.name == shard_name }
        mapping&.update!(
          sync_status: 'synced',
          last_synced_at: Time.current
        )
      end
      
      # Update profile across all shards
      service.create_profile(user)
    else
      user.update!(supabase_sync_status: 'error')
      raise "Failed to update Supabase user on any shard: #{result[:error]}"
    end
  end
  
  def delete_supabase_user(user, service)
    # Get all shard mappings for this user
    mappings = user.user_shard_mappings.includes(:database_shard)
    
    # Use the primary Supabase user ID if available, otherwise use from first mapping
    supabase_user_id = user.supabase_user_id || mappings.first&.supabase_user_id
    return unless supabase_user_id
    
    result = service.delete_user(supabase_user_id)
    
    if result[:success]
      user.update!(
        supabase_user_id: nil,
        supabase_sync_status: 'deleted',
        supabase_last_synced_at: Time.current
      )
      
      # Update shard mappings for successful deletions
      result[:synced_shards]&.each do |shard_name|
        mapping = mappings.find { |m| m.database_shard.name == shard_name }
        mapping&.update!(sync_status: 'deleted')
      end
      
      # Log failed deletions
      result[:failed_shards]&.each do |failed|
        Rails.logger.error "[SupabaseSync] Failed to delete user #{user.id} from #{failed[:shard]}: #{failed[:error]}"
      end
    else
      Rails.logger.error "Failed to delete Supabase user #{supabase_user_id} from any shard: #{result[:error]}"
    end
  end
end