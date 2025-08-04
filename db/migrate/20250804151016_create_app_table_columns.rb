class CreateAppTableColumns < ActiveRecord::Migration[8.0]
  def change
    create_table :app_table_columns do |t|
      t.references :app_table, null: false, foreign_key: true
      t.string :name
      t.string :column_type
      t.text :options
      t.boolean :required
      t.string :default_value

      t.timestamps
    end
  end
end
