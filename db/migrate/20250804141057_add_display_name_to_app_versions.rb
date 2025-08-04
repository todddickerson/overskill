class AddDisplayNameToAppVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_versions, :display_name, :string
  end
end
