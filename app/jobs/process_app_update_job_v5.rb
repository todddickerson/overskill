# ProcessAppUpdateJobV5 - Uses the V5 orchestrator with simple flow
class ProcessAppUpdateJobV5 < ApplicationJob
  queue_as :ai_processing
  
  # Retry configuration - V5 has its own retry logic, so limit job-level retries
  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    # Log the final failure
    message = job.arguments.first
    Rails.logger.error "[ProcessAppUpdateJobV5] Final failure for message ##{message&.id}: #{error.message}"
    
    # Update app status if message and app exist
    if message && message.app
      message.app.update!(status: "failed")
      
      # Create error message for user
      message.app.app_chat_messages.create!(
        role: "assistant", 
        content: "I encountered an error with the V5 app builder: #{error.message}\n\nThe V5 system uses a simplified flow. Please try again or contact support if the issue persists.",
        status: "failed"
      )
    end
  end
  
  def perform(message)
    Rails.logger.info "[ProcessAppUpdateJobV5] Starting V5 orchestrator for message ##{message.id} (app ##{message.app.id})"
    
    # Use V5 builder with simple flow
    orchestrator = Ai::AppBuilderV5.new(message)
    
    # V5 uses simple flow without complex decision engine
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV5] Successfully processed message ##{message.id} with V5 orchestrator"
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV5] Error processing message ##{message.id}: #{e.message}"
    Rails.logger.error "[ProcessAppUpdateJobV5] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    raise # Re-raise for job-level retry logic
  end
end