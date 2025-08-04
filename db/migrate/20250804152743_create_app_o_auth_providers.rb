class CreateAppOAuthProviders < ActiveRecord::Migration[8.0]
  def change
    create_table :app_o_auth_providers do |t|
      t.references :app, null: false, foreign_key: true
      t.string :provider
      t.string :client_id
      t.string :client_secret
      t.string :domain
      t.string :redirect_uri
      t.text :scopes
      t.boolean :enabled

      t.timestamps
    end
  end
end
