class CreateAppOauthProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :app_oauth_providers do |t|
      t.references :app, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      
      t.string :provider_type, null: false
      t.string :client_id, null: false
      t.text :client_secret # Will be encrypted
      t.string :authorization_endpoint
      t.string :token_endpoint
      t.string :scope
      t.text :refresh_token # Will be encrypted
      t.text :access_token # Could be encrypted if needed
      t.datetime :token_expires_at
      t.boolean :enabled, default: true, null: false
      t.jsonb :settings, default: {}
      
      t.timestamps
    end
    
    add_index :app_oauth_providers, :provider_type
    add_index :app_oauth_providers, [:app_id, :provider_type], unique: true
    add_index :app_oauth_providers, :enabled
  end
end