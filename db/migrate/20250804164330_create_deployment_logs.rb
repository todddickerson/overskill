class CreateDeploymentLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :deployment_logs do |t|
      t.references :app, null: false, foreign_key: true
      t.string :environment
      t.string :status
      t.references :initiated_by, null: false, foreign_key: {to_table: :users}
      t.string :deployment_url
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.references :rollback_from, foreign_key: {to_table: :deployment_logs}
      t.string :deployed_version
      t.text :build_output

      t.timestamps
    end
  end
end
