class CreateAppDeployments < ActiveRecord::Migration[8.0]
  def change
    create_table :app_deployments do |t|
      t.references :app, null: false, foreign_key: true
      t.string :environment, null: false # preview, staging, production
      t.string :deployment_id
      t.string :deployment_url
      t.string :commit_sha
      t.text :deployment_metadata
      t.datetime :deployed_at
      t.boolean :is_rollback, default: false
      t.string :rollback_version_id
      t.timestamps
    end

    add_index :app_deployments, [:app_id, :environment]
    add_index :app_deployments, :deployed_at
  end
end
