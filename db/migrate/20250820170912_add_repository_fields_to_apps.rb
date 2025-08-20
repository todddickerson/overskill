class AddRepositoryFieldsToApps < ActiveRecord::Migration[8.0]
  def change
    # GitHub repository tracking (using obfuscated_id for privacy) - NEW FIELDS
    add_column :apps, :repository_url, :string
    add_column :apps, :repository_name, :string  # Generated with obfuscated_id
    add_column :apps, :github_repo_id, :integer
    
    # Cloudflare Workers tracking (using obfuscated_id for privacy) - NEW FIELDS
    add_column :apps, :cloudflare_worker_name, :string  # Generated with obfuscated_id
    # Note: preview_url, staging_url, production_url, staging_deployed_at, 
    # last_deployed_at, and deployment_status already exist
    
    # Migration and deployment status - NEW FIELDS
    add_column :apps, :repository_status, :string, default: 'pending'

    # Indexes (repository_name includes obfuscated_id, so safe to index)
    add_index :apps, :repository_name, unique: true
    add_index :apps, :repository_status
    # Note: deployment_status index may already exist, adding with if_not_exists
    add_index :apps, :deployment_status, if_not_exists: true
  end
end
