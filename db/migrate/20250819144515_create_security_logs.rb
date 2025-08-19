class CreateSecurityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :security_logs do |t|
      t.references :user, null: true, foreign_key: true
      t.references :app, null: true, foreign_key: true
      t.string :event_type, null: false
      t.jsonb :details, null: false, default: {}
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end
    
    add_index :security_logs, :event_type
    add_index :security_logs, :created_at
    add_index :security_logs, [:user_id, :created_at]
    add_index :security_logs, :details, using: :gin
  end
end
