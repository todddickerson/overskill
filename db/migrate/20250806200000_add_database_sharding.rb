class AddDatabaseSharding < ActiveRecord::Migration[8.0]
  def change
    # Create database_shards table for managing Supabase shards
    create_table :database_shards do |t|
      t.string :name, null: false
      t.integer :shard_number, null: false
      t.string :supabase_project_id, null: false
      t.string :supabase_url, null: false
      t.text :supabase_anon_key, null: false
      t.text :supabase_service_key, null: false
      t.integer :app_count, default: 0, null: false
      t.integer :status, default: 1, null: false # 1 = available
      t.jsonb :metadata, default: {}
      t.timestamps
    end
    
    add_index :database_shards, :name, unique: true
    add_index :database_shards, :supabase_project_id, unique: true
    add_index :database_shards, :status
    add_index :database_shards, :app_count
    
    # Add shard reference to apps
    add_reference :apps, :database_shard, foreign_key: true, index: true
    
    # Add shard-specific fields to apps
    add_column :apps, :shard_app_id, :string # Unique ID within the shard
    add_column :apps, :supabase_project_url, :string # Quick reference to shard URL
    
    add_index :apps, [:database_shard_id, :shard_app_id], unique: true
  end
end