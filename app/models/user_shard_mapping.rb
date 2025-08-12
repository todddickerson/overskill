# Tracks user IDs across different Supabase shards
class UserShardMapping < ApplicationRecord
  belongs_to :user
  belongs_to :database_shard
  
  validates :supabase_user_id, presence: true, uniqueness: { scope: :database_shard_id }
  validates :user_id, uniqueness: { scope: :database_shard_id }
  
  # Encrypt sensitive data
  encrypts :supabase_user_id
  
  # Scopes
  scope :for_shard, ->(shard) { where(database_shard: shard) }
  scope :synced, -> { where(sync_status: 'synced') }
  scope :failed, -> { where(sync_status: 'failed') }
  
  # Status enum
  enum :sync_status, {
    pending: 'pending',
    syncing: 'syncing',
    synced: 'synced',
    failed: 'failed',
    deleted: 'deleted'
  }, default: :pending
  
  # Find or create mapping for user and shard
  def self.find_or_initialize_for(user, shard)
    find_or_initialize_by(user: user, database_shard: shard)
  end
end
