class AddUseCustomDatabaseToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :use_custom_database, :boolean, default: false, null: false
    add_index :apps, :use_custom_database
  end
end
