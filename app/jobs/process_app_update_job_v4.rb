# ProcessAppUpdateJobV4 - Named V4 but actually uses V5 orchestrator (Vite + TypeScript builds)
# TODO: Rename to ProcessAppUpdateJobV5 when convenient
class ProcessAppUpdateJobV4 < ApplicationJob
  include ActiveJob::Uniqueness
  
  queue_as :ai_processing
  
  # Prevent duplicate AI processing for the same message
  # Lock until the job completes to avoid concurrent AI generation
  unique :until_executed, lock_ttl: 30.minutes, on_conflict: :log
  
  # Define uniqueness based on message ID
  def lock_key
    message_or_id = arguments.first
    
    # Handle GlobalID objects from ActiveJob serialization
    if message_or_id.respond_to?(:model_id)
      return "process_app_update_v4:message:#{message_or_id.model_id}"
    end
    
    case message_or_id
    when AppChatMessage
      "process_app_update_v4:message:#{message_or_id.id}"
    when Integer, String
      "process_app_update_v4:message:#{message_or_id}"
    else
      # Try to extract ID from GlobalID string representation
      if message_or_id.to_s.include?('AppChatMessage/')
        id = message_or_id.to_s.split('AppChatMessage/').last.split('>').first
        "process_app_update_v4:message:#{id}"
      else
        "process_app_update_v4:unknown:#{message_or_id.to_s}"
      end
    end
  end
  
  # Retry configuration - V4 has its own retry logic, so limit job-level retries
  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    # Log the final failure
    message_or_id = job.arguments.first
    
    # Handle both message object and ID
    message = begin
      case message_or_id
      when AppChatMessage
        message_or_id
      when Integer, String
        AppChatMessage.find_by(id: message_or_id)
      else
        nil
      end
    rescue
      nil
    end
    
    Rails.logger.error "[ProcessAppUpdateJobV4] Final failure for message ##{message&.id || message_or_id}: #{error.message}"
    
    # Update app status if message and app exist
    if message && message.app
      message.app.update!(status: "failed")
      
      # Create error message for user (note: this job actually uses V5 builder internally)
      message.app.app_chat_messages.create!(
        role: "assistant", 
        content: "I encountered an error with the app builder: #{error.message}\n\nThe system includes automatic retries, so this indicates a persistent issue. Please try again or contact support.",
        status: "failed"
      )
    end
  end
  
  def perform(message_or_id, use_enhanced: true)
    # Handle both message object and ID (for robustness with ActiveJob serialization)
    message = case message_or_id
    when AppChatMessage
      message_or_id
    when Integer, String
      AppChatMessage.find(message_or_id)
    else
      raise ArgumentError, "Expected AppChatMessage or ID, got #{message_or_id.class}"
    end
    
    Rails.logger.info "[ProcessAppUpdateJobV4] Starting V5 orchestrator for message ##{message.id} (app ##{message.app.id})"
    
    # Use V5 orchestrator (job is named V4 for historical reasons)
    orchestrator = Ai::AppBuilderV5.new(message)
    
    # V5 has built-in retry logic
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV4] Successfully processed message ##{message.id} with V5 orchestrator"
    
    # Queue deployment job after successful generation
    # This ensures app version is created and files are ready
    app = message.app
    if app && app.app_files.any?
      Rails.logger.info "[ProcessAppUpdateJobV4] Queueing deployment for app ##{app.id}"
      DeployAppJob.perform_later(app.id, "preview")
    else
      Rails.logger.warn "[ProcessAppUpdateJobV4] Skipping deployment - no files generated"
    end
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "[ProcessAppUpdateJobV4] Message not found: #{e.message}"
    raise # Let job retry logic handle it
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV4] Error processing message ##{message&.id}: #{e.message}"
    Rails.logger.error "[ProcessAppUpdateJobV4] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    raise # Re-raise for job-level retry logic
  end
end