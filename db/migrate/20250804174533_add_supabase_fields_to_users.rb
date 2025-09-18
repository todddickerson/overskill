class AddSupabaseFieldsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :supabase_user_id, :string
    add_column :users, :supabase_sync_status, :string, default: "pending"
    add_column :users, :supabase_last_synced_at, :datetime

    add_index :users, :supabase_user_id, unique: true
    add_index :users, :supabase_sync_status
  end
end
