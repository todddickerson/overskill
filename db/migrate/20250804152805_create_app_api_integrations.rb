class CreateAppApiIntegrations < ActiveRecord::Migration[8.0]
  def change
    create_table :app_api_integrations do |t|
      t.references :app, null: false, foreign_key: true
      t.string :name
      t.string :base_url
      t.string :auth_type
      t.string :api_key
      t.string :path_prefix
      t.text :additional_headers
      t.boolean :enabled

      t.timestamps
    end
  end
end
