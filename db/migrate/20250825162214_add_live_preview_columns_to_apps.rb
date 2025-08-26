class AddLivePreviewColumnsToApps < ActiveRecord::Migration[8.0]
  def change
    add_column :apps, :preview_websocket_url, :string
    add_column :apps, :preview_status, :string
    add_column :apps, :preview_error, :text
    add_column :apps, :preview_deployment_time, :decimal
    add_column :apps, :preview_provisioned_at, :datetime
  end
end
