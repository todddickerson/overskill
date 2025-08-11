module Ai
  class AppBuilderV4
    MAX_RETRIES = 2
    
    def initialize(app_chat_message)
      @app = app_chat_message.app
      @message = app_chat_message
      @app_version = create_new_version
    end
    
    def execute!
      execute_with_retry
    end
    
    private
    
    def execute_with_retry
      # Intelligent error recovery via chat conversation
      attempt = 0
      
      begin
        attempt += 1
        Rails.logger.info "[V4] Generation attempt #{attempt}/#{MAX_RETRIES + 1} for app ##{@app.id}"
        
        execute_generation!
        
      rescue StandardError => e
        Rails.logger.error "[V4] Generation failed (attempt #{attempt}): #{e.message}"
        Rails.logger.error "[V4] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"
        
        if attempt <= MAX_RETRIES
          # Instead of blind retry, ask AI to fix the error via chat
          create_error_recovery_message(e, attempt)
          
          # Brief pause to allow message processing, then retry
          sleep(2)
          retry
        else
          mark_as_failed(e)
          raise e
        end
      end
    end
    
    def execute_generation!
      # V4 Enhanced Generation Pipeline
      Rails.logger.info "[V4] Starting enhanced generation pipeline for app ##{@app.id}"
      
      # Phase 1: Generate shared foundation (Day 2 ✅ IMPLEMENTED)
      generate_shared_foundation
      
      # Phase 1.5: 🚀 NEW - Generate AI context with available components
      component_context = generate_component_context
      Rails.logger.info "[V4] Generated component context (#{component_context.length} chars)"
      
      # Phase 2: AI app-specific features with component awareness (Day 2.5 implementation)
      # generate_app_features_with_components(component_context)
      
      # Phase 3: Smart component selection and integration (Day 2.5 implementation)
      # integrate_requested_components
      
      # Phase 4: Smart edits via existing services (Week 1 integration)
      # apply_smart_edits
      
      # Phase 5: Build and deploy (Day 3-5 implementation)
      # build_and_deploy
      
      # Update app status
      @app.update!(status: 'generated')
      
      Rails.logger.info "[V4] Enhanced generation pipeline completed for app ##{@app.id}"
    end
    
    def generate_component_context
      Rails.logger.info "[V4] Generating enhanced component context for AI"
      
      # Use the enhanced optional component service
      optional_service = if defined?(Ai::EnhancedOptionalComponentService)
        Ai::EnhancedOptionalComponentService.new(@app)
      else
        # Fallback to basic service
        Ai::OptionalComponentService.new(@app)
      end
      
      context = optional_service.respond_to?(:generate_ai_context_with_supabase) ? 
        optional_service.generate_ai_context_with_supabase : 
        optional_service.generate_ai_context
        
      # Store context for potential use in chat messages
      Rails.cache.write("app_#{@app.id}_component_context", context, expires_in: 1.hour)
      
      context
    end
    
    def generate_shared_foundation
      Rails.logger.info "[V4] Generating shared foundation files for app ##{@app.id}"
      
      # Use SharedTemplateService to create all foundation files
      template_service = Ai::SharedTemplateService.new(@app)
      template_service.generate_core_files
      
      # Track files created in this version
      track_template_files_created
      
      Rails.logger.info "[V4] Shared foundation generation completed"
    end
    
    def track_template_files_created
      # Get files created since this version started
      files_created = @app.app_files.where('created_at >= ?', @app_version.created_at)
      
      files_created.each do |app_file|
        @app_version.app_version_files.create!(
          app_file: app_file,
          action: 'created'
        )
      end
      
      Rails.logger.info "[V4] Tracked #{files_created.count} template files in version"
    end
    
    def create_new_version
      @app.app_versions.create!(
        version_number: next_version_number,
        changelog: "V4 orchestrator generation: #{@message.content.truncate(100)}"
      )
    end
    
    def next_version_number
      last_version = @app.app_versions.order(:created_at).last&.version_number || "0.0.0"
      version_parts = last_version.split('.').map(&:to_i)
      version_parts[2] += 1
      version_parts.join('.')
    end
    
    
    def create_error_recovery_message(error, attempt)
      # Create a system message on behalf of user asking AI to fix the error
      error_context = build_error_context(error, attempt)
      
      recovery_message = @app.app_chat_messages.create!(
        role: "user",
        content: error_context,
        user: @message.user,
        # Mark as bug fix for billing purposes (tokens should be ignored)
        metadata: {
          type: "error_recovery",
          attempt: attempt,
          original_error: error.class.name,
          billing_ignore: true
        }.to_json
      )
      
      Rails.logger.info "[V4] Created error recovery message ##{recovery_message.id} for attempt #{attempt}"
      
      # Update the current message reference to the recovery message
      @message = recovery_message
    end
    
    def build_error_context(error, attempt)
      context = []
      context << "I encountered an error during app generation (attempt #{attempt}/#{MAX_RETRIES + 1}):"
      context << ""
      context << "**Error:** #{error.message}"
      context << ""
      
      # Add relevant context based on error type
      case error
      when Ai::GenerationError, OpenAI::RequestError
        context << "This appears to be an AI generation issue. Please:"
        context << "1. Review the current app structure and identify the problem"
        context << "2. Fix any syntax errors or missing dependencies"
        context << "3. Continue with the generation process"
      when Net::TimeoutError, Timeout::Error
        context << "This was a timeout error. Please:"
        context << "1. Continue with the generation using smaller, focused changes"
        context << "2. Break down complex operations into simpler steps"
      when StandardError
        context << "This was a system error. Please:"
        context << "1. Analyze the error and current app state"
        context << "2. Make necessary corrections to continue generation"
        context << "3. Proceed with building the app"
      end
      
      context << ""
      context << "Please fix this issue and continue with the app generation."
      
      context.join("\n")
    end
    
    def mark_as_failed(error)
      @app.update!(
        status: 'failed',
        error_message: error.message
      )
      
      @app_version.update!(
        changelog: "V4 generation failed: #{error.message.truncate(200)}"
      )
      
      Rails.logger.error "[V4] App ##{@app.id} marked as failed after #{MAX_RETRIES} retries"
    end
  end
end