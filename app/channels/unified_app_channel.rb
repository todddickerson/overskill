class UnifiedAppChannel < ApplicationCable::Channel
  def subscribed
    app_id = params[:app_id]
    
    # Verify user has access to this app via any team
    app = current_user.teams.joins(:apps).find_by(apps: { id: app_id })
    
    if app
      # Subscribe to multiple app-scoped streams in one channel
      stream_from "app_#{app_id}_chat"           # Chat messages & AI responses
      stream_from "app_#{app_id}_deployment"     # Deployment status & progress  
      stream_from "app_#{app_id}_build_status"   # Build timing & GitHub Actions
      stream_from "app_#{app_id}_progress"       # Generation progress & file updates
      
      Rails.logger.info "[UnifiedAppChannel] Subscribed to all streams for app #{app_id}"
    else
      reject
      Rails.logger.warn "[UnifiedAppChannel] Rejected subscription for app #{app_id} (user #{current_user&.id})"
    end
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def unsubscribed
    Rails.logger.info "[UnifiedAppChannel] Unsubscribed from unified app channel"
    stop_all_streams
  end

  # Handle approval responses from client
  def approve_changes(data)
    app_id = params[:app_id]
    app = current_user.teams.joins(:apps).find_by(apps: { id: app_id })
    
    return unless app
    
    ApprovalService.handle_approval(
      message_id: data['message_id'],
      callback_id: data['callback_id'],
      approved_files: data['approved_files']
    )
  end
  
  # Handle rejection of changes
  def reject_changes(data)
    app_id = params[:app_id]
    app = current_user.teams.joins(:apps).find_by(apps: { id: app_id })
    
    return unless app
    
    ApprovalService.handle_rejection(
      message_id: data['message_id'],
      callback_id: data['callback_id']
    )
  end
  
  # Handle pause/resume generation
  def pause_generation(data)
    app_id = params[:app_id]
    app = current_user.teams.joins(:apps).find_by(apps: { id: app_id })
    
    return unless app
    
    GenerationControlService.pause(data['message_id'])
  end
  
  def resume_generation(data)
    app_id = params[:app_id]
    app = current_user.teams.joins(:apps).find_by(apps: { id: app_id })
    
    return unless app
    
    GenerationControlService.resume(data['message_id'])
  end
end