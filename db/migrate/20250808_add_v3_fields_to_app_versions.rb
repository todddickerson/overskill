class AddV3FieldsToAppVersions < ActiveRecord::Migration[7.0]
  def change
    # Add status for tracking version progress
    add_column :app_versions, :status, :string, default: "pending" unless column_exists?(:app_versions, :status)
    add_index :app_versions, :status unless index_exists?(:app_versions, :status)

    # Add timing fields
    add_column :app_versions, :started_at, :datetime unless column_exists?(:app_versions, :started_at)
    add_column :app_versions, :completed_at, :datetime unless column_exists?(:app_versions, :completed_at)

    # Add metadata for storing additional info
    add_column :app_versions, :metadata, :jsonb, default: {} unless column_exists?(:app_versions, :metadata)
    add_index :app_versions, :metadata, using: :gin unless index_exists?(:app_versions, :metadata)

    # Add error tracking
    add_column :app_versions, :error_message, :text unless column_exists?(:app_versions, :error_message)

    # display_name already exists from previous migration
  end
end
