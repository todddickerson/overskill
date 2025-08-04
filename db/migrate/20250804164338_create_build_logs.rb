class CreateBuildLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :build_logs do |t|
      t.references :deployment_log, null: false, foreign_key: true
      t.string :level
      t.text :message

      t.timestamps
    end
  end
end
