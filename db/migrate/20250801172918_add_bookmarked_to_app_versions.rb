class AddBookmarkedToAppVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_versions, :bookmarked, :boolean, default: false, null: false
    add_index :app_versions, :bookmarked
  end
end
