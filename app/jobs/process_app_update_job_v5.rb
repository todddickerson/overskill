# ProcessAppUpdateJobV5 - Wrapper for V4 to avoid confusion
# This simply delegates to ProcessAppUpdateJobV4 which uses app_builder_v5
class ProcessAppUpdateJobV5 < ApplicationJob
  queue_as :ai_processing

  def perform(message_or_id)
    # Handle both message objects and message IDs, just like V4
    message_id = case message_or_id
    when AppChatMessage
      message_or_id.id
    when Integer, String
      message_or_id.to_s
    else
      # Handle GlobalID or other cases
      message_or_id
    end
    
    Rails.logger.info "[ProcessAppUpdateJobV5] Delegating to V4 for message ##{message_id}"
    
    # Simply pass through to V4 which uses app_builder_v5
    # Use perform_later to maintain async behavior
    ProcessAppUpdateJobV4.perform_later(message_or_id)
  end
end