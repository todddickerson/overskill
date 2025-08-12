# Action Cable channel for real-time chat progress updates
class ChatProgressChannel < ApplicationCable::Channel
  def subscribed
    message = AppChatMessage.find(params[:message_id])
    
    # Ensure user has access to this message
    # Check if user owns the app
    if message.app.team.users.include?(current_user)
      stream_from "chat_progress_#{message.id}"
      stream_for message
    else
      reject
    end
  end
  
  def unsubscribed
    # Cleanup when channel is unsubscribed
    stop_all_streams
  end
  
  # Handle approval responses from client
  def approve_changes(data)
    message = AppChatMessage.find(params[:message_id])
    
    if message.app.team.users.include?(current_user)
      # Notify the builder about the approval
      ApprovalService.handle_approval(
        message_id: message.id,
        callback_id: data['callback_id'],
        approved_files: data['approved_files']
      )
    end
  end
  
  # Handle rejection of changes
  def reject_changes(data)
    message = AppChatMessage.find(params[:message_id])
    
    if message.app.team.users.include?(current_user)
      ApprovalService.handle_rejection(
        message_id: message.id,
        callback_id: data['callback_id']
      )
    end
  end
  
  # Handle pause request
  def pause_generation(data)
    message = AppChatMessage.find(params[:message_id])
    
    if message.app.team.users.include?(current_user)
      GenerationControlService.pause(message.id)
    end
  end
  
  # Handle resume request
  def resume_generation(data)
    message = AppChatMessage.find(params[:message_id])
    
    if message.app.team.users.include?(current_user)
      GenerationControlService.resume(message.id)
    end
  end
end