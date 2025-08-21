class AddGithubTagToAppVersions < ActiveRecord::Migration[8.0]
  def change
    # Add GitHub tag tracking for version restoration
    add_column :app_versions, :github_tag, :string
    add_column :app_versions, :github_commit_sha, :string
    add_column :app_versions, :github_tag_url, :string
    add_column :app_versions, :tagged_at, :datetime
    
    # Add index for quick tag lookups
    add_index :app_versions, :github_tag
    add_index :app_versions, [:app_id, :github_tag], unique: true
    
    # Add comment to explain the fields
    change_column_comment :app_versions, :github_tag, 
      'GitHub tag name for this version (e.g., v1.2.3-20250821)'
    change_column_comment :app_versions, :github_commit_sha, 
      'Git commit SHA associated with this version'
    change_column_comment :app_versions, :github_tag_url, 
      'URL to view this tag on GitHub'
    change_column_comment :app_versions, :tagged_at, 
      'Timestamp when the GitHub tag was created'
  end
end