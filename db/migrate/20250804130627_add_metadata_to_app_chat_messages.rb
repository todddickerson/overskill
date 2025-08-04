class AddMetadataToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :app_chat_messages, :metadata, :jsonb, default: {}
    add_index :app_chat_messages, :metadata, using: :gin
  end
end
