class CreateAppVersionFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :app_version_files do |t|
      t.references :app_version, null: false, foreign_key: true
      t.references :app_file, null: false, foreign_key: true
      t.text :content
      t.string :action

      t.timestamps
    end

    # Add indexes for common queries
    add_index :app_version_files, [:app_version_id, :app_file_id], unique: true
  end
end
