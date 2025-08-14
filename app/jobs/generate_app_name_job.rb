# Job to generate meaningful app names based on user prompts
# Uses AI to analyze the app's prompt and generate a descriptive, brandable name
# Integrates with AppNamerService for the actual AI generation
class GenerateAppNameJob < ApplicationJob
  queue_as :default

  def perform(app_id)
    app = App.find(app_id)
    
    # Skip if app already has a good name (not default/generic)
    if app.name_generated_at.present?
      Rails.logger.info "[AppName] Skipping name generation for app #{app.id} - already generated name: '#{app.name}'"
      return
    end

    service = Ai::AppNamerService.new(app)
    result = service.generate_name!

    if result[:success]
      app.update(name_generated_at: Time.current)
      Rails.logger.info "[AppName] Successfully generated name for app: #{result[:new_name]}"
      
      # Broadcast the updated navigation to refresh the app name
      broadcast_navigation_update(app)
    else
      Rails.logger.error "[AppName] Failed to generate name for app #{app.id}: #{result[:error]}"
    end
  rescue ActiveRecord::RecordNotFound => e
    # If app was deleted, log and exit gracefully (don't retry)
    Rails.logger.info "[AppName] App #{app_id} not found - likely deleted. Skipping name generation."
    return
  rescue => e
    Rails.logger.error "[AppName] Exception in GenerateAppNameJob: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  private

  def broadcast_navigation_update(app)
    # Broadcast to all users who might be viewing this app's editor
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}",
      target: "app_navigation_#{app.id}",
      partial: "account/app_editors/app_navigation",
      locals: { app: app }
    )
  end
end
