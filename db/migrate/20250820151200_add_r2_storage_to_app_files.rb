class AddR2StorageToAppFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :app_files, :storage_location, :string, default: "database"
    add_column :app_files, :r2_object_key, :string
    add_column :app_files, :content_hash, :string

    add_index :app_files, :storage_location
    add_index :app_files, :r2_object_key, unique: true, where: "r2_object_key IS NOT NULL"
    add_index :app_files, :content_hash

    # Add constraint to ensure either content or r2_object_key exists
    add_check_constraint :app_files, "content IS NOT NULL OR r2_object_key IS NOT NULL", name: "content_or_r2_key_required"
  end
end
