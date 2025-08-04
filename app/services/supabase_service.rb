# Singleton service for managing Supabase interactions
class SupabaseService
  include Singleton
  
  attr_reader :client
  
  def initialize
    @client = SupabaseApi::Client.new(
      supabase_url: ENV['SUPABASE_URL'],
      supabase_key: ENV['SUPABASE_SERVICE_KEY'] || ENV['SUPABASE_ANON_KEY']
    )
  end
  
  # Create a new auth user in Supabase
  def create_user(email, password = nil, metadata = {})
    password ||= SecureRandom.hex(16)
    
    # Using the admin API to create users
    response = @client.auth.admin.create_user({
      email: email,
      password: password,
      email_confirm: true,
      user_metadata: metadata
    })
    
    if response.success?
      { success: true, data: response.data }
    else
      { success: false, error: response.error }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Update existing Supabase user
  def update_user(supabase_user_id, attributes)
    response = @client.auth.admin.update_user_by_id(
      supabase_user_id,
      attributes
    )
    
    if response.success?
      { success: true, data: response.data }
    else
      { success: false, error: response.error }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Create or update user profile in Supabase
  def create_profile(user)
    profile_data = {
      id: user.supabase_user_id,
      rails_user_id: user.id,
      email: user.email,
      name: user.name,
      team_id: user.current_team&.id,
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601
    }
    
    response = @client.from('profiles').upsert(profile_data).execute
    
    if response.success?
      { success: true, data: response.data }
    else
      { success: false, error: response.error }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Delete user from Supabase
  def delete_user(supabase_user_id)
    response = @client.auth.admin.delete_user(supabase_user_id)
    
    if response.success?
      { success: true }
    else
      { success: false, error: response.error }
    end
  rescue => e
    { success: false, error: e.message }
  end
  
  # Verify webhook signature
  def verify_webhook_signature(payload, signature)
    secret = ENV['SUPABASE_WEBHOOK_SECRET']
    return false unless secret
    
    expected_signature = OpenSSL::HMAC.hexdigest(
      'SHA256',
      secret,
      payload
    )
    
    ActiveSupport::SecurityUtils.secure_compare(signature, expected_signature)
  end
end