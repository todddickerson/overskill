class AddStagingFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :staging_url, :string
    add_column :apps, :staging_deployed_at, :datetime
    add_column :apps, :preview_updated_at, :datetime
  end
end
