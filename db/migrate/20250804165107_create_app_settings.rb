class CreateAppSettings < ActiveRecord::Migration[8.0]
  def change
    create_table :app_settings do |t|
      t.references :app, null: false, foreign_key: true
      t.string :key
      t.text :value
      t.boolean :encrypted
      t.text :description
      t.string :setting_type

      t.timestamps
    end
  end
end
