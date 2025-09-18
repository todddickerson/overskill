class AddR2StorageToAppVersionFiles < ActiveRecord::Migration[8.0]
  def change
    add_column :app_version_files, :r2_content_key, :string

    add_index :app_version_files, :r2_content_key, unique: true, where: "r2_content_key IS NOT NULL"

    # Add constraint to ensure either content or r2_content_key exists
    add_check_constraint :app_version_files, "content IS NOT NULL OR r2_content_key IS NOT NULL", name: "version_content_or_r2_key_required"
  end
end
