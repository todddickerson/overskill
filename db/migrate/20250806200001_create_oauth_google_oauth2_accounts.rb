class CreateOauthGoogleOauth2Accounts < ActiveRecord::Migration[8.0]
  def change
    create_table :oauth_google_oauth2_accounts do |t|
      t.string :uid
      t.jsonb :data
      t.references :user, null: true, foreign_key: true

      t.timestamps
    end
  end
end
