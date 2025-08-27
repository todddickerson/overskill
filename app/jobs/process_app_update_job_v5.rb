# ProcessAppUpdateJobV5 - Wrapper for V4 to avoid confusion
# This simply delegates to ProcessAppUpdateJobV4 which uses app_builder_v5
class ProcessAppUpdateJobV5 < ApplicationJob
  queue_as :ai_processing

  def perform(message_or_id)
    # Resolve message to ensure it exists before processing
    message = case message_or_id
    when AppChatMessage
      message_or_id
    when Integer, String
      AppChatMessage.find(message_or_id)
    else
      # Handle GlobalID cases
      AppChatMessage.find(message_or_id)
    end
    
    Rails.logger.info "[ProcessAppUpdateJobV5] Processing message ##{message.id} directly with AppBuilderV5"
    
    # Process directly with AppBuilderV5 instead of delegating to avoid race conditions
    service = Ai::AppBuilderV5.new(message)
    service.execute!
  end
end