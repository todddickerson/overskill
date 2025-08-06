class AddBuildFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :build_status, :string
    add_column :apps, :build_error, :text
    add_column :apps, :last_built_at, :datetime
    add_column :apps, :build_id, :string
  end
end
