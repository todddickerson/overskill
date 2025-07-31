class AppGenerationJob < ApplicationJob
  queue_as :ai_generation

  # Retry up to 3 times with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(app_generation)
    Rails.logger.info "[AppGenerationJob] Processing generation ##{app_generation.id}"

    app = app_generation.app

    # Check if already processed
    if app_generation.completed?
      Rails.logger.info "[AppGenerationJob] Generation ##{app_generation.id} already completed"
      return
    end

    # Run the generation
    service = AI::AppGeneratorService.new(app, app_generation)
    result = service.generate!

    if result[:success]
      Rails.logger.info "[AppGenerationJob] Successfully generated app ##{app.id}"

      # Broadcast success via Turbo
      broadcast_status(app, "generated", "Your app has been generated successfully!")

      # Queue deployment job if enabled
      if ENV["AUTO_DEPLOY_AFTER_GENERATION"] == "true"
        AppDeploymentJob.perform_later(app)
      end
    else
      Rails.logger.error "[AppGenerationJob] Failed to generate app ##{app.id}: #{result[:error]}"

      # Broadcast failure
      broadcast_status(app, "failed", "Generation failed. Please try again.")
    end
  rescue => e
    Rails.logger.error "[AppGenerationJob] Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Update status to failed
    app_generation.update!(status: "failed", error_message: e.message)
    app_generation.app.update!(status: "failed")

    # Broadcast error
    broadcast_status(app_generation.app, "failed", "An unexpected error occurred.")

    raise # Re-raise to trigger retry logic
  end

  private

  def broadcast_status(app, status, message)
    # Broadcast to the app's channel
    Turbo::StreamsChannel.broadcast_update_to(
      "app_#{app.id}_generation",
      target: "app_generation_status",
      partial: "account/apps/generation_status",
      locals: {app: app, status: status, message: message}
    )

    # Also update the specific turbo frame
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{app.id}_generation",
      target: "app_#{app.id}_status",
      partial: "account/apps/status_badge",
      locals: {app: app}
    )
  end
end
