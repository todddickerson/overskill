class AddStateTrackingToAppDeployments < ActiveRecord::Migration[7.1]
  def change
    # Add status tracking with enum support
    add_column :app_deployments, :status, :string, default: "pending", null: false

    # Track build phase timing
    add_column :app_deployments, :build_started_at, :datetime
    add_column :app_deployments, :build_completed_at, :datetime
    add_column :app_deployments, :build_duration_seconds, :integer

    # Track deployment phase timing
    add_column :app_deployments, :deploy_started_at, :datetime
    add_column :app_deployments, :deploy_completed_at, :datetime
    add_column :app_deployments, :deploy_duration_seconds, :integer

    # Error tracking
    add_column :app_deployments, :error_message, :text
    add_column :app_deployments, :error_details, :jsonb

    # Build metadata
    add_column :app_deployments, :build_log_url, :string
    add_column :app_deployments, :bundle_size_bytes, :integer
    add_column :app_deployments, :files_count, :integer

    # Performance tracking
    add_column :app_deployments, :worker_script_size_bytes, :integer
    add_column :app_deployments, :cold_start_duration_ms, :integer

    # Add indexes for querying
    add_index :app_deployments, :status
    add_index :app_deployments, [:app_id, :environment, :status]
    add_index :app_deployments, [:app_id, :created_at]

    # Add status tracking to apps table as well
    unless column_exists?(:apps, :processing_started_at)
      add_column :apps, :processing_started_at, :datetime
      add_column :apps, :processing_completed_at, :datetime
      add_column :apps, :last_processed_at, :datetime
    end
  end
end
