# ProcessAppUpdateJobV5 - Current active job for AI app updates
# This is the ONLY version in use - V3 and V4 have been removed
# Pipeline: User Message → This Job → AppBuilderV5 → File Creation
#
# DO NOT create V6 or resurrect old versions - this is the single source of truth
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
    
    # Track processing state in database (Rails best practice)
    app = message.app
    app.update!(
      status: 'processing',
      processing_started_at: Time.current
    )
    
    # Process directly with AppBuilderV5 - our single AI builder service
    begin
      service = Ai::AppBuilderV5.new(message)
      result = service.execute!
      
      # Update completion state
      app.update!(
        status: result ? 'generated' : 'failed',
        processing_completed_at: Time.current
      )
      
      result
    rescue => e
      Rails.logger.error "[ProcessAppUpdateJobV5] Error: #{e.message}"
      app.update!(
        status: 'failed',
        processing_completed_at: Time.current
      )
      raise
    end
  end
end