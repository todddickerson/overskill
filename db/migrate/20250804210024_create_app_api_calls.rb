class CreateAppApiCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :app_api_calls do |t|
      t.references :app, null: false, foreign_key: true
      t.string :http_method
      t.string :path
      t.integer :status_code
      t.integer :response_time
      t.text :request_body
      t.text :response_body
      t.string :user_agent
      t.string :ip_address
      t.datetime :occurred_at

      t.timestamps
    end

    add_index :app_api_calls, [:app_id, :occurred_at]
    add_index :app_api_calls, :occurred_at
    add_index :app_api_calls, :http_method
    add_index :app_api_calls, :status_code
  end
end
