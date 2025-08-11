# ProcessAppUpdateJobV3 - Uses the V3 orchestrator (GPT-5 optimized)
class ProcessAppUpdateJobV3 < ApplicationJob
  queue_as :ai_processing
  
  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    # Log the final failure
    message = job.arguments.first
    Rails.logger.error "[ProcessAppUpdateJobV3] Final failure for message ##{message.id}: #{error.message}"
    
    # Update app status
    message.app.update!(status: "failed")
    
    # Create error message for user
    message.app.app_chat_messages.create!(
      role: "assistant",
      content: "I encountered an error processing your request: #{error.message}\n\nPlease try again or contact support if the issue persists.",
      status: "failed"
    )
  end
  
  def perform(message)
    Rails.logger.info "[ProcessAppUpdateJobV3] Starting V3 orchestrator for message ##{message.id}"
    
    # Use the unified orchestrator that supports both Claude and GPT-5
    # It will automatically select the best model based on app settings
    orchestrator = if defined?(Ai::AppUpdateOrchestratorV3Unified)
      Rails.logger.info "[ProcessAppUpdateJobV3] Using V3 Unified orchestrator"
      Ai::AppUpdateOrchestratorV3Unified.new(message)
    else
      Rails.logger.info "[ProcessAppUpdateJobV3] Falling back to V3 Optimized orchestrator"
      Ai::AppUpdateOrchestratorV3Optimized.new(message)
    end
    
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV3] Successfully processed message ##{message.id}"
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV3] Error processing message ##{message.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise for retry logic
  end
end