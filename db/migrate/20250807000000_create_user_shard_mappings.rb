class CreateUserShardMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :user_shard_mappings do |t|
      t.references :user, null: false, foreign_key: true
      t.references :database_shard, null: false, foreign_key: true
      t.string :supabase_user_id, null: false
      t.string :sync_status, default: 'pending'
      t.datetime :last_synced_at
      t.text :sync_error
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Ensure unique user per shard
    add_index :user_shard_mappings, [:user_id, :database_shard_id], unique: true
    add_index :user_shard_mappings, [:database_shard_id, :supabase_user_id], unique: true
    add_index :user_shard_mappings, :sync_status
  end
end
