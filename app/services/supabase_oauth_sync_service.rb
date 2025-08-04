# Service to sync OAuth providers between Rails and Supabase
class SupabaseOauthSyncService
  include Singleton
  
  # Map Rails OAuth providers to Supabase provider names
  PROVIDER_MAPPING = {
    'google_oauth2' => 'google',
    'github' => 'github',
    'facebook' => 'facebook',
    'twitter' => 'twitter',
    'apple' => 'apple',
    'discord' => 'discord',
    'linkedin' => 'linkedin'
  }.freeze
  
  def sync_oauth_user(user, auth_hash)
    Rails.logger.info "[SupabaseOauthSync] Syncing OAuth user: #{user.email}, provider: #{auth_hash.provider}"
    
    # Get or create Supabase user
    if user.supabase_user_id.present?
      # Update existing user
      update_oauth_identity(user, auth_hash)
    else
      # Create new user with OAuth identity
      create_oauth_user(user, auth_hash)
    end
  end
  
  def link_oauth_identity(user, provider, uid, auth_data = {})
    return unless user.supabase_user_id.present?
    
    supabase_provider = PROVIDER_MAPPING[provider] || provider
    
    Rails.logger.info "[SupabaseOauthSync] Linking #{supabase_provider} identity for user #{user.id}"
    
    # This would typically be done through Supabase Admin API
    # For now, we'll store the mapping in user metadata
    result = SupabaseService.instance.update_user(
      user.supabase_user_id,
      {
        user_metadata: {
          oauth_identities: {
            supabase_provider => {
              uid: uid,
              linked_at: Time.current.iso8601,
              auth_data: auth_data
            }
          }
        }
      }
    )
    
    if result[:success]
      Rails.logger.info "[SupabaseOauthSync] Successfully linked OAuth identity"
    else
      Rails.logger.error "[SupabaseOauthSync] Failed to link OAuth identity: #{result[:error]}"
    end
    
    result
  end
  
  private
  
  def create_oauth_user(user, auth_hash)
    Rails.logger.info "[SupabaseOauthSync] Creating new Supabase user with OAuth"
    
    # Create user in Supabase with OAuth metadata
    result = SupabaseService.instance.create_user(
      user.email,
      nil, # No password for OAuth users
      {
        rails_user_id: user.id,
        first_name: user.first_name,
        last_name: user.last_name,
        name: user.name,
        oauth_provider: auth_hash.provider,
        oauth_uid: auth_hash.uid,
        created_via: 'oauth',
        oauth_identities: {
          PROVIDER_MAPPING[auth_hash.provider] || auth_hash.provider => {
            uid: auth_hash.uid,
            email: auth_hash.info.email,
            name: auth_hash.info.name,
            image: auth_hash.info.image,
            linked_at: Time.current.iso8601
          }
        }
      }
    )
    
    if result[:success]
      supabase_user = result[:data]
      user.update!(
        supabase_user_id: supabase_user['id'],
        supabase_sync_status: 'synced',
        supabase_last_synced_at: Time.current
      )
      
      # Create profile
      SupabaseService.instance.create_profile(user)
    end
    
    result
  end
  
  def update_oauth_identity(user, auth_hash)
    Rails.logger.info "[SupabaseOauthSync] Updating OAuth identity for existing user"
    
    # Add or update OAuth identity in user metadata
    link_oauth_identity(
      user,
      auth_hash.provider,
      auth_hash.uid,
      {
        email: auth_hash.info.email,
        name: auth_hash.info.name,
        image: auth_hash.info.image
      }
    )
  end
end