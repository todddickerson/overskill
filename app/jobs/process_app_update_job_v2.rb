# New version that uses the orchestrator for better user feedback
class ProcessAppUpdateJobV2 < ApplicationJob
  queue_as :ai_generation
  
  # Set a 10 minute timeout for the entire job
  around_perform do |job, block|
    Timeout.timeout(600) do
      block.call
    end
  rescue Timeout::Error
    Rails.logger.error "[ProcessAppUpdateJobV2] Job timed out after 10 minutes"
    chat_message = job.arguments.first
    handle_timeout_error(chat_message)
  end
  
  def perform(chat_message)
    Rails.logger.info "[ProcessAppUpdateJobV2] Starting orchestrated update for message ##{chat_message.id}"
    
    # Use the new orchestrator for better user feedback
    orchestrator = Ai::AppUpdateOrchestrator.new(chat_message)
    orchestrator.execute!
    
    Rails.logger.info "[ProcessAppUpdateJobV2] Orchestrated update completed"
  rescue => e
    Rails.logger.error "[ProcessAppUpdateJobV2] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    handle_error(chat_message, e.message)
  end
  
  private
  
  def handle_timeout_error(chat_message)
    error_response = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: "⏱️ This request took too long to process (over 10 minutes) and was automatically cancelled.\n\nPlease try breaking your request into smaller, more specific changes.",
      status: "failed"
    )
    
    broadcast_error(chat_message, error_response)
  end
  
  def handle_error(chat_message, error_message)
    error_response = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: "❌ I encountered an error: #{error_message}\n\nPlease try rephrasing your request or contact support if the issue persists.",
      status: "failed"
    )
    
    broadcast_error(chat_message, error_response)
  end
  
  def broadcast_error(user_message, error_message)
    # Broadcast the error message
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{user_message.app_id}_chat",
      target: "chat_messages",
      partial: "account/app_editors/chat_message",
      locals: {message: error_message}
    )
    
    # Re-enable the chat form
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{user_message.app_id}_chat",
      target: "chat_form",
      partial: "account/app_editors/chat_input_wrapper",
      locals: {app: user_message.app}
    )
  end
end