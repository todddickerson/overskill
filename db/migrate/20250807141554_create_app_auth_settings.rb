class CreateAppAuthSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :app_auth_settings do |t|
      t.references :app, null: false, foreign_key: true, index: {unique: true}
      t.integer :visibility, default: 1, null: false # Default to public_login_required
      t.text :allowed_providers, default: '["email", "google", "github"]'
      t.text :allowed_email_domains, default: "[]" # Empty array = all domains allowed
      t.boolean :require_email_verification, default: false, null: false
      t.boolean :allow_signups, default: true, null: false
      t.boolean :allow_anonymous, default: false, null: false

      t.timestamps
    end

    add_index :app_auth_settings, :visibility
  end
end
