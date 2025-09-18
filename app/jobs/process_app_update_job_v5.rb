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
      status: "processing",
      processing_started_at: Time.current
    )

    # Process directly with AppBuilderV5 - our single AI builder service
    begin
      service = Ai::AppBuilderV5.new(message)
      result = service.execute!

      # ULTRATHINK FIX: Don't overwrite status if it's already ready_to_deploy
      # AppBuilderV5 sets status to 'ready_to_deploy' when triggering deployment
      # We should only update if it's still in 'processing' state
      app.reload # Get latest status from database

      Rails.logger.info "[ProcessAppUpdateJobV5] After execute, app status: #{app.status}"

      if app.status == "processing"
        # Only update if still processing (means something went wrong)
        app.update!(
          status: result ? "generated" : "failed",
          processing_completed_at: Time.current
        )
        Rails.logger.info "[ProcessAppUpdateJobV5] Updated status to: #{app.status}"
      else
        # Just update the processing timestamp
        app.update!(processing_completed_at: Time.current)
        Rails.logger.info "[ProcessAppUpdateJobV5] Kept status as: #{app.status}"
      end

      result
    rescue => e
      Rails.logger.error "[ProcessAppUpdateJobV5] Error: #{e.message}"
      app.update!(
        status: "failed",
        processing_completed_at: Time.current
      )
      raise
    end
  end
end
