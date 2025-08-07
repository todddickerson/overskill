class AppGenerationJob < ApplicationJob
  queue_as :ai_generation

  # Retry up to 3 times with exponential backoff
  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(app_generation)
    # Handle different input types
    if app_generation.is_a?(Integer)
      app_generation = AppGeneration.find(app_generation)
    elsif app_generation.is_a?(App)
      # If an App was passed by mistake, find its latest generation
      Rails.logger.warn "[AppGenerationJob] Received App instead of AppGeneration, finding latest generation"
      app_generation = app_generation.app_generations.order(created_at: :desc).first
      unless app_generation
        Rails.logger.error "[AppGenerationJob] No AppGeneration found for App ##{app_generation.id}"
        return
      end
    end
    
    Rails.logger.info "[AppGenerationJob] Processing generation ##{app_generation.id}"

    app = app_generation.app

    # Check if already processed
    if app_generation.completed?
      Rails.logger.info "[AppGenerationJob] Generation ##{app_generation.id} already completed"
      return
    end

    # Use the main AppGeneratorService which has all our enhancements
    # LovableStyleGenerator is deprecated - it wasn't using AI properly
    service = Ai::AppGeneratorService.new(app, app_generation)
    result = service.generate!

    if result[:success]
      Rails.logger.info "[AppGenerationJob] Successfully generated app ##{app.id}"
      
      # Automatically create database tables
      setup_database_tables(app)
      
      # Create auth settings if not present
      create_auth_settings(app)

      # Broadcast success via Turbo
      broadcast_status(app, "generated", "Your app has been generated successfully!")

      # Queue logo generation job
      GenerateAppLogoJob.perform_later(app.id)
      
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
  
  def create_auth_settings(app)
    return if app.app_auth_setting.present?
    
    # Determine if app needs authentication based on its type/prompt
    needs_auth = app_needs_authentication?(app)
    
    visibility = if needs_auth
      'public_login_required'  # Default: anyone can sign up but must login
    else
      'public_no_login'  # No auth needed
    end
    
    app.create_app_auth_setting!(
      visibility: visibility,
      allowed_providers: ['email', 'google', 'github'],
      allowed_email_domains: [],
      require_email_verification: false,  # NOTE: Supabase email verification is PROJECT-LEVEL, not app-level
      allow_signups: true,
      allow_anonymous: false
    )
    
    Rails.logger.info "[AppGenerationJob] Created auth settings for app ##{app.id} with visibility: #{visibility}"
  rescue => e
    Rails.logger.error "[AppGenerationJob] Failed to create auth settings: #{e.message}"
  end
  
  def app_needs_authentication?(app)
    # Check if app prompt mentions users, authentication, accounts, or personal data
    keywords = ['user', 'login', 'auth', 'account', 'personal', 'private', 'todo', 'note', 'diary', 'dashboard']
    prompt_text = "#{app.prompt} #{app.name}".downcase
    
    keywords.any? { |keyword| prompt_text.include?(keyword) }
  end
  
  def setup_database_tables(app)
    Rails.logger.info "[AppGenerationJob] Setting up database tables for app #{app.id}"
    
    begin
      # Use the automatic table creation service
      table_service = Supabase::AutoTableService.new(app)
      result = table_service.ensure_tables_exist!
      
      if result[:success]
        Rails.logger.info "[AppGenerationJob] Created tables: #{result[:tables].join(', ')}"
        
        # Broadcast table creation success
        ActionCable.server.broadcast(
          "app_#{app.id}_generation",
          {
            type: 'database_ready',
            tables: result[:tables],
            message: 'Database tables created automatically'
          }
        )
      else
        Rails.logger.error "[AppGenerationJob] Failed to create tables: #{result[:error]}"
      end
    rescue => e
      Rails.logger.error "[AppGenerationJob] Table creation error: #{e.message}"
      # Don't fail the whole job if table creation fails
      # Tables will be auto-created on first use anyway
    end
  end

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
    
    # If generation is complete, redirect to editor
    if status == "generated"
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_generation",
        target: "body",
        html: "<script>window.location.href = '/account/apps/#{app.to_param}/editor';</script>"
      )
    end
  end
end
