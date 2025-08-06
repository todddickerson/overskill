class CreateWebhooksIncomingOauthGoogleOauth2AccountWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks_incoming_oauth_google_oauth2_account_webhooks do |t|
      t.jsonb :data
      t.datetime :processed_at
      t.datetime :verified_at
      t.references :oauth_google_oauth2_account, null: true, foreign_key: true, index: {name: "idx_google_oauth2_webhooks_on_oauth_account_id"}

      t.timestamps
    end
  end
end
