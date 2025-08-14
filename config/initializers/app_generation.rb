# App Generation Configuration
# This file configures which orchestrator version to use for app generation
# Can be overridden with environment variables

Rails.application.configure do
  # Set the default orchestrator version from ENV or default to v5
  # Options: :v3, :v4, :v4_enhanced, :v5
  version = ENV.fetch('APP_GENERATION_VERSION', 'v5')
  config.app_generation_version = version.to_sym
  
  # Feature flags for specific enhancements
  config.app_generation_features = {
    # Enable real-time visual feedback in chat
    visual_feedback: ENV.fetch('APP_GENERATION_VISUAL_FEEDBACK', 'true') == 'true',
    
    # Enable interactive approval flow for changes
    approval_flow: ENV.fetch('APP_GENERATION_APPROVAL_FLOW', 'true') == 'true',
    
    # Enable streaming build output
    streaming_output: ENV.fetch('APP_GENERATION_STREAMING_OUTPUT', 'true') == 'true',
    
    # Enable smart dependency management
    smart_dependencies: ENV.fetch('APP_GENERATION_SMART_DEPENDENCIES', 'true') == 'true',
    
    # Enable user-friendly error messages
    friendly_errors: ENV.fetch('APP_GENERATION_FRIENDLY_ERRORS', 'true') == 'true'
  }
  
  # Fallback configuration
  # If V4 fails, should we fallback to V3?
  config.app_generation_fallback = ENV.fetch('APP_GENERATION_FALLBACK', 'false') == 'true'
  
  # Debug mode - adds extra logging
  config.app_generation_debug = ENV.fetch('APP_GENERATION_DEBUG', Rails.env.development?.to_s) == 'true'
  
  # Log the configuration on startup
  if config.app_generation_debug
    Rails.logger.info "=" * 60
    Rails.logger.info "App Generation Configuration:"
    Rails.logger.info "  Version: #{config.app_generation_version}"
    Rails.logger.info "  Features:"
    config.app_generation_features.each do |feature, enabled|
      Rails.logger.info "    #{feature}: #{enabled}"
    end
    Rails.logger.info "  Fallback to V3: #{config.app_generation_fallback}"
    Rails.logger.info "  Debug mode: #{config.app_generation_debug}"
    Rails.logger.info "=" * 60
  end
end