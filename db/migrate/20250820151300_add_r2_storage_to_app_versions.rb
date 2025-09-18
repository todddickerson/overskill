class AddR2StorageToAppVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_versions, :storage_strategy, :string, default: "database"
    add_column :app_versions, :r2_snapshot_key, :string

    add_index :app_versions, :storage_strategy
    add_index :app_versions, :r2_snapshot_key, unique: true, where: "r2_snapshot_key IS NOT NULL"

    # Add constraint to ensure either files_snapshot or r2_snapshot_key exists for versions that need restoration
    add_check_constraint :app_versions, "files_snapshot IS NOT NULL OR r2_snapshot_key IS NOT NULL OR storage_strategy = 'database'", name: "snapshot_data_required"
  end
end
