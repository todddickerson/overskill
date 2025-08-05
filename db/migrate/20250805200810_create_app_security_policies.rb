class CreateAppSecurityPolicies < ActiveRecord::Migration[8.0]
  def change
    create_table :app_security_policies do |t|
      t.references :app, null: false, foreign_key: true
      t.string :policy_name
      t.string :policy_type
      t.boolean :enabled, default: false
      t.text :configuration
      t.text :description
      t.datetime :last_violation
      t.integer :violation_count

      t.timestamps
    end
  end
end
