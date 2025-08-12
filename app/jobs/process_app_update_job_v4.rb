# ProcessAppUpdateJobV4 - Uses the V4 orchestrator (Vite + TypeScript builds)
class ProcessAppUpdateJobV4 < ApplicationJob
  queue_as :ai_processing
  
  # Retry configuration - V4 has its own retry logic, so limit job-level retries
  retry_on StandardError, wait: :polynomially_longer, attempts: 2 do |job, error|
    # Log the final failure
    message = job.arguments.first
    Rails.logger.error "[ProcessAppUpdateJobV4] Final failure for message ##{message&.id}: #{error.message}"
    
    # Update app status if message and app exist
    if message && message.app
      message.app.update!(status: "failed")
      
      # Create error message for user
      message.app.app_chat_messages.create!(
        role: "assistant", 
        content: "I encountered an error with the V4 app builder: #{error.message}\n\nThe V4 system includes automatic retries, so this indicates a persistent issue. Please try again or contact support.",
        status: "failed"
      )
    end
  end
  
  def perform(message, use_enhanced: true)
    Rails.logger.info "[ProcessAppUpdateJobV4] Starting V4 orchestrator for message ##{message.id} (app ##{message.app.id})"
    
    # Use enhanced V4 with visual feedback by default
    use_v5 = true # Todd's human built new version based on Lovable leaked Agent prompts
    orchestrator = if use_v5
      Rails.logger.info "[ProcessAppUpdateJobV4] Using V5 builder"
      Ai::AppBuilderV5.new(message)
    elsif use_enhanced
      Rails.logger.info "[ProcessAppUpdateJobV4] Using ENHANCED V4 builder with real-time feedback"
      Ai::AppBuilderV4Enhanced.new(message)
    else
      Rails.logger.info "[ProcessAppUpdateJobV4] Using standard V4 builder"
      Ai::AppBuilderV4.new(message)
    end
    
    # V4 has built-in retry logic (MAX_RETRIES = 2)
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV4] Successfully processed message ##{message.id} with V4 orchestrator"
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV4] Error processing message ##{message.id}: #{e.message}"
    Rails.logger.error "[ProcessAppUpdateJobV4] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
    raise # Re-raise for job-level retry logic
  end
end