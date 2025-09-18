class AddConstraintsToAppChatMessages < ActiveRecord::Migration[8.0]
  def change
    # Add index for faster queries on status
    add_index :app_chat_messages, :status

    # Add index for faster queries on created_at (for finding stuck messages)
    add_index :app_chat_messages, :created_at

    # Add composite index for app_id and created_at for efficient chat loading
    add_index :app_chat_messages, [:app_id, :created_at]

    # Clean up any invalid data before adding constraint
    # Set status to NULL for non-assistant messages (user messages shouldn't have status)
    reversible do |dir|
      dir.up do
        # First, clean up existing data
        execute <<-SQL
          UPDATE app_chat_messages 
          SET status = NULL 
          WHERE role != 'assistant' AND status IS NOT NULL;
        SQL

        # Then add the constraint
        execute <<-SQL
          ALTER TABLE app_chat_messages
          ADD CONSTRAINT check_status_only_for_assistant
          CHECK (
            (role = 'assistant' AND status IN ('planning', 'executing', 'generating', 'completed', 'failed', 'validation_error'))
            OR
            (role != 'assistant' AND status IS NULL)
          );
        SQL
      end

      dir.down do
        execute <<-SQL
          ALTER TABLE app_chat_messages
          DROP CONSTRAINT IF EXISTS check_status_only_for_assistant;
        SQL
      end
    end
  end
end
