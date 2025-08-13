class GenerateAppLogoJob < ApplicationJob
  queue_as :default

  def perform(app_id)
    app = App.find(app_id)
    
    # Skip if logo already exists and was generated recently
    if app.logo.attached? && app.logo_generated_at && app.logo_generated_at > 1.day.ago
      Rails.logger.info "[Logo] Skipping logo generation for app #{app.id} - already has recent logo"
      return
    end

    service = Ai::LogoGeneratorService.new(app)
    result = service.generate_logo

    if result[:success]
      app.update(logo_generated_at: Time.current)
      Rails.logger.info "[Logo] Successfully generated logo for app: #{app.name}"
      
      # Broadcast the updated navigation to refresh the logo
      broadcast_navigation_update(app)
    else
      Rails.logger.error "[Logo] Failed to generate logo for app #{app.id}: #{result[:error]}"
    end
  rescue => e
    Rails.logger.error "[Logo] Exception in GenerateAppLogoJob: #{e.message}"
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