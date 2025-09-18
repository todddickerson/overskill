class AddFileSyncStatusToApps < ActiveRecord::Migration[8.0]
  def change
    # Add columns for tracking file sync status
    add_column :apps, :file_sync_status, :string, default: "pending"
    add_column :apps, :file_sync_started_at, :datetime
    add_column :apps, :file_sync_completed_at, :datetime
    add_column :apps, :file_sync_error, :text
    add_column :apps, :file_sync_attempted_at, :datetime
    add_column :apps, :file_sync_stats, :text

    # Add indexes for querying
    add_index :apps, :file_sync_status
    add_index :apps, [:file_sync_status, :created_at]

    # Also add R2 sync tracking columns to app_files for granular tracking
    add_column :app_files, :r2_sync_status, :string
    add_column :app_files, :r2_sync_error, :text
    add_column :app_files, :r2_sync_attempted_at, :datetime
    add_column :app_files, :r2_sync_completed_at, :datetime

    add_index :app_files, :r2_sync_status
    add_index :app_files, [:app_id, :r2_sync_status]
  end
end
