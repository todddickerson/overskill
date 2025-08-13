class AddConversationFlowToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :app_chat_messages, :conversation_flow, :jsonb, default: []
    add_index :app_chat_messages, :conversation_flow, using: :gin
  end
end
