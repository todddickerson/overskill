class CleanupStuckMessagesJob < ApplicationJob
  queue_as :maintenance
  
  def perform
    Rails.logger.info "[CleanupStuckMessages] Starting cleanup of stuck messages"
    
    stuck_count = 0
    orphaned_count = 0
    
    # Find messages stuck in processing states for more than 15 minutes
    stuck_messages = AppChatMessage.where(
      status: ['planning', 'executing', 'generating']
    ).where('created_at < ?', 15.minutes.ago)
    
    stuck_messages.each do |message|
      Rails.logger.info "[CleanupStuckMessages] Found stuck message #{message.id} in #{message.status} state for #{((Time.current - message.created_at) / 60).round} minutes"
      
      message.update!(
        status: 'failed',
        content: message.content.presence || "This request timed out. Please try again with a simpler request.",
        response: "Automatically failed due to timeout"
      )
      
      # Create a failure notification message if this was an assistant message
      if message.role == 'assistant'
        message.app.app_chat_messages.create!(
          role: "assistant",
          content: "This request took too long to process and was automatically cancelled. Please try again with a simpler request.",
          status: "failed"
        )
      end
      
      stuck_count += 1
    end
    
    # Find user messages without responses older than 15 minutes
    apps_with_messages = App.joins(:app_chat_messages)
                            .where(app_chat_messages: { role: 'user', created_at: 15.minutes.ago.. })
                            .distinct
    
    apps_with_messages.each do |app|
      recent_user_messages = app.app_chat_messages
                               .where(role: 'user')
                               .where('created_at > ?', 1.hour.ago)
                               .order(created_at: :desc)
      
      recent_user_messages.each do |user_message|
        # Check if there's an assistant response after this message
        next_assistant_message = app.app_chat_messages
                                    .where(role: 'assistant')
                                    .where('created_at > ?', user_message.created_at)
                                    .order(created_at: :asc)
                                    .first
        
        if !next_assistant_message && user_message.created_at < 15.minutes.ago
          Rails.logger.info "[CleanupStuckMessages] Found orphaned user message #{user_message.id} from #{((Time.current - user_message.created_at) / 60).round} minutes ago"
          
          # Create a failure response
          app.app_chat_messages.create!(
            role: "assistant",
            content: "This request timed out. The system was unable to process your request. Please try again.",
            status: "failed"
          )
          
          orphaned_count += 1
        end
      end
    end
    
    Rails.logger.info "[CleanupStuckMessages] Cleanup complete: #{stuck_count} stuck messages fixed, #{orphaned_count} orphaned messages handled"
  end
end