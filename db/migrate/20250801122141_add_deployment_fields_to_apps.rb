class AddDeploymentFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :deployment_url, :string
    add_column :apps, :deployment_status, :string
    add_column :apps, :deployed_at, :datetime
  end
end
