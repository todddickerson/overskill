require 'test_helper'

class MultiShardSupabaseSyncTest < ActiveSupport::TestCase
  setup do
    # Create mock database shards
    @shard1 = DatabaseShard.create!(
      name: 'test-shard-001',
      shard_number: 1,
      supabase_project_id: 'test-project-001',
      supabase_url: 'https://test-shard-001.supabase.co',
      supabase_anon_key: 'test-anon-key-001',
      supabase_service_key: 'test-service-key-001',
      app_count: 0,
      status: 'available'
    )
    
    @shard2 = DatabaseShard.create!(
      name: 'test-shard-002',
      shard_number: 2,
      supabase_project_id: 'test-project-002',
      supabase_url: 'https://test-shard-002.supabase.co',
      supabase_anon_key: 'test-anon-key-002',
      supabase_service_key: 'test-service-key-002',
      app_count: 0,
      status: 'available'
    )
    
    # Mock successful responses using WebMock
    stub_request(:post, /supabase\.co\/auth\/v1\/admin\/users/)
      .to_return(
        status: 200,
        body: {
          id: SecureRandom.uuid,
          email: 'test@example.com',
          created_at: Time.current.iso8601
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    stub_request(:patch, /supabase\.co\/auth\/v1\/admin\/users/)
      .to_return(
        status: 200,
        body: {
          id: SecureRandom.uuid,
          email: 'test@example.com',
          updated_at: Time.current.iso8601
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    stub_request(:post, /supabase\.co\/rest\/v1\/profiles/)
      .to_return(
        status: 200,
        body: { success: true }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    stub_request(:patch, /supabase\.co\/rest\/v1\/profiles/)
      .to_return(
        status: 200,
        body: { success: true }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    stub_request(:delete, /supabase\.co\/auth\/v1\/admin\/users/)
      .to_return(
        status: 200,
        body: {}.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
  
  test 'creating a user syncs to all available shards' do
    user = User.create!(
      email: 'test@example.com',
      name: 'Test User',
      password: 'password123'
    )
    
    # Process background jobs
    perform_enqueued_jobs
    
    # Check that user was synced to both shards
    assert_equal 2, user.user_shard_mappings.count
    assert_equal 'synced', user.supabase_sync_status
    assert_not_nil user.supabase_user_id
    
    # Verify mappings exist for both shards
    shard1_mapping = user.user_shard_mappings.find_by(database_shard: @shard1)
    assert_not_nil shard1_mapping
    assert_equal 'synced', shard1_mapping.sync_status
    assert_not_nil shard1_mapping.supabase_user_id
    
    shard2_mapping = user.user_shard_mappings.find_by(database_shard: @shard2)
    assert_not_nil shard2_mapping
    assert_equal 'synced', shard2_mapping.sync_status
    assert_not_nil shard2_mapping.supabase_user_id
  end
  
  test 'updating a user syncs changes to all shards' do
    # Create a user with existing shard mappings
    user = users(:one)
    user.update!(
      supabase_user_id: SecureRandom.uuid,
      supabase_sync_status: 'synced'
    )
    
    # Create shard mappings
    user.user_shard_mappings.create!(
      database_shard: @shard1,
      supabase_user_id: user.supabase_user_id,
      sync_status: 'synced'
    )
    
    user.user_shard_mappings.create!(
      database_shard: @shard2,
      supabase_user_id: user.supabase_user_id,
      sync_status: 'synced'
    )
    
    # Update the user
    user.update!(name: 'Updated Name')
    
    # Process background jobs
    perform_enqueued_jobs
    
    # Verify user was updated
    user.reload
    assert_equal 'Updated Name', user.name
    assert_equal 'synced', user.supabase_sync_status
    
    # Verify update requests were made to both shards
    assert_requested :patch, "#{@shard1.supabase_url}/auth/v1/admin/users/#{user.supabase_user_id}", times: 1
    assert_requested :patch, "#{@shard2.supabase_url}/auth/v1/admin/users/#{user.supabase_user_id}", times: 1
  end
  
  test 'handles partial shard sync failures gracefully' do
    # Stub first shard to fail, second to succeed
    stub_request(:post, "#{@shard1.supabase_url}/auth/v1/admin/users")
      .to_return(
        status: 500,
        body: { error: 'Connection timeout' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    user = User.create!(
      email: 'partial@example.com',
      name: 'Partial User',
      password: 'password123'
    )
    
    # Process background jobs
    perform_enqueued_jobs
    
    # User should still be created and marked as synced (at least one shard succeeded)
    assert_equal 'synced', user.supabase_sync_status
    assert_not_nil user.supabase_user_id
    
    # Only one shard should have a successful mapping
    assert_equal 1, user.user_shard_mappings.synced.count
    assert_equal @shard2, user.user_shard_mappings.synced.first.database_shard
  end
  
  test 'user shard mapping model validations and scopes' do
    user = users(:one)
    
    # Test uniqueness validation
    mapping1 = UserShardMapping.create!(
      user: user,
      database_shard: @shard1,
      supabase_user_id: SecureRandom.uuid
    )
    
    # Should not allow duplicate user/shard combination
    mapping2 = UserShardMapping.new(
      user: user,
      database_shard: @shard1,
      supabase_user_id: SecureRandom.uuid
    )
    assert_not mapping2.valid?
    assert_includes mapping2.errors[:user_id], 'has already been taken'
    
    # Test scopes
    assert_includes UserShardMapping.for_shard(@shard1), mapping1
    assert_empty UserShardMapping.for_shard(@shard2)
    
    # Test status transitions
    assert mapping1.pending?
    mapping1.synced!
    assert mapping1.synced?
    assert_includes UserShardMapping.synced, mapping1
  end
  
  test 'SupabaseService handles multiple shards correctly' do
    service = SupabaseService.instance
    
    # Test create_user method
    result = service.create_user('newuser@example.com', 'password123', { name: 'New User' })
    
    assert result[:success]
    assert_equal 2, result[:synced_shards].count
    assert_includes result[:synced_shards], @shard1.name
    assert_includes result[:synced_shards], @shard2.name
    assert_empty result[:failed_shards]
  end
  
  test 'SupabaseShardService works with individual shards' do
    shard_service = SupabaseShardService.new(@shard1)
    
    # Test create_user on specific shard
    result = shard_service.create_user('sharduser@example.com', 'password123', { name: 'Shard User' })
    
    assert result[:success]
    assert_equal @shard1.name, result[:shard]
    assert_not_nil result[:data]['id']
  end
  
  private
  
  def perform_enqueued_jobs
    # Execute all enqueued jobs synchronously for testing
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = true
  end
end
