class AddEnvironmentToAppVersions < ActiveRecord::Migration[8.0]
  def change
    add_column :app_versions, :environment, :string
  end
end
