class CreateAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :app_chat_messages do |t|
      t.references :app, null: false, foreign_key: true
      t.text :content
      t.string :role
      t.text :response
      t.string :status

      t.timestamps
    end
  end
end
