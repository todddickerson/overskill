# UnifiedAiProcessingJob - Single entry point for all AI message processing
# Replaces multiple legacy jobs with one consistent flow
class UnifiedAiProcessingJob < ApplicationJob
  queue_as :ai_processing
  
  # Retry configuration
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    # Log the final failure
    message = job.arguments.first
    Rails.logger.error "[UnifiedAI] Final failure for message ##{message.id}: #{error.message}"
    
    # Create error message for user
    message.app.app_chat_messages.create!(
      role: "assistant",
      content: "I encountered an error processing your request. Please try again or contact support if the issue persists.",
      status: "failed"
    )
  end
  
  def perform(message)
    Rails.logger.info "[UnifiedAI] Processing message ##{message.id}"
    
    # Use the unified coordinator for all AI operations
    coordinator = Ai::UnifiedAiCoordinator.new(message.app, message)
    coordinator.execute!
    
    Rails.logger.info "[UnifiedAI] Successfully processed message ##{message.id}"
  rescue => e
    Rails.logger.error "[UnifiedAI] Error processing message ##{message.id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise # Re-raise for retry logic
  end
end