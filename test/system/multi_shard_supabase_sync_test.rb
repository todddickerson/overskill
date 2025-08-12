require 'application_system_test_case'

class MultiShardSupabaseSyncTest < ApplicationSystemTestCase
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
    
    # Stub HTTParty responses
    @successful_response = OpenStruct.new(
      success?: true,
      parsed_response: {
        'id' => SecureRandom.uuid,
        'email' => 'test@example.com',
        'created_at' => Time.current.iso8601
      },
      code: 200
    )
    
    # Mock the HTTParty class methods
    HTTParty.stub :post, @successful_response do
      HTTParty.stub :patch, @successful_response do
        HTTParty.stub :delete, OpenStruct.new(success?: true, parsed_response: {}, code: 200) do
          yield if block_given?
        end
      end
    end
  end
  
  test 'creating a user syncs to all available shards' do
    HTTParty.stub :post, @successful_response do
      # Visit signup page
      visit new_user_registration_path
      
      # Fill in registration form
      fill_in 'Your Name', with: 'Test User'
      fill_in 'Your Email Address', with: 'test@example.com'
      fill_in 'Set Password', with: 'password123'
      fill_in 'Confirm Password', with: 'password123'
      
      # Submit the form
      click_button 'Sign Up'
      
      # User should be created
      user = User.find_by(email: 'test@example.com')
      assert_not_nil user
      
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
  end
  
  test 'updating a user syncs changes to all shards' do
    HTTParty.stub :patch, @successful_response do
      # Create a user with existing shard mappings
      user = users(:one).dup
      user.update!(
        email: 'existing@example.com',
        name: 'Existing User',
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
      
      # Sign in as the user
      login_as(user, scope: :user)
      
      # Visit account settings
      visit edit_account_user_path
      
      # Update name
      fill_in 'Your Name', with: 'Updated Name'
      click_button 'Save Changes'
      
      # Process background jobs
      perform_enqueued_jobs
      
      # Verify user was updated
      user.reload
      assert_equal 'Updated Name', user.name
      assert_equal 'synced', user.supabase_sync_status
    end
  end
  
  test 'handles partial shard sync failures gracefully' do
    # Create a sequence of responses - first fails, second succeeds
    failed_response = OpenStruct.new(
      success?: false,
      parsed_response: { 'error' => 'Connection timeout' },
      code: 500,
      message: 'Internal Server Error'
    )
    
    responses = [failed_response, @successful_response]
    call_count = 0
    
    # Stub to return different responses on each call
    HTTParty.stub :post, -> (*args) { 
      response = responses[call_count % responses.length]
      call_count += 1
      response
    } do
      # Create a new user
      visit new_user_registration_path
      fill_in 'Your Name', with: 'Partial User'
      fill_in 'Your Email Address', with: 'partial@example.com'
      fill_in 'Set Password', with: 'password123'
      fill_in 'Confirm Password', with: 'password123'
      click_button 'Sign Up'
      
      # Process background jobs
      perform_enqueued_jobs
      
      # User should still be created and marked as synced
      user = User.find_by(email: 'partial@example.com')
      assert_not_nil user
      assert_equal 'synced', user.supabase_sync_status
      assert_not_nil user.supabase_user_id
      
      # Only one shard should have a successful mapping
      assert_equal 1, user.user_shard_mappings.synced.count
    end
  end
  
  test 'user shard mapping tracks sync status correctly' do
    user = users(:one).dup
    user.update!(email: 'mapping-test@example.com')
    
    # Create a mapping
    mapping = UserShardMapping.create!(
      user: user,
      database_shard: @shard1,
      supabase_user_id: SecureRandom.uuid,
      sync_status: 'pending'
    )
    
    # Test status transitions
    assert mapping.pending?
    
    mapping.syncing!
    assert mapping.syncing?
    
    mapping.synced!
    assert mapping.synced?
    
    mapping.failed!
    assert mapping.failed?
    
    # Test scopes
    assert_includes UserShardMapping.for_shard(@shard1), mapping
    assert_empty UserShardMapping.for_shard(@shard2)
  end
  
  private
  
  def perform_enqueued_jobs
    # Execute all enqueued jobs synchronously for testing
    ActiveJob::Base.queue_adapter.perform_enqueued_jobs = true
    ActiveJob::Base.queue_adapter.perform_enqueued_at_jobs = true
    
    ActiveJob::Base.queue_adapter.enqueued_jobs.each do |job|
      ActiveJob::Base.execute(job)
    end
    
    ActiveJob::Base.queue_adapter.performed_jobs.clear
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end
  
  def login_as(user, scope:)
    # Helper for Devise login in system tests
    visit new_user_session_path
    fill_in 'Your Email Address', with: user.email
    fill_in 'Your Password', with: user.password || 'password'
    click_button 'Sign In'
  end
end