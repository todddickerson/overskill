class CreateAppGenerations < ActiveRecord::Migration[8.0]
  def change
    create_table :app_generations do |t|
      t.references :team, null: false, foreign_key: true
      t.references :app, null: false, foreign_key: true
      t.text :prompt, null: false
      t.text :enhanced_prompt
      t.string :status, default: "processing"
      t.string :ai_model, default: "kimi-k2"
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.integer :duration_seconds
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :total_cost
      t.text :error_message
      t.integer :retry_count, default: 0

      t.timestamps
    end
  end
end
