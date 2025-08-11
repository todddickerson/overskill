class AppNamingJob < ApplicationJob
  queue_as :ai_naming
  
  # Retry up to 2 times for naming failures
  retry_on StandardError, wait: :polynomially_longer, attempts: 2
  
  def perform(app_id)
    app = App.find_by(id: app_id)
    unless app
      Rails.logger.error "[AppNamingJob] App ##{app_id} not found"
      return
    end
    
    Rails.logger.info "[AppNamingJob] Starting AI naming for app ##{app.id}"
    
    # Skip if app already has a good name (not generated)
    if app.name.present? && !generic_name?(app.name)
      Rails.logger.info "[AppNamingJob] App ##{app.id} already has a good name: '#{app.name}'"
      return
    end
    
    # Use the AI naming service
    namer = Ai::AppNamerService.new(app)
    result = namer.generate_name!
    
    if result[:success]
      Rails.logger.info "[AppNamingJob] Successfully named app ##{app.id}: #{result[:new_name]}"
      
      # Broadcast success notification
      broadcast_naming_success(app, result)
    else
      Rails.logger.error "[AppNamingJob] Failed to name app ##{app.id}: #{result[:error]}"
      
      # Don't fail the job for naming errors - it's not critical
      # Just log and continue
    end
  rescue => e
    Rails.logger.error "[AppNamingJob] Unexpected error naming app ##{app_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    
    # Don't re-raise - naming is nice to have but not critical
  end
  
  private
  
  def generic_name?(name)
    # Check if the name looks auto-generated or generic
    return true if name.blank?
    return true if name.match?(/^My App \d+$/i)
    return true if name.match?(/^App \d+$/i) 
    return true if name.match?(/^Untitled/i)
    return true if name.match?(/^New App/i)
    return true if name.match?(/^app-[a-f0-9]+$/i)  # slug-like names
    
    false
  end
  
  def broadcast_naming_success(app, result)
    # Send notification to user about the naming
    ActionCable.server.broadcast(
      "app_#{app.id}_chat",
      {
        action: "app_named",
        old_name: result[:old_name],
        new_name: result[:new_name],
        message: "🎉 AI named your app '#{result[:new_name]}'"
      }
    )
    
    # Also create a system chat message
    app.app_chat_messages.create!(
      role: 'system',
      content: "AI automatically named your app **#{result[:new_name]}** based on your description.",
      message_type: 'system_notification'
    )
  rescue => e
    Rails.logger.error "[AppNamingJob] Failed to broadcast naming success: #{e.message}"
  end
end