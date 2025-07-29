class CreateAppCollaborators < ActiveRecord::Migration[8.0]
  def change
    create_table :app_collaborators do |t|
      t.references :team, null: false, foreign_key: true
      t.references :app, null: false, foreign_key: true
      t.references :membership, null: true, foreign_key: true
      t.string :role, default: 'viewer'
      t.string :github_username
      t.boolean :permissions_synced, default: false

      t.timestamps
    end
  end
end
