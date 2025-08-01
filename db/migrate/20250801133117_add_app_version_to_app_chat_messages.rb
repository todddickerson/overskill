class AddAppVersionToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_reference :app_chat_messages, :app_version, null: true, foreign_key: true
  end
end
