# Service for managing Supabase operations across multiple shards
class SupabaseShardService
  include HTTParty
  
  def initialize(database_shard)
    @shard = database_shard
    @base_uri = @shard.supabase_url
    @headers = {
      'Authorization' => "Bearer #{@shard.supabase_service_key}",
      'Content-Type' => 'application/json',
      'apikey' => @shard.supabase_anon_key
    }
  end
  
  # Create a new auth user in this shard
  def create_user(email, password = nil, metadata = {})
    password ||= SecureRandom.hex(16)
    
    response = self.class.post("#{@base_uri}/auth/v1/admin/users", {
      headers: @headers,
      body: {
        email: email,
        password: password,
        email_confirm: true,
        user_metadata: metadata
      }.to_json
    })
    
    if response.success?
      { success: true, data: response.parsed_response, shard: @shard.name }
    else
      { success: false, error: response.parsed_response['error'] || response.message, shard: @shard.name }
    end
  rescue => e
    { success: false, error: e.message, shard: @shard.name }
  end
  
  # Update existing Supabase user in this shard
  def update_user(supabase_user_id, attributes)
    response = self.class.patch("#{@base_uri}/auth/v1/admin/users/#{supabase_user_id}", {
      headers: @headers,
      body: attributes.to_json
    })
    
    if response.success?
      { success: true, data: response.parsed_response, shard: @shard.name }
    else
      { success: false, error: response.parsed_response['error'] || response.message, shard: @shard.name }
    end
  rescue => e
    { success: false, error: e.message, shard: @shard.name }
  end
  
  # Create or update user profile in this shard
  def create_profile(user, shard_user_id)
    profile_data = {
      id: shard_user_id,
      rails_user_id: user.id,
      email: user.email,
      name: user.name,
      team_id: user.current_team&.id,
      created_at: Time.current.iso8601,
      updated_at: Time.current.iso8601
    }
    
    response = self.class.post("#{@base_uri}/rest/v1/profiles", {
      headers: @headers,
      body: profile_data.to_json
    })
    
    # Handle upsert - if conflict, update instead
    if response.code == 409 # Conflict
      response = self.class.patch("#{@base_uri}/rest/v1/profiles?id=eq.#{shard_user_id}", {
        headers: @headers,
        body: profile_data.except(:id, :created_at).to_json
      })
    end
    
    if response.success?
      { success: true, data: response.parsed_response, shard: @shard.name }
    else
      { success: false, error: response.parsed_response['error'] || response.message, shard: @shard.name }
    end
  rescue => e
    { success: false, error: e.message, shard: @shard.name }
  end
  
  # Delete user from this shard
  def delete_user(supabase_user_id)
    response = self.class.delete("#{@base_uri}/auth/v1/admin/users/#{supabase_user_id}", {
      headers: @headers
    })
    
    if response.success?
      { success: true, shard: @shard.name }
    else
      { success: false, error: response.parsed_response['error'] || response.message, shard: @shard.name }
    end
  rescue => e
    { success: false, error: e.message, shard: @shard.name }
  end
end
