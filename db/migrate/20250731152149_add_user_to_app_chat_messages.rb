class AddUserToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :app_chat_messages, :user, null: true, foreign_key: true
  end
end
