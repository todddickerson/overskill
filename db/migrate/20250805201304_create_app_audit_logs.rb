class CreateAppAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :app_audit_logs do |t|
      t.references :app, null: false, foreign_key: true
      t.string :action_type
      t.string :performed_by
      t.string :target_resource
      t.string :resource_id
      t.text :change_details
      t.string :ip_address
      t.string :user_agent
      t.datetime :occurred_at

      t.timestamps
    end
  end
end
