# ProcessAppUpdateJobV4 - Uses the V4 orchestrator (Vite + TypeScript builds)
class ProcessAppUpdateJobV4 < ApplicationJob
  queue_as :ai_processing
  
  # Retry configuration - V4 has its own retry logic, so limit job-level retries
  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    # Log the final failure
    message = job.arguments.first
    Rails.logger.error "[ProcessAppUpdateJobV4] Final failure for message ##{message.id}: #{error.message}"
    
    # Update app status
    message.app.update!(status: "failed", error_message: error.message)
    
    # Create error message for user
    message.app.app_chat_messages.create!(
      role: "assistant", 
      content: "I encountered an error with the V4 app builder: #{error.message}\n\nThe V4 system includes automatic retries, so this indicates a persistent issue. Please try again or contact support.",
      status: "failed"
    )
  end
  
  def perform(message)
    Rails.logger.info "[ProcessAppUpdateJobV4] Starting V4 orchestrator for message ##{message.id} (app ##{message.app.id})"
    
    # Use the new V4 orchestrator with template-based generation
    orchestrator = Ai::AppBuilderV4.new(message)
    
    # V4 has built-in retry logic (MAX_RETRIES = 2)
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV4] Successfully processed message ##{message.id} with V4 orchestrator"
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV4] Error processing message ##{message.id}: #{e.message}"
    Rails.logger.error "[ProcessAppUpdateJobV4] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    raise # Re-raise for job-level retry logic
  end
end