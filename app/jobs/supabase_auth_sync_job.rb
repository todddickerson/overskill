# Background job to sync users between Rails and Supabase
class SupabaseAuthSyncJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(user, action)
    service = SupabaseService.instance
    
    case action.to_sym
    when :create
      create_supabase_user(user, service)
    when :update
      update_supabase_user(user, service)
    when :delete
      delete_supabase_user(user, service)
    else
      raise ArgumentError, "Unknown action: #{action}"
    end
  end
  
  private
  
  def create_supabase_user(user, service)
    # Skip if already synced
    return if user.supabase_user_id.present?
    
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
      user.update!(
        supabase_user_id: result[:data]['id'],
        supabase_sync_status: 'synced',
        supabase_last_synced_at: Time.current
      )
      
      # Create profile in Supabase
      profile_result = service.create_profile(user)
      
      unless profile_result[:success]
        Rails.logger.error "Failed to create Supabase profile for user #{user.id}: #{profile_result[:error]}"
      end
    else
      user.update!(supabase_sync_status: 'failed')
      raise "Failed to create Supabase user: #{result[:error]}"
    end
  end
  
  def update_supabase_user(user, service)
    return unless user.supabase_user_id.present?
    
    result = service.update_user(user.supabase_user_id, {
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
      
      # Update profile
      service.create_profile(user)
    else
      user.update!(supabase_sync_status: 'error')
      raise "Failed to update Supabase user: #{result[:error]}"
    end
  end
  
  def delete_supabase_user(user, service)
    return unless user.supabase_user_id.present?
    
    result = service.delete_user(user.supabase_user_id)
    
    if result[:success]
      user.update!(
        supabase_user_id: nil,
        supabase_sync_status: 'deleted',
        supabase_last_synced_at: Time.current
      )
    else
      Rails.logger.error "Failed to delete Supabase user #{user.supabase_user_id}: #{result[:error]}"
    end
  end
end