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
      
      # Phase 2: AI app-specific features with component awareness
      generate_app_features_with_components(component_context)
      
      # Phase 3: Smart component selection and integration
      integrate_requested_components
      
      # Phase 4: Smart edits via existing services
      apply_smart_edits
      
      # Phase 5: Build and deploy (Day 3-4 ✅ IMPLEMENTED)
      build_result = build_for_deployment
      
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

    def build_for_deployment
      Rails.logger.info "[V4] Building app ##{@app.id} for deployment"
      
      builder = Deployment::ViteBuilderService.new(@app)
      
      # Determine build mode based on user intent
      build_mode = builder.determine_build_mode(@message.content)
      
      build_result = case build_mode
                    when :production
                      Rails.logger.info "[V4] Using production build (3min optimized)"
                      builder.build_for_production!
                    else
                      Rails.logger.info "[V4] Using development build (45s fast)"
                      builder.build_for_development!
                    end

      # Deploy to Cloudflare if build successful
      if build_result[:success]
        deployment_result = deploy_to_cloudflare(build_result)
        build_result.merge!(deployment: deployment_result)
      end
      
      Rails.logger.info "[V4] Build and deployment completed in #{build_result[:build_time]}s"
      build_result
    rescue => e
      Rails.logger.error "[V4] Build/deployment failed: #{e.message}"
      # Don't fail the entire generation for build issues
      # Apps can still be manually built later
      { success: false, error: e.message, build_skipped: true }
    end

    def deploy_to_cloudflare(build_result)
      Rails.logger.info "[V4] Deploying to Cloudflare for app ##{@app.id}"
      
      client = Deployment::CloudflareApiClient.new(@app)
      deployment_result = client.deploy_complete_application(build_result)
      
      if deployment_result[:success]
        Rails.logger.info "[V4] Cloudflare deployment successful"
        # Update app URLs from deployment
        update_app_urls_from_deployment(deployment_result[:deployment_urls])
      else
        Rails.logger.warn "[V4] Cloudflare deployment failed: #{deployment_result[:error]}"
      end
      
      deployment_result
    rescue => e
      Rails.logger.error "[V4] Cloudflare deployment error: #{e.message}"
      { success: false, error: e.message }
    end

    def update_app_urls_from_deployment(deployment_urls)
      updates = {}
      
      if deployment_urls[:preview_url]
        updates[:preview_url] = deployment_urls[:preview_url]
      end
      
      if deployment_urls[:production_url]
        updates[:production_url] = deployment_urls[:production_url]
      end
      
      @app.update!(updates) if updates.any?
    end

    
    def generate_app_features_with_components(component_context)
      Rails.logger.info "[V4] Generating app-specific features with AI"
      
      # Build comprehensive prompt with component awareness
      prompt = build_generation_prompt(component_context)
      
      # Use Claude conversation loop for multi-file generation
      generate_with_claude_conversation(prompt)
      
      Rails.logger.info "[V4] App-specific features generated"
    end
    
    def integrate_requested_components
      Rails.logger.info "[V4] Integrating requested components"
      
      # Analyze generated files to identify needed components
      components_needed = analyze_component_requirements
      
      # Copy optional component templates as needed
      components_needed.each do |component|
        integrate_component(component)
      end
      
      Rails.logger.info "[V4] Integrated #{components_needed.size} components"
    end
    
    def apply_smart_edits
      Rails.logger.info "[V4] Applying smart edits via LineReplaceService"
      
      # Use SmartSearchService to find files that need updates
      search_service = Ai::SmartSearchService.new(@app)
      
      # Find files with TODO comments or placeholders
      todo_results = search_service.search_files(
        query: 'TODO|FIXME|{{.*}}',
        include_pattern: '*.tsx',
        context_lines: 3
      )
      
      # Apply surgical edits to complete TODOs
      if todo_results[:success] && todo_results[:results].any?
        todo_results[:results].each do |result|
          apply_todo_completion(result)
        end
      end
      
      Rails.logger.info "[V4] Smart edits completed"
    end
    
    def build_generation_prompt(component_context)
      prompt = []
      prompt << "You are building a #{@app.name} application."
      prompt << ""
      prompt << "User Request: #{@message.content}"
      prompt << ""
      prompt << "The shared foundation files have already been created (auth, routing, database)."
      prompt << "Now generate the app-specific features and pages."
      prompt << ""
      prompt << component_context
      prompt << ""
      prompt << "Guidelines:"
      prompt << "- Use TypeScript and React with Vite"
      prompt << "- Follow the existing project structure (src/pages/, src/components/)"
      prompt << "- Use the app-scoped database wrapper for all Supabase queries"
      prompt << "- Import and use shadcn/ui components where appropriate"
      prompt << "- Create professional, production-ready code"
      prompt.join("\n")
    end
    
    def generate_with_claude_conversation(prompt)
      Rails.logger.info "[V4] Starting Claude conversation loop for multi-file generation"
      
      # Determine files needed based on app type
      files_needed = plan_files_needed
      
      # Claude can only create 1-2 files per API call
      files_created = []
      
      files_needed.each_slice(2) do |batch|
        Rails.logger.info "[V4] Generating batch: #{batch.join(', ')}"
        
        batch_prompt = build_batch_prompt(prompt, batch, files_created)
        response = generate_files_with_claude(batch_prompt, batch)
        
        if response[:success]
          files_created.concat(response[:files])
          broadcast_progress(files_created)
        else
          Rails.logger.error "[V4] Failed to generate batch: #{response[:error]}"
          break
        end
      end
      
      Rails.logger.info "[V4] Claude conversation completed. Generated #{files_created.size} files"
    end
    
    def plan_files_needed
      # Analyze the user's request to determine what files to generate
      content = @message.content.downcase
      files = []
      
      # Core app page
      files << 'src/pages/Dashboard.tsx'
      
      # Based on keywords in request
      if content.include?('todo') || content.include?('task')
        files << 'src/components/TodoList.tsx'
        files << 'src/components/TodoItem.tsx'
        files << 'src/hooks/useTodos.ts'
      end
      
      if content.include?('chat') || content.include?('message')
        files << 'src/components/ChatInterface.tsx'
        files << 'src/components/MessageList.tsx'
        files << 'src/hooks/useChat.ts'
      end
      
      if content.include?('form') || content.include?('input')
        files << 'src/components/FormBuilder.tsx'
        files << 'src/components/FormField.tsx'
      end
      
      # Always add app-specific types and utilities
      files << 'src/types/app.ts'
      files << 'src/lib/app-utils.ts'
      
      files
    end
    
    def build_batch_prompt(base_prompt, batch, files_created)
      prompt = []
      prompt << base_prompt
      prompt << ""
      prompt << "Files already created:"
      files_created.each { |f| prompt << "- #{f}" }
      prompt << ""
      prompt << "Now create these files:"
      batch.each { |f| prompt << "- #{f}" }
      prompt << ""
      prompt << "Return the complete content for each file."
      prompt.join("\n")
    end
    
    def generate_files_with_claude(prompt, file_paths)
      # This would make the actual API call to Claude
      # For now, implementing the structure
      
      begin
        # TODO: Integrate with actual Claude API
        # response = claude_client.generate(prompt)
        
        # Simulate file generation for now
        files = file_paths.map do |path|
          content = generate_placeholder_content(path)
          create_app_file(path, content)
          path
        end
        
        { success: true, files: files }
      rescue => e
        Rails.logger.error "[V4] Claude generation error: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def generate_placeholder_content(path)
      # Generate appropriate placeholder content based on file type
      file_name = File.basename(path, '.*')
      
      case path
      when /Dashboard\.tsx$/
        <<~TSX
          import React from 'react';
          import { useAuth } from '@/hooks/useAuth';
          import { db } from '@/lib/app-scoped-db';
          
          export default function Dashboard() {
            const { user } = useAuth();
            
            return (
              <div className="container mx-auto p-6">
                <h1 className="text-3xl font-bold mb-6">Dashboard</h1>
                <p>Welcome back, {user?.email}!</p>
                {/* TODO: Add app-specific content here */}
              </div>
            );
          }
        TSX
      when /\.tsx$/
        <<~TSX
          import React from 'react';
          
          export default function #{file_name}() {
            return (
              <div>
                <h2>#{file_name}</h2>
                {/* TODO: Implement #{file_name} component */}
              </div>
            );
          }
        TSX
      when /\.ts$/
        <<~TS
          // #{file_name} implementation
          
          export function #{file_name.gsub(/[^a-zA-Z]/, '')}() {
            // TODO: Implement #{file_name}
            return {};
          }
        TS
      else
        "// TODO: Implement #{path}"
      end
    end
    
    def analyze_component_requirements
      # Analyze generated files to determine which optional components are needed
      components = []
      
      @app.app_files.each do |file|
        content = file.content
        
        # Check for shadcn/ui component usage
        components << 'button' if content.include?('Button')
        components << 'card' if content.include?('Card')
        components << 'input' if content.include?('Input')
        components << 'dialog' if content.include?('Dialog')
        
        # Check for Supabase UI component usage
        components << 'auth/password-based-auth' if content.include?('PasswordAuth')
        components << 'data/infinite-query-hook' if content.include?('useInfiniteQuery')
        components << 'realtime/realtime-chat' if content.include?('RealtimeChat')
      end
      
      components.uniq
    end
    
    def integrate_component(component)
      Rails.logger.info "[V4] Integrating component: #{component}"
      
      # Copy component template to app
      template_path = Rails.root.join('app/templates/optional', "#{component}.tsx")
      
      if File.exist?(template_path)
        content = File.read(template_path)
        target_path = determine_component_path(component)
        
        # Process template variables
        content = process_template_variables(content)
        
        # Create or update the file
        create_app_file(target_path, content)
      else
        Rails.logger.warn "[V4] Component template not found: #{component}"
      end
    end
    
    def determine_component_path(component)
      case component
      when /^auth\//
        "src/components/#{component}"
      when /^data\//
        "src/hooks/#{component.gsub('data/', '')}"
      when /^realtime\//
        "src/components/#{component}"
      else
        "src/components/ui/#{component}.tsx"
      end
    end
    
    def apply_todo_completion(search_result)
      file = search_result[:file]
      line_number = search_result[:line_number]
      
      Rails.logger.info "[V4] Completing TODO at #{file.path}:#{line_number}"
      
      # Use LineReplaceService for surgical edit
      # This is where we'd use AI to complete the TODO
      # For now, just log it
      
      Rails.logger.debug "[V4] Would complete TODO: #{search_result[:match]}"
    end
    
    def broadcast_progress(files_created)
      # Broadcast progress to user via ActionCable or similar
      Rails.logger.info "[V4] Progress: #{files_created.size} files created"
      
      # Could implement real-time updates here
      # ActionCable.server.broadcast("app_#{@app.id}", {
      #   type: 'generation_progress',
      #   files_created: files_created
      # })
    end
    
    def process_template_variables(content)
      content
        .gsub('{{APP_NAME}}', @app.name)
        .gsub('{{APP_ID}}', @app.id.to_s)
        .gsub('{{APP_SLUG}}', @app.name.parameterize)
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
    
    def create_app_file(path, content)
      # Create or update an app file
      existing_file = @app.app_files.find_by(path: path)
      
      if existing_file
        existing_file.update!(content: content)
        Rails.logger.info "[V4] Updated existing file: #{path}"
      else
        @app.app_files.create!(
          path: path,
          content: content,
          team: @app.team
        )
        Rails.logger.info "[V4] Created new file: #{path}"
      end
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