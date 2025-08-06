class CreateIntegrationsGithubInstallations < ActiveRecord::Migration[8.0]
  def change
    create_table :integrations_github_installations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :oauth_github_account, null: false, foreign_key: true, index: {name: "index_github_installations_on_oauth_github_account_id"}
      t.string :name

      t.timestamps
    end
  end
end
