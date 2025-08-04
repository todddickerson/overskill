class CreateAppTables < ActiveRecord::Migration[8.0]
  def change
    create_table :app_tables do |t|
      t.references :app, null: false, foreign_key: true
      t.string :name
      t.text :description

      t.timestamps
    end
  end
end
