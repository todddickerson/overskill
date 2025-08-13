class AddV5FieldsToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :app_chat_messages, :thinking_status, :string
    add_column :app_chat_messages, :thought_for_seconds, :integer
    add_column :app_chat_messages, :loop_messages, :jsonb, default: []
    add_column :app_chat_messages, :tool_calls, :jsonb, default: []
    add_column :app_chat_messages, :iteration_count, :integer, default: 0
    add_column :app_chat_messages, :is_code_generation, :boolean, default: false
    
    # Add GIN indexes for JSONB columns for better query performance
    add_index :app_chat_messages, :loop_messages, using: :gin
    add_index :app_chat_messages, :tool_calls, using: :gin
  end
end
