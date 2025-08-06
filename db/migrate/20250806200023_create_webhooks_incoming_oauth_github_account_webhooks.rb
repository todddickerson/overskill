class CreateWebhooksIncomingOauthGithubAccountWebhooks < ActiveRecord::Migration[8.0]
  def change
    create_table :webhooks_incoming_oauth_github_account_webhooks do |t|
      t.jsonb :data
      t.datetime :processed_at
      t.datetime :verified_at
      t.references :oauth_github_account, null: true, foreign_key: true, index: {name: "index_github_webhooks_on_oauth_github_account_id"}

      t.timestamps
    end
  end
end
