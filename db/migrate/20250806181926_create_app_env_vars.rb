class CreateAppEnvVars < ActiveRecord::Migration[8.0]
  def change
    create_table :app_env_vars do |t|
      t.references :app, null: false, foreign_key: true
      t.string :key
      t.string :value
      t.string :description
      t.boolean :is_secret, default: false
      t.boolean :is_system, default: false

      t.timestamps
    end
  end
end
