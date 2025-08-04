class CreateFeatureFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_flags do |t|
      t.string :name
      t.boolean :enabled
      t.integer :percentage
      t.text :description

      t.timestamps
    end
  end
end
