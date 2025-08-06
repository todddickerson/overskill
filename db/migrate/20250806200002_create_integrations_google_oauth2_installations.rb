class CreateIntegrationsGoogleOauth2Installations < ActiveRecord::Migration[8.0]
  def change
    create_table :integrations_google_oauth2_installations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :oauth_google_oauth2_account, null: false, foreign_key: true, index: {name: "idx_google_oauth2_inst_on_oauth_account_id"}
      t.string :name

      t.timestamps
    end
  end
end
