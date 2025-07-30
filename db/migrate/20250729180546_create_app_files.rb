class CreateAppFiles < ActiveRecord::Migration[8.0]
  def change
    create_table :app_files do |t|
      t.references :team, null: false, foreign_key: true
      t.references :app, null: false, foreign_key: true
      t.string :path, null: false
      t.text :content, null: false
      t.string :file_type
      t.integer :size_bytes
      t.string :checksum
      t.boolean :is_entry_point, default: false, default: false

      t.timestamps
    end

    add_index :app_files, [:app_id, :path], unique: true
  end
end
