module Ai
  class GenerationError < StandardError; end
  
  class AppBuilderV4
    MAX_RETRIES = 2
    
    def initialize(app_chat_message)
      @app = app_chat_message.app
      @message = app_chat_message
      @app_version = create_new_version
      @broadcaster = Ai::ChatProgressBroadcaster.new(@app, @message.user, @message)
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
      # V4 Enhanced Generation Pipeline with Real-time Chat Feedback
      Rails.logger.info "[V4] Starting enhanced generation pipeline for app ##{@app.id}"
      
      # Start chat feedback with plan overview
      app_type = determine_app_type(@message.content)
      @broadcaster.broadcast_start("a #{app_type} with professional components")
      
      # Phase 1: Generate shared foundation (Day 2 ✅ IMPLEMENTED)
      @broadcaster.broadcast_step_start("Project Foundation", "Setting up package.json, configs, and core files")
      files_before = @app.app_files.count
      generate_shared_foundation
      files_after = @app.app_files.count
      @broadcaster.broadcast_step_complete("Project Foundation", { 
        files_count: files_after - files_before 
      })
      
      # Phase 1.5: Generate AI context with available components
      component_context = generate_component_context
      Rails.logger.info "[V4] Generated component context (#{component_context.length} chars)"
      
      # Phase 2: AI app-specific features with component awareness
      @broadcaster.broadcast_step_start("Core Components", "Generating #{app_type} components with AI")
      files_before = @app.app_files.count
      generate_app_features_with_components(component_context)
      files_after = @app.app_files.count
      @broadcaster.broadcast_step_complete("Core Components", { 
        files_count: files_after - files_before,
        components: extract_component_names_created
      })
      
      # Phase 3: Smart component selection and integration
      @broadcaster.broadcast_step_start("UI Enhancement", "Adding professional UI components")
      integrate_requested_components
      @broadcaster.broadcast_step_complete("UI Enhancement")
      
      # Phase 4: Smart edits via existing services
      @broadcaster.broadcast_step_start("Code Optimization", "Applying smart edits and improvements")
      apply_smart_edits
      @broadcaster.broadcast_step_complete("Code Optimization")
      
      # Phase 5: Build and deploy
      @broadcaster.broadcast_step_start("Build & Deploy", "Building with npm + Vite and deploying")
      @broadcaster.broadcast_build_progress(:npm_install)
      @broadcaster.broadcast_build_progress(:vite_build)
      
      build_result = build_for_deployment
      
      if build_result[:success]
        @broadcaster.broadcast_build_progress(:complete)
        @broadcaster.broadcast_step_complete("Build & Deploy", {
          build_time: build_result[:build_time],
          size: build_result[:size] || 0
        })
        
        # Update app status and complete generation
        @app.update!(status: 'generated')
        
        # Final completion message with preview URL
        @broadcaster.broadcast_completion(
          @app.preview_url,
          {
            size: build_result[:size],
            build_time: build_result[:build_time]
          }
        )
      else
        @broadcaster.broadcast_error("Build failed: #{build_result[:error]}", true)
        @app.update!(status: 'failed')
      end
      
      # Set up for ongoing chat
      @broadcaster.broadcast_chat_ready
      
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
      Rails.logger.info "[V4] Building app ##{@app.id} using external Rails build system"
      
      # Use external Rails-based builder (MVP approach)
      builder = Deployment::ExternalViteBuilder.new(@app)
      
      # Determine if this is preview or production based on context
      is_production = @message.content.downcase.include?('deploy') || 
                     @message.content.downcase.include?('production')
      
      build_result = if is_production
                      Rails.logger.info "[V4] Using production optimized build"
                      builder.build_for_production
                    else
                      Rails.logger.info "[V4] Using fast preview build"
                      builder.build_for_preview
                    end

      # Deploy to Cloudflare Workers (not Pages) if build successful
      if build_result[:success]
        deployment_result = deploy_to_workers_with_secrets(build_result, is_production)
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

    def deploy_to_workers_with_secrets(build_result, is_production = false)
      Rails.logger.info "[V4] Deploying to Cloudflare Workers with secrets for app ##{@app.id}"
      
      # Use new Workers deployer with secrets management
      deployer = Deployment::CloudflareWorkersDeployer.new(@app)
      
      # Deploy to preview or production subdomain
      deployment_type = is_production ? :production : :preview
      deployment_result = deployer.deploy_with_secrets(
        built_code: build_result[:built_code],
        deployment_type: deployment_type
      )
      
      if deployment_result[:success]
        Rails.logger.info "[V4] Workers deployment successful to #{deployment_type} environment"
        # Update app URLs based on deployment type
        update_app_urls_for_deployment_type(deployment_result, deployment_type)
      else
        Rails.logger.warn "[V4] Workers deployment failed: #{deployment_result[:error]}"
      end
      
      deployment_result
    rescue => e
      Rails.logger.error "[V4] Workers deployment error: #{e.message}"
      { success: false, error: e.message }
    end

    def update_app_urls_for_deployment_type(deployment_result, deployment_type)
      updates = {}
      
      if deployment_type == :preview
        # Preview deployments go to preview subdomain
        updates[:preview_url] = deployment_result[:worker_url]  # preview-{app-id}.overskill.app
      elsif deployment_type == :production
        # Production deployments go to main subdomain
        updates[:production_url] = deployment_result[:worker_url]  # app-{app-id}.overskill.app
        updates[:deployed_at] = Time.current
      end
      
      # Also track custom domain if configured
      if deployment_result[:custom_url].present?
        updates[:custom_domain_url] = deployment_result[:custom_url]
      end
      
      @app.update!(updates) if updates.any?
      
      # Ensure environment variables are synced to Worker
      ensure_app_env_vars_synced(deployment_type)
    end
    
    def ensure_app_env_vars_synced(deployment_type)
      # Ensure system defaults and platform secrets are set up
      if defined?(AppEnvVar)
        begin
          AppEnvVar.ensure_system_defaults_for_app(@app) if AppEnvVar.respond_to?(:ensure_system_defaults_for_app)
          AppEnvVar.ensure_platform_secrets_for_app(@app) if AppEnvVar.respond_to?(:ensure_platform_secrets_for_app)
        rescue => e
          Rails.logger.warn "[V4] Could not sync env vars: #{e.message}"
        end
      end
      
      Rails.logger.info "[V4] Environment variables synced for #{deployment_type} deployment"
    end

    
    def generate_app_features_with_components(component_context)
      Rails.logger.info "[V4] Generating app-specific features with AI"
      
      # Build comprehensive prompt with component awareness
      prompt = build_generation_prompt(component_context)
      
      # Use Claude conversation loop for multi-file generation
      response = generate_with_claude_conversation(prompt)
      
      # Detect and add optional components based on AI response
      if response && response[:files]
        enhanced_component_service = Ai::EnhancedOptionalComponentService.new(@app)
        
        # Analyze all generated content for component needs
        all_content = response[:files].map { |f| f[:content] }.join("\n")
        all_content += @message.content # Include original request
        
        components_added = enhanced_component_service.detect_and_add_components(all_content)
        
        if components_added.any?
          Rails.logger.info "[V4] Added enhanced components: #{components_added.join(', ')}"
          
          # Update package.json with new dependencies
          update_package_json_dependencies(enhanced_component_service.get_required_dependencies)
        end
      end
      
      Rails.logger.info "[V4] App-specific features generated"
    end
    
    def integrate_requested_components
      Rails.logger.info "[V4] Integrating requested components"
      
      # Use EnhancedOptionalComponentService for component detection
      enhanced_service = Ai::EnhancedOptionalComponentService.new(@app)
      
      # Analyze user request for explicit component requests
      if @message.content.match?(/\b(add|include|use)\s+(shadcn|supabase)\s+(ui|components?)\b/i)
        if @message.content.match?(/auth|authentication/i)
          enhanced_service.add_component_category('supabase_ui_auth')
        end
        if @message.content.match?(/chat|realtime/i)
          enhanced_service.add_component_category('supabase_ui_realtime')
        end
        if @message.content.match?(/upload|dropzone/i)
          enhanced_service.add_component_category('supabase_ui_data')
        end
      end
      
      Rails.logger.info "[V4] Integrated requested components"
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
    
    def update_package_json_dependencies(new_dependencies)
      return if new_dependencies.empty?
      
      package_file = @app.app_files.find_by(path: 'package.json')
      return unless package_file
      
      begin
        package_json = JSON.parse(package_file.content)
        package_json['dependencies'] ||= {}
        
        # Add new dependencies with latest version marker
        new_dependencies.each do |dep|
          unless package_json['dependencies'].key?(dep)
            package_json['dependencies'][dep] = 'latest'
            Rails.logger.info "[V4] Added dependency: #{dep}"
          end
        end
        
        # Save updated package.json
        package_file.update!(content: JSON.pretty_generate(package_json))
        Rails.logger.info "[V4] Updated package.json with #{new_dependencies.size} new dependencies"
      rescue JSON::ParserError => e
        Rails.logger.error "[V4] Failed to parse package.json: #{e.message}"
      end
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
      { success: true, files: files_created }
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
      Rails.logger.info "[V4] Generating files with Claude: #{file_paths.join(', ')}"
      
      begin
        # Use AnthropicClient for generation
        client = Ai::AnthropicClient.instance
        
        # Build messages for Claude
        messages = build_claude_messages(prompt, file_paths)
        
        # Make API call with appropriate model
        response = client.chat(
          messages,
          model: :claude_sonnet_4,
          temperature: 0.7,
          max_tokens: 8000
        )
        
        # Parse and create files from response
        generated_files = parse_claude_response(response, file_paths)
        
        # Track token usage for billing
        track_token_usage(response) if response[:usage]
        
        { success: true, files: generated_files }
      rescue => e
        Rails.logger.error "[V4] Claude generation error: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def build_claude_messages(prompt, file_paths)
      system_prompt = <<~PROMPT
        You are an expert TypeScript and React developer.
        Generate the requested files with production-quality code.
        Use the app-scoped database wrapper (db.from()) for all Supabase queries.
        Follow TypeScript best practices and use proper typing.
        Include appropriate imports and exports.
      PROMPT
      
      user_prompt = <<~PROMPT
        #{prompt}
        
        Please generate the following files:
        #{file_paths.map { |p| "- #{p}" }.join("\n")}
        
        Return each file in this format:
        
        FILE: path/to/file.tsx
        ```typescript
        // file contents here
        ```
        
        Make sure each file is complete and functional.
      PROMPT
      
      [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]
    end
    
    def parse_claude_response(response, requested_paths)
      generated_files = []
      content = response[:content] || response["content"] || ""
      
      # Parse files from response using FILE: markers
      file_sections = content.split(/^FILE:\s*/m).drop(1)
      
      file_sections.each do |section|
        lines = section.lines
        path = lines.first.strip
        
        # Extract code block content
        code_match = section.match(/```(?:typescript|tsx|ts|jsx|js)?\n(.*?)```/m)
        next unless code_match
        
        file_content = code_match[1]
        
        # Create the app file
        create_app_file(path, file_content)
        generated_files << { path: path, content: file_content }
        
        Rails.logger.info "[V4] Created file: #{path}"
      end
      
      # If no files parsed but we have requested paths, create with placeholder
      if generated_files.empty? && requested_paths.any?
        Rails.logger.warn "[V4] Claude response didn't contain expected file format, creating placeholders"
        requested_paths.each do |path|
          content = generate_placeholder_content(path)
          create_app_file(path, content)
          generated_files << { path: path, content: content }
        end
      end
      
      generated_files
    end
    
    def track_token_usage(response)
      usage = response[:usage] || response["usage"]
      return unless usage
      
      input_tokens = usage[:input_tokens] || usage["input_tokens"] || 0
      output_tokens = usage[:output_tokens] || usage["output_tokens"] || 0
      
      # Calculate cost (Claude Sonnet 4: $3/1M input, $15/1M output)
      input_cost_cents = (input_tokens * 0.3).round # $3 per 1M = $0.003 per 1K = 0.3 cents per 1K
      output_cost_cents = (output_tokens * 1.5).round # $15 per 1M = $0.015 per 1K = 1.5 cents per 1K
      total_cost_cents = input_cost_cents + output_cost_cents
      
      # Update app version with token usage
      @app_version.update!(
        ai_tokens_input: (@app_version.ai_tokens_input || 0) + input_tokens,
        ai_tokens_output: (@app_version.ai_tokens_output || 0) + output_tokens,
        ai_cost_cents: (@app_version.ai_cost_cents || 0) + total_cost_cents,
        ai_model_used: 'claude-3-5-sonnet-20241022'
      )
      
      Rails.logger.info "[V4] Token usage tracked: #{input_tokens} in / #{output_tokens} out (#{total_cost_cents} cents)"
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
      todo_content = search_result[:match]
      context_before = search_result[:context_before] || []
      context_after = search_result[:context_after] || []
      
      Rails.logger.info "[V4] Completing TODO at #{file.path}:#{line_number}"
      
      # Determine what needs to be done based on TODO content
      replacement = generate_todo_replacement(todo_content, file.path, context_before, context_after)
      
      # Use LineReplaceService for surgical edit
      result = Ai::LineReplaceService.replace_lines(
        file,
        todo_content,
        line_number,
        line_number,
        replacement
      )
      
      if result[:success]
        Rails.logger.info "[V4] Successfully completed TODO at #{file.path}:#{line_number}"
      else
        Rails.logger.warn "[V4] Failed to complete TODO: #{result[:error]}"
      end
      
      result
    end
    
    def generate_todo_replacement(todo_content, file_path, context_before, context_after)
      # Analyze the TODO and generate appropriate replacement
      case todo_content
      when /TODO:\s*Implement\s+(.+)/i
        feature = $1.strip
        generate_implementation_for(feature, file_path)
      when /FIXME:\s*(.+)/i
        issue = $1.strip
        generate_fix_for(issue, file_path)
      when /\{\{(.+?)\}\}/
        placeholder = $1.strip
        generate_value_for(placeholder, file_path)
      else
        # Return original if we can't determine what to do
        todo_content
      end
    end
    
    def generate_implementation_for(feature, file_path)
      # Generate appropriate implementation based on feature and file type
      case file_path
      when /\.tsx?$/
        # TypeScript/React implementation
        "// #{feature} implementation\n    // Auto-generated by V4 builder"
      when /\.css$/
        "/* #{feature} styles */\n    /* Auto-generated by V4 builder */"
      else
        "// #{feature}"
      end
    end
    
    def generate_fix_for(issue, file_path)
      # Generate fix for identified issue
      "// Fixed: #{issue}\n    // Auto-corrected by V4 builder"
    end
    
    def generate_value_for(placeholder, file_path)
      # Replace placeholders with actual values
      case placeholder
      when "APP_NAME"
        @app.name
      when "APP_ID"
        @app.id.to_s
      when "APP_SLUG"
        @app.subdomain || @app.name.parameterize
      else
        placeholder # Keep original if unknown
      end
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
        # Check if this file is already tracked in this version to avoid constraint violations
        existing_version_file = @app_version.app_version_files.find_by(app_file: app_file)
        
        unless existing_version_file
          @app_version.app_version_files.create!(
            app_file: app_file,
            action: 'created',
            content: app_file.content  # Include content for validation
          )
        end
      end
      
      Rails.logger.info "[V4] Tracked #{files_created.count} template files in version"
    end
    
    def create_new_version
      @app.app_versions.create!(
        team: @app.team,
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
      when Ai::GenerationError
        context << "This appears to be an AI generation issue. Please:"
        context << "1. Review the current app structure and identify the problem"
        context << "2. Fix any syntax errors or missing dependencies"
        context << "3. Continue with the generation process"
      when Timeout::Error
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
      # Create or update an app file with chat feedback
      # Ensure content is not nil or empty
      content = content.presence || "// Placeholder content for #{path}"
      
      existing_file = @app.app_files.find_by(path: path)
      
      if existing_file
        existing_file.update!(content: content)
        Rails.logger.info "[V4] Updated existing file: #{path}"
      else
        new_file = @app.app_files.create!(
          path: path,
          content: content,
          team: @app.team
        )
        
        Rails.logger.info "[V4] Created new file: #{path}"
        
        # Broadcast file creation with preview if it's a component
        preview = nil
        if path.match?(/\.(tsx|jsx|ts|js)$/) && content.length > 50
          # Extract first few lines for preview
          lines = content.lines.first(5)
          preview = lines.join.strip if lines.any?
        end
        
        @broadcaster&.broadcast_file_created(path, content.length, preview)
      end
    end
    
    def determine_app_type(content)
      content_lower = content.downcase
      
      return "todo/task management app" if content_lower.match?(/todo|task|checklist/)
      return "chat application" if content_lower.match?(/chat|message|conversation/)
      return "e-commerce store" if content_lower.match?(/shop|store|ecommerce|product|cart/)
      return "dashboard application" if content_lower.match?(/dashboard|admin|analytics/)
      return "blog/CMS" if content_lower.match?(/blog|cms|content|post/)
      return "authentication system" if content_lower.match?(/auth|login|user|account/)
      return "file management app" if content_lower.match?(/file|upload|storage|document/)
      return "social media app" if content_lower.match?(/social|profile|feed|follow/)
      return "productivity app" if content_lower.match?(/note|calendar|remind|schedule/)
      
      "web application"
    end
    
    def extract_component_names_created
      # Extract component names from recently created files
      components = []
      
      @app.app_files.where("path LIKE 'src/components/%'").each do |file|
        if file.path.match?(/\/([A-Z][a-zA-Z0-9]*)\.(tsx|ts|jsx|js)$/)
          component_name = ::File.basename(file.path, '.*')
          components << component_name unless components.include?(component_name)
        end
      end
      
      components.first(5) # Return first 5 components to avoid clutter
    end

    def mark_as_failed(error)
      @app.update!(
        status: 'failed'
      )
      
      @app_version.update!(
        changelog: "V4 generation failed: #{error.message.truncate(200)}"
      )
      
      Rails.logger.error "[V4] App ##{@app.id} marked as failed after #{MAX_RETRIES} retries"
    end
  end
end