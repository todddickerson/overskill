class CreateAppVersions < ActiveRecord::Migration[8.0]
  def change
    create_table :app_versions do |t|
      t.references :team, null: false, foreign_key: true
      t.references :app, null: false, foreign_key: true
      t.references :user, null: true, foreign_key: true
      t.string :commit_sha
      t.string :commit_message
      t.string :version_number, null: false
      t.text :changelog
      t.text :files_snapshot
      t.text :changed_files
      t.boolean :external_commit, default: false
      t.boolean :deployed, default: false
      t.datetime :published_at

      t.timestamps
    end
  end
end
