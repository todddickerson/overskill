# Test for multi-shard Supabase sync functionality
require "test_helper"

class SupabaseServiceTest < ActiveSupport::TestCase
  test "SupabaseShardService initializes correctly" do
    shard = OpenStruct.new(
      name: "test-shard",
      supabase_url: "https://test.supabase.co",
      supabase_anon_key: "anon-key",
      supabase_service_key: "service-key"
    )

    service = SupabaseShardService.new(shard)
    assert_not_nil service
  end

  test "SupabaseService is a singleton" do
    service1 = SupabaseService.instance
    service2 = SupabaseService.instance
    assert_equal service1, service2
  end

  test "UserShardMapping model exists and has correct associations" do
    # Test that the model exists
    assert defined?(UserShardMapping)

    # Test associations
    mapping = UserShardMapping.new
    assert mapping.respond_to?(:user)
    assert mapping.respond_to?(:database_shard)
    assert mapping.respond_to?(:supabase_user_id)
    assert mapping.respond_to?(:sync_status)
  end

  test "UserShardMapping has correct enum values" do
    mapping = UserShardMapping.new

    # Test enum values
    mapping.sync_status = "pending"
    assert mapping.pending?

    mapping.sync_status = "synced"
    assert mapping.synced?

    mapping.sync_status = "failed"
    assert mapping.failed?
  end

  test "User model has shard mapping associations" do
    user = User.first || User.create!(
      email: "test@example.com",
      password: "password123",
      name: "Test User"
    )
    assert user.respond_to?(:user_shard_mappings)
    assert user.respond_to?(:database_shards)
  end
end
