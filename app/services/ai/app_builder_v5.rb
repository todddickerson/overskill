# AppBuilderV5 - Agent Loop Implementation with Lovable-style architecture
require_relative 'context_manager'
require_relative 'agent_decision_engine'
require_relative 'termination_evaluator'

module Ai
  class AppBuilderV5
    include Rails.application.routes.url_helpers
    include Ai::Concerns::CacheInvalidation
    
    MAX_ITERATIONS = 30
    COMPLETION_CONFIDENCE_THRESHOLD = 0.85
    
    attr_reader :chat_message, :app, :agent_state, :assistant_message, :file_tracker
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app || create_app
      @start_time = Time.current
      @iteration_count = 0
      @completion_status = :active
      @last_flow_timestamp = nil  # Track timestamp for conversation flow ordering
      
      # Initialize security filter
      @security_filter = Security::PromptInjectionFilter.new
      
      # Initialize GitHub Migration Project services
      @use_repository_mode = ENV['USE_REPOSITORY_MODE'] == 'true'
      if @use_repository_mode && @app
        @github_service = @app.github_repository_service
        # No longer need @cloudflare_service - GitHub Actions handles deployment
        Rails.logger.info "[V5_GITHUB] Repository mode enabled for app ##{@app.id}"
      end
      
      # Initialize incremental streaming feature flag
      @incremental_streaming_enabled = ENV['INCREMENTAL_TOOL_STREAMING'] == 'true'
      Rails.logger.info "[V5_INIT] Incremental streaming: #{@incremental_streaming_enabled ? 'ENABLED' : 'disabled'}"
      
      # Initialize centralized tool service for cleaner architecture
      # All tool implementations are now in AiToolService for better maintainability
      # See app/services/ai/ai_tool_service.rb for tool implementations
      tool_service_options = {
        logger: Rails.logger, 
        user: chat_message.user,
        # GitHub Migration Project: Pass repository mode configuration
        use_repository_mode: @use_repository_mode,
        github_service: @github_service,
        cloudflare_service: @cloudflare_service
      }
      @tool_service = Ai::AiToolService.new(@app, tool_service_options)
      
      # Create assistant reply message for V5 UI
      @assistant_message = create_assistant_message
      
      # No separate broadcaster needed - we'll use direct updates
      
      # Analyze component requirements EARLY for context optimization
      @component_analysis = Ai::ComponentRequirementsAnalyzer.analyze_with_confidence(
        chat_message.content,
        app ? app.app_files : []
      )
      @predicted_components = @component_analysis[:components]
      @detected_app_type = @component_analysis[:app_type]
      
      Rails.logger.info "[V5_OPTIMIZATION] Predicted components: #{@predicted_components.join(', ')}"
      Rails.logger.info "[V5_OPTIMIZATION] Detected app type: #{@detected_app_type}"
      
      # Initialize agent components
      @prompt_service = Prompts::AgentPromptService.new(agent_variables)
      
      # TODO: Consider adding GoalTracker as a tool call instead of internal logic
      # For now, simplify by removing GoalTracker to reduce confusion
      # @goal_tracker = GoalTracker.new(chat_message.content)
      
      # Debug: check if prompt service works
      Rails.logger.debug "[V5_DEBUG] Prompt service initialized"
      Rails.logger.debug "[V5_DEBUG] Agent variables: #{agent_variables.keys.join(', ')}"
      @context_manager = Ai::ContextManager.new(app)
      @decision_engine = Ai::AgentDecisionEngine.new
      @termination_evaluator = Ai::TerminationEvaluator.new
      
      # Initialize file change tracker for granular caching
      @file_tracker = FileChangeTracker.new(@app.id)
      
      # Configure streaming mode for tools and API calls
      @streaming_enabled = true # Feature flag for streaming tools execution 
      @api_streaming_enabled = true # API streaming enabled for monitoring verification
      
      # Initialize state
      @agent_state = {
        iteration: 0,
        context: {},
        history: [],
        errors: [],
        generated_files: [],
        modified_files: {},  # Track which files have been modified
        verification_results: []
      }
      
      # Template files are now copied on app creation (in App model after_create)
      # Just track existing files as already generated
      initialize_existing_files
    end
    
    def initialize_existing_files
      # Track all existing app files (including those copied from template)
      @app.app_files.each do |file|
        @agent_state[:generated_files] << file
      end
      Rails.logger.info "[V5_INIT] Tracking #{@agent_state[:generated_files].count} existing files"
    end
    
    def execute!
      Rails.logger.info "[AppBuilderV5] Starting agent loop for app ##{app.id}"
      
      begin
        # Mark app as generating
        app.update!(status: 'generating')
        update_thinking_status("Phase 1/6: Starting AI Agent")
        
        # GitHub Migration Project: Repository setup moved to finalization phase
        # This ensures we create the repository AFTER code generation completes
        Rails.logger.info "[V5_GITHUB] Repository setup deferred to finalization phase"
        
        # Analyze requirements (let Claude handle goal extraction naturally)
        update_thinking_status("Analyzing your requirements...")
        
        # Log the start
        log_claude_event("AGENT_LOOP_STARTED", {
          user_request: @chat_message.content.truncate(100)
        })
        
        # Execute agent loop
        execute_until_complete
        
        # Finalize
        finalize_app_generation
        
      rescue Ai::RateLimitError => e
        Rails.logger.error "[V5_RATE_LIMIT] Rate limit error: #{e.message}"
        
        # Create user-friendly error message
        error_message = if e.message.include?("0 token")
          "⚠️ **API Access Issue**\n\n" \
          "The Anthropic API key currently has no available tokens. This usually means:\n" \
          "- The API key may need billing setup at console.anthropic.com\n" \
          "- The account may be suspended or require payment\n" \
          "- The API key might be invalid\n\n" \
          "Please contact support to resolve this issue."
        else
          "⚠️ **Rate Limit Exceeded**\n\n" \
          "We've hit the Anthropic API rate limit. Please wait a few moments and try again.\n\n" \
          "If this persists, we may need to upgrade our API plan."
        end
        
        # Update assistant message with error
        @assistant_message.update!(
          content: error_message,
          status: "failed"
        )
        
        # Update app status
        app.update!(status: "failed", build_error: e.message)
        
        return # Don't continue processing
        
      rescue => e
        Rails.logger.error "[V5_CRITICAL] AppBuilderV5 execute! failed: #{e.class.name}: #{e.message}"
        Rails.logger.error "[V5_CRITICAL] FULL STACK TRACE:"
        e.backtrace.each_with_index do |line, i|
          Rails.logger.error "[V5_CRITICAL]   #{i.to_s.rjust(2)}: #{line}"
        end
        
        # Special handling for nil access errors
        if e.message.include?("undefined method `[]'") || e.message.include?("undefined method `dig'")
          Rails.logger.error "[V5_CRITICAL] *** CRITICAL NIL ACCESS ERROR ***"
          Rails.logger.error "[V5_CRITICAL] This is the main error we're investigating!"
          Rails.logger.error "[V5_CRITICAL] Error occurred in: #{e.backtrace.first}"
          Rails.logger.error "[V5_CRITICAL] Current iteration: #{@iteration_count}"
          Rails.logger.error "[V5_CRITICAL] App ID: #{@app.id}" if @app
          Rails.logger.error "[V5_CRITICAL] Message ID: #{@assistant_message.id}" if @assistant_message
        end
        
        handle_error(e)
        return # CRITICAL: Don't continue to finalize_app_generation after error
      end
    end

    # =============================================================================
    # GITHUB MIGRATION PROJECT METHODS
    # =============================================================================

    def setup_github_repository_with_code
      Rails.logger.info "[V5_GITHUB] Setting up GitHub repository with generated code for app ##{@app.id}"
      
      begin
        # Create repository via forking (2-3 seconds) 
        result = @app.create_repository_via_fork!
        
        if result[:success]
          Rails.logger.info "[V5_GITHUB] ✅ Repository setup complete: #{@app.repository_url}"
          
          # Set up GitHub Actions secrets for Cloudflare Workers deployment
          secrets_result = @github_service.setup_deployment_secrets
          if secrets_result[:success]
            Rails.logger.info "[V5_GITHUB] ✅ Deployment secrets configured"
          else
            Rails.logger.warn "[V5_GITHUB] ⚠️ Failed to configure deployment secrets: #{secrets_result[:error]}"
          end
          
          # Initialize repository tracking in agent state
          @agent_state[:github_repository] = {
            url: @app.repository_url,
            name: @app.repository_name,
            # worker_name field deprecated - WFP uses dispatch namespaces
            setup_completed: true,
            secrets_configured: secrets_result[:success]
          }
        else
          Rails.logger.error "[V5_GITHUB] ❌ Repository setup failed: #{result[:error]}"
          raise StandardError, "Failed to create GitHub repository: #{result[:error]}"
        end
      rescue => e
        Rails.logger.error "[V5_GITHUB] Repository setup exception: #{e.message}"
        @app.update!(repository_status: 'failed')
        raise e
      end
    end
        
    def execute_until_complete
      Rails.logger.info "[V5_LOOP] Starting execute_until_complete"
      
      # Feature flag to use simple flow vs complex decision engine
      use_simple_flow = ENV.fetch('V5_SIMPLE_FLOW', 'true') == 'true'
      
      if use_simple_flow
        # SIMPLE FLOW: Just let Claude do its thing
        Rails.logger.info "[V5_LOOP] Using SIMPLE FLOW - no decision engine"
        execute_simple_claude_flow
      else
        # ORIGINAL COMPLEX FLOW with decision engine
        execute_complex_decision_loop
      end
    end
    
    def execute_simple_claude_flow
      # Simple flow: Send context to Claude, let it do its thing, deploy
      Rails.logger.info "[V5_SIMPLE] Starting simple Claude flow"
      
      # Detect if this is initial build or continuation
      # Check if there are previous assistant messages (not just template files)
      is_continuation = @app.app_chat_messages.where(role: 'assistant').where.not(id: @assistant_message.id).exists?
      Rails.logger.info "[V5_SIMPLE] Mode: #{is_continuation ? 'CONTINUATION' : 'INITIAL BUILD'}"
      Rails.logger.info "[V5_SIMPLE] Total messages: #{@app.app_chat_messages.count}, previous assistant messages: #{@app.app_chat_messages.where(role: 'assistant').where.not(id: @assistant_message.id).count}"
      
      @iteration_count = 1
      @agent_state[:iteration] = @iteration_count
      update_iteration_count
      
      begin
        # Phase 1: Send user's raw message to Claude - system context handles the rest
        if is_continuation
          # update_thinking_status("Analyzing your request and updating the app...")
          update_thinking_status("Thinking...")
        else
          # update_thinking_status("Phase 1/3: Analyzing requirements and generating app...")
          update_thinking_status("Thinking...")
        end
        
        # Enhance the user message with additional instructions for first-time app generation
        user_message = if is_continuation
          # For continuations, just use the raw message
          @chat_message.content
        else
          # NOTE: This runs for new apps only, anything needed for 'starting new apps' with hard enforcement should be done in the prompt
          # For initial app generation, add instructions to name the app and generate a logo
          enhanced_message = @chat_message.content + "\n\n"
          enhanced_message += "<system-reminder>IMPORTANT: As part of creating this app:\n"
          enhanced_message += "1. Use the 'rename-app' tool to give the app an appropriate name based on its purpose\n"
          enhanced_message += "2. After naming, use the 'generate-new-app-logo' tool to create a logo that matches the app's theme\n"
          enhanced_message += "3. Choose a logo style that fits the app's purpose (modern, professional, playful, etc.)\n"
          enhanced_message += "\nThese should be done early in the generation process, after understanding the app's requirements.</system-reminder>"
          enhanced_message
        end
        
        # Send the (potentially enhanced) message to Claude
        response = call_ai_with_context(user_message)
        
        # Claude's response (with tool calls) is already handled by execute_tool_calling_cycle
        Rails.logger.info "[V5_SIMPLE] Claude completed work"
        
        # Phase 2: Build and deploy preview
        update_thinking_status("Building and deploying preview...")
        deploy_result = deploy_preview_if_ready
        
        if deploy_result[:success]
          # Phase 3: Complete
          update_thinking_status("Complete!")

          # Note; adds debugging logs in chat
          # if is_continuation
          #   add_loop_message("App updated successfully. Preview is ready at: #{deploy_result[:preview_url]}", type: 'status')
          # else
          #   add_loop_message("App generation complete. Preview is ready at: #{deploy_result[:preview_url]}", type: 'status')
          # end
          
          # Mark completion
          @completion_status = :complete
        else
          add_loop_message("Deployment failed: #{deploy_result[:error]}", type: 'error')
          @completion_status = :failed
        end
        
      rescue => e
        Rails.logger.error "[V5_SIMPLE] Error in simple flow: #{e.class.name}: #{e.message}"
        Rails.logger.error "[V5_SIMPLE] FULL STACK TRACE:"
        e.backtrace.each_with_index do |line, i|
          Rails.logger.error "[V5_SIMPLE]   #{i.to_s.rjust(2)}: #{line}"
        end
        
        # Enhanced error message based on error type
        if e.message.include?("undefined method `[]'")
          Rails.logger.error "[V5_SIMPLE] *** NIL ACCESS ERROR DETECTED ***"
          Rails.logger.error "[V5_SIMPLE] This is the undefined method [] for nil error we're tracking"
          error_msg = "Critical error: Trying to access array/hash element on nil value. Location: #{e.backtrace.first}"
        elsif e.is_a?(NoMethodError)
          Rails.logger.error "[V5_SIMPLE] *** NO METHOD ERROR ***"
          error_msg = "Method error: #{e.message}"
        elsif e.message.include?("<html") || e.message.include?("<!DOCTYPE") || e.message.include?("<!--")
          Rails.logger.error "[V5_SIMPLE] *** HTML ERROR RESPONSE DETECTED ***"
          
          # Try to extract meaningful error from HTML
          if e.message.include?("Worker exceeded resource limits")
            error_msg = "API Error: Worker exceeded resource limits. The request was too large or complex. Please try a simpler request."
          elsif e.message.include?("anthropic.helicone.ai")
            error_msg = "API Error: Request failed at proxy layer. Please try again in a moment."
          elsif e.message.include?("502") || e.message.include?("Bad Gateway")
            error_msg = "API Error: Service temporarily unavailable (502 Bad Gateway). Please try again."
          elsif e.message.include?("503") || e.message.include?("Service Unavailable")
            error_msg = "API Error: Service temporarily unavailable (503). Please try again."
          else
            # Generic HTML error - don't show raw HTML
            error_msg = "API Error: Received invalid response from server. Please try again."
          end
        else
          error_msg = "Error during generation: #{e.message}"
        end
        
        add_loop_message(error_msg, type: 'error')
        @completion_status = :failed  # Mark as failed to prevent deployment
        raise e
      end
    end
    
    def deploy_preview_if_ready
      if @use_repository_mode && @app.using_repository_mode?
        # GitHub Migration Project: Use Cloudflare Workers Builds deployment
        deploy_with_github_workers
      else
        # Legacy mode: Use existing DeployAppJob
        deploy_with_legacy_job
      end
    rescue => e
      Rails.logger.error "[V5_DEPLOY] Deployment error: #{e.message}"
      { success: false, error: e.message }
    end

    def deploy_with_github_workers
      Rails.logger.info "[V5_GITHUB] GitHub Actions will handle deployment"
      
      # Check if repository is ready
      unless @app.repository_ready?
        return { success: false, error: "Repository not ready for deployment" }
      end
      
      # GitHub Actions will automatically build and deploy from the repository
      # DeployAppJob will be queued by ProcessAppUpdateJobV4 after version creation
      # No need to call old Cloudflare services anymore
      
      # Update app status to indicate generation is complete
      @app.update!(
        status: 'ready',
        deployment_status: 'pending_deployment',
        last_deployed_at: Time.current
      )
      
      Rails.logger.info "[V5_GITHUB] ✅ Generation complete, GitHub Actions will deploy"
      
      return {
        success: true,
        deployment_type: 'github_actions',
        message: "Generation complete, deployment will be handled by GitHub Actions"
      }
    end

    def deploy_with_legacy_job
      # Check if we have files to deploy (either new or existing)
      total_files = @app.app_files.count
      new_files = @agent_state[:generated_files].count
      
      if total_files == 0
        Rails.logger.warn "[V5_LEGACY] No files to deploy"
        return { success: false, error: "No files to deploy" }
      end
      
      Rails.logger.info "[V5_LEGACY] Ready for deployment with #{total_files} total files (#{new_files} new/modified)"
      
      # NOTE: DeployAppJob is queued by ProcessAppUpdateJobV4 after app version is created
      # We don't queue it here to ensure proper sequencing
      
      # Update app status to indicate generation is complete
      @app.update!(status: 'ready')
      
      # Return success - deployment will be handled after app version creation
      { success: true, message: "Generation complete" }
    end
    
    def execute_complex_decision_loop
      # Original complex flow with decision engine
      loop do
        @iteration_count += 1
        @agent_state[:iteration] = @iteration_count
        
        # Update V5 UI with iteration count
        update_iteration_count
        
        Rails.logger.info "[V5_LOOP] Starting iteration #{@iteration_count}"
        
        # Safety check for infinite loops
        if @iteration_count > MAX_ITERATIONS
          Rails.logger.warn "[AppBuilderV5] Max iterations reached"
          add_loop_message("Maximum iterations reached. Finalizing generation.", type: 'status')
          break
        end
        
        # Execute one iteration of the agent loop
        Rails.logger.info "[V5_LOOP] Calling execute_iteration"
        result = execute_iteration
        
        if result.nil?
          Rails.logger.error "[V5_CRITICAL] execute_iteration returned nil - stopping loop"
          add_loop_message("Critical error: iteration returned nil result", type: 'error')
          break
        end
        
        Rails.logger.info "[V5_LOOP] Iteration result: #{result[:type] || 'unknown'}"
        
        # Update progress tracking
        update_progress_tracking(result)
        
        # Check for loop detection
        if loop_detected?(result)
          Rails.logger.warn "[V5_LOOP] Loop detected - stopping to prevent infinite iteration"
          add_loop_message("Loop detected in operations - stopping to prevent repetitive actions.", type: 'error')
          break
        end
        
        # Check termination conditions
        if should_terminate?(result)
          Rails.logger.info "[V5_LOOP] Termination condition met"
          # Status message already added in should_terminate? when appropriate
          break
        end
        
        # Update context for next iteration
        @context_manager.update_from_result(result)
        @agent_state[:history] << result
      end
    end
    
    def execute_iteration
      # Assess current state
      current_state = assess_current_state
      
      # Update progress (simplified - let Claude determine completion naturally)
      update_thinking_status(
        "Iteration #{@iteration_count}: Analyzing current state and determining next actions"
      )
      
      # Determine next action based on state
      next_action = @decision_engine.determine_next_action(current_state)
      
      Rails.logger.info "[AppBuilderV5] Next action: #{next_action[:type]}"
      
      # Execute the determined action
      result = execute_action(next_action)
      
      # Verify and validate results
      verification = verify_result(result)
      @agent_state[:verification_results] << verification
      
      {
        iteration: @iteration_count,
        state: current_state,
        action: next_action,
        result: result,
        verification: verification
      }
    end
    
    def assess_current_state
      {
        app_id: app.id,
        iteration: @iteration_count,
        context_completeness: @context_manager.completeness_score,
        files_generated: @agent_state[:generated_files].count,
        recent_operations: @recent_operations&.count || 0,
        loop_risk: assess_loop_risk,
        errors: @agent_state[:errors],
        last_action: @agent_state[:history].last&.dig(:action, :type),
        last_verification_confidence: @agent_state[:verification_results].last&.dig(:confidence) || 0,
        user_prompt: @chat_message.content
      }
    end
    
    def execute_action(action)
      case action[:type]
      when :gather_context
        gather_additional_context(action)
      when :plan_implementation
        plan_app_implementation(action)
      when :execute_tools
        execute_tool_operations(action)
      when :verify_changes
        verify_generated_code(action)
      when :debug_issues
        debug_and_fix_issues(action)
      when :request_feedback
        request_user_feedback(action)
      when :complete_task
        complete_app_generation(action)
      else
        handle_unknown_action(action)
      end
    end
    
    def gather_additional_context(action)
      update_thinking_status("Gathering additional context...")
      
      # Use the prompt service to get more specific requirements
      context_prompt = @prompt_service.generate_prompt.merge(
        additional_context: "Focus on understanding: #{action[:focus_areas].join(', ')}"
      )
      
      response = call_ai_with_context(context_prompt)
      
      # Capture Claude's conversational response (with thinking blocks for continuity)
      if response[:content].present?
        # Validate output for security issues
        if !@security_filter.validate_output(response[:content])
          Rails.logger.warn "[SECURITY] Suspicious output detected, filtering response"
          filtered_content = @security_filter.filter_response(response[:content])
          add_loop_message(filtered_content, type: 'content', thinking_blocks: response[:thinking_blocks])
        else
          add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
        end
      end
      
      @context_manager.add_context(response)
      
      # Clear thinking status and add result
      update_thinking_status(nil)
      add_loop_message("Analyzed project requirements and context.", type: 'status')
      
      { type: :context_gathered, data: response }
    end
    
    def plan_app_implementation(action)
      update_thinking_status("Phase 2/6: Planning Architecture")
      update_thinking_status("Thinking..")
      
      # Generate comprehensive plan using template structure
      plan_prompt = build_planning_prompt
      
      begin
        response = call_ai_with_context(plan_prompt)
        Rails.logger.info "[V5_LOOP] AI response received: #{response.inspect[0..200]}"
      rescue => e
        Rails.logger.error "[V5_ERROR] Failed to call AI: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        return { type: :error, error: e.message }
      end
      
      # Check if response is nil or empty
      if response.nil? || (response[:content].blank? && response[:tool_calls].blank?)
        Rails.logger.error "[V5_ERROR] Empty response from Claude API"
        return { type: :error, error: "Empty response from AI" }
      end
      
      # Capture Claude's conversational response about the plan (with thinking blocks)
      if response[:content].present?
        add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
      end
      
      # Extract and structure the plan
      implementation_plan = extract_implementation_plan(response)
      @context_manager.set_implementation_plan(implementation_plan)
      
      { type: :plan_created, data: implementation_plan }
    end
    
    def execute_tool_operations(action)
      update_thinking_status("Phase 4/6: Generating Features")
      
      # Special handling for implementing features - call Claude to do the work
      if action[:tools].any? { |t| t[:type] == :implement_features }
        update_thinking_status("Implementing app-specific features...")
        
        # Build prompt for implementing features
        feature_prompt = <<~PROMPT
          Now implement the specific features requested by the user. 
          Use the existing template files as a foundation.
          
          User request: #{@chat_message.content}
          
          Use the os-write, os-line-replace, and other tools to implement the features.
          Focus on creating a working implementation that meets all requirements.
        PROMPT
        
        # Call Claude to implement features
        response = call_ai_with_context(feature_prompt)
        
        # Only capture Claude's actual conversational response if present (with thinking blocks)
        if response[:content].present?
          add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
        end
        
        # Process any tool calls from the response
        if response[:tool_calls].present?
          tool_results = process_tool_calls(response[:tool_calls])
          return { type: :tools_executed, data: tool_results }
        else
          return { type: :tools_executed, data: [{ success: true, content: response[:content] }] }
        end
      end
      
      # Original tool processing logic
      results = []
      action[:tools].each_with_index do |tool, index|
        update_thinking_status("Executing: #{tool[:description]}")
        
        result = case tool[:type]
        when :generate_file
          generate_file_with_template(tool)
        when :update_file
          update_existing_file(tool)
        when :create_component
          create_ui_component(tool)
        when :setup_integration
          setup_integration(tool)
        else
          { error: "Unknown tool type: #{tool[:type]}" }
        end
        
        results << result
        
        # Update progress
        progress_percent = ((index + 1) / action[:tools].count.to_f * 100).to_i
        update_thinking_status("Progress: #{progress_percent}% - #{index + 1}/#{action[:tools].count} operations completed")
      end
      
      { type: :tools_executed, data: results }
    end
    
    def generate_file_with_template(tool)
      file_path = tool[:file_path]
      
      # Add tool call with running status
      add_tool_call("os-write", file_path: file_path, status: 'running')
      
      # Use overskill_20250728 template as base
      template_path = Rails.root.join("app/services/ai/templates/overskill_20250728")
      
      # Generate content using AI with template context
      content = generate_file_content(tool, template_path)
      
      # Store the generated file
      generated_file = store_generated_file(file_path, content)
      @agent_state[:generated_files] << generated_file
      
      # Update tool call status to complete - must reassign array for change detection
      updated_tool_calls = @assistant_message.tool_calls.deep_dup
      updated_tool_calls.last['status'] = 'complete'
      @assistant_message.tool_calls = updated_tool_calls
      @assistant_message.save!
      
      { 
        type: :file_generated, 
        path: file_path, 
        size: content.bytesize,
        id: generated_file.id 
      }
    end
    
    def verify_generated_code(action)
      update_thinking_status("Phase 5/6: Validating & Building")
      update_thinking_status("Verifying generated code...")
      
      verification_results = {
        syntax_valid: true,
        dependencies_resolved: true,
        build_successful: false,
        errors: []
      }
      
      # Run various verification checks
      @agent_state[:generated_files].each do |file|
        case file.path
        when /\.tsx?$/
          # TypeScript validation
          result = validate_typescript_file(file)
          verification_results[:syntax_valid] &&= result[:valid]
          verification_results[:errors] += result[:errors]
        when /package\.json$/
          # Dependency check
          result = validate_dependencies(file)
          verification_results[:dependencies_resolved] &&= result[:valid]
        end
      end
      
      # Attempt build
      if verification_results[:syntax_valid] && verification_results[:dependencies_resolved]
        build_result = attempt_build
        verification_results[:build_successful] = build_result[:success]
        verification_results[:errors] += build_result[:errors]
      end
      
      { type: :verification_complete, data: verification_results }
    end
    
    def debug_and_fix_issues(action)
      update_thinking_status("Debugging and fixing issues...")
      
      fixes_applied = []
      
      action[:issues].each do |issue|
        fix_prompt = build_fix_prompt(issue)
        fix_response = call_ai_with_context(fix_prompt)
        
        # Capture Claude's explanation of the fix
        if fix_response[:content].present?
          add_loop_message("🔧 #{fix_response[:content]}", type: 'content')
        end
        
        # Apply the fix
        if fix_response[:file_updates]
          fix_response[:file_updates].each do |update|
            apply_file_fix(update)
            fixes_applied << update
          end
        end
      end
      
      { type: :issues_fixed, data: fixes_applied }
    end
    
    def complete_app_generation(action)
      update_thinking_status("Phase 6/6: Finalizing")
      update_thinking_status("Completing app generation...")
      
      # Final validation
      final_check = perform_final_validation
      
      if final_check[:success]
        @completion_status = :complete
        { type: :generation_complete, data: final_check }
      else
        # Need another iteration to fix remaining issues
        { type: :needs_iteration, data: final_check }
      end
    end
    
    def verify_result(result)
      case result[:type]
      when :tools_executed
        # Check if files were created successfully
        success_rate = result[:data].count { |r| !r[:error] } / result[:data].count.to_f
        # Don't be too confident just because tools succeeded - we need to verify the app works
        { 
          success: success_rate > 0.8, 
          confidence: [success_rate * 0.7, 0.8].min,  # Cap at 0.8 for tool execution
          details: result[:data]
        }
      when :verification_complete
        # Check verification results
        data = result[:data]
        success = data[:syntax_valid] && data[:dependencies_resolved] && data[:build_successful]
        { 
          success: success, 
          confidence: success ? 0.9 : 0.3,
          errors: data[:errors]
        }
      when :generation_complete
        { success: true, confidence: 1.0 }
      when :plan_created
        # Plan was created, continue with implementation
        { success: true, confidence: 0.3 }
      when :context_gathered
        # Context was gathered, continue processing
        { success: true, confidence: 0.2 }
      when :error
        # Error occurred
        { success: false, confidence: 0.0, error: result[:error] }
      else
        # Default case - continue processing
        { success: true, confidence: 0.4 }
      end
    end
    
    def check_for_completion_signal
      # Check recent messages for Claude's completion signal
      return false unless @assistant_message.loop_messages.present?
      
      # Check last few messages for the completion signal
      recent_messages = @assistant_message.loop_messages.last(3)
      
      recent_messages.any? do |msg|
        content = msg['content'].to_s.downcase
        # Look for phrases that indicate the app is ready
        content.include?('functional and ready for preview') ||
        content.include?('app is now functional') ||
        content.include?('ready for preview') ||
        content.include?('ready to preview') ||
        content.include?('implementation is complete') ||
        content.include?('successfully implemented') ||
        content.include?("perfect! i've created") ||
        content.include?("i've successfully created") ||
        content.include?("i've created a beautiful") ||
        content.include?("i've built a") ||
        content.include?("i've implemented") ||
        content.include?("with the following features:") ||
        content.include?("with the following amazing features:") ||
        content.include?("everything you need for") ||
        content.include?("the app includes everything")
      end
    end
    
    def should_terminate?(result)
      # Safety check for nil result
      return false if result.nil?
      
      # Check if Claude explicitly said the app is ready for preview
      app_ready_signal = check_for_completion_signal
      
      # Use termination evaluator
      termination_by_evaluator = @termination_evaluator.should_terminate?(@agent_state, result)
      status_complete = @completion_status == :complete
      intervention_required = @completion_status == :user_intervention_required
      high_confidence = (result[:verification] && result[:verification][:confidence] && result[:verification][:confidence] >= COMPLETION_CONFIDENCE_THRESHOLD)
      # Let Claude determine completion naturally through conversation
      natural_completion = @completion_status == :complete
      await_input = result[:action] == :await_user_input
      
      if app_ready_signal
        Rails.logger.info "[V5_LOOP] Termination: Claude signaled app is ready for preview"
        add_loop_message("✅ App generation complete - ready for deployment", type: 'status')
        @completion_status = :complete  # CRITICAL: Mark as complete so deployment happens
      elsif termination_by_evaluator
        Rails.logger.info "[V5_LOOP] Termination: evaluator said to stop"
      elsif status_complete
        Rails.logger.info "[V5_LOOP] Termination: status is complete"
      elsif intervention_required
        Rails.logger.info "[V5_LOOP] Termination: user intervention required"
      elsif high_confidence
        Rails.logger.info "[V5_LOOP] Termination: high confidence #{result[:verification][:confidence]}"
        @completion_status = :complete  # Mark as complete for high confidence scenarios
      elsif natural_completion
        Rails.logger.info "[V5_LOOP] Termination: natural completion achieved"
      elsif await_input
        Rails.logger.info "[V5_LOOP] Termination: awaiting user input"
      end
      
      app_ready_signal || termination_by_evaluator || status_complete || intervention_required || high_confidence || natural_completion || await_input
    end
    
    def finalize_app_generation
      Rails.logger.info "[V5_FINALIZE] Starting finalization, conversation_flow size: #{@assistant_message.conversation_flow&.size}"
      
      # Check if this is an update to an existing app with modified files
      is_app_update = @agent_state[:modified_files].any?
      if is_app_update
        Rails.logger.info "[V5_FINALIZE] This is an app update with #{@agent_state[:modified_files].count} modified files"
      end
      
      # Check if generation actually completed successfully
      if @completion_status == :failed || @completion_status == :error
        Rails.logger.warn "[V5_FINALIZE] Skipping deployment due to failed generation status: #{@completion_status}"
        app.update!(status: 'failed')
        return
      end
      
      # Only deploy if we have files AND generation completed successfully
      if app.app_files.count > 0 && @completion_status != :failed
        # Queue R2 content syncing for all app files (moved from inline callbacks)
        # This handles R2 storage in the background to keep generation fast
        Rails.logger.info "[V5_FINALIZE] Queueing R2 content sync for #{app.app_files.count} files"
        AppFilesInitializationJob.perform_later(app.id, { broadcast: true })
        
        # Setup R2 asset resolver integration before deployment
        update_thinking_status("Setting up asset management...")
        begin
          r2_integration = R2AssetIntegrationService.new(app)
          r2_integration.setup_complete_integration
          Rails.logger.info "[V5_FINALIZE] R2 asset integration completed"
          
          # Process all image URLs to create imageUrls.js for easy component access
          image_extractor = Ai::ImageUrlExtractorService.new(app)
          if image_extractor.process_all_images
            Rails.logger.info "[V5_FINALIZE] Image URLs processed and imageUrls.js created"
          end
        rescue => e
          Rails.logger.error "[V5_FINALIZE] R2 asset integration failed: #{e.message}"
          # Continue with deployment even if R2 setup fails
        end
        
        # Live Preview Infrastructure: Create instant preview environment (5-10s)
        update_thinking_status("Creating live preview environment...")
        begin
          Rails.logger.info "[V5_FINALIZE] Creating preview environment for app #{app.id}"
          
          # Start file watcher for hot reload
          Deployment::FileWatcherService.start_watching_app(app)
          
          # Always use real WFP preview service
          Rails.logger.info "[V5_FINALIZE] Using real WFP preview service"
          preview_service = Deployment::WfpPreviewService.new(app)
          result = preview_service.create_preview_environment
          
          if result && result[:success]
            Rails.logger.info "[V5_FINALIZE] WFP preview created successfully: #{result[:preview_url]}"
            Rails.logger.info "[V5_FINALIZE] Deployment time: #{result[:deployment_time]}s"
          else
            error_msg = result ? result[:error] : "Unknown error"
            Rails.logger.error "[V5_FINALIZE] WFP preview creation failed: #{error_msg}"
          end
          
        rescue => e
          Rails.logger.error "[V5_FINALIZE] Preview environment creation failed: #{e.message}"
          Rails.logger.error "[V5_FINALIZE] Backtrace: #{e.backtrace.first(5).join("\n")}"
          # Continue with deployment even if preview fails
        end
        
        # GitHub Migration Project: Setup repository with generated code BEFORE deployment
        if @use_repository_mode && !@app.using_repository_mode?
          update_thinking_status("Creating GitHub repository with generated code...")
          setup_github_repository_with_code
        end
        
        # Queue deployment job for async processing
        update_thinking_status("Phase 6/6: Queueing deployment")
        
        # Queue deployment for both new apps and updates
        if is_app_update
          Rails.logger.info "[V5_FINALIZE] Queueing deployment for app update"
        else
          Rails.logger.info "[V5_FINALIZE] Queueing deployment for new app generation"
        end
        
        deploy_result = deploy_app
        
        if deploy_result[:success]
          # Status will be updated by DeployAppJob when deployment completes
          # For now, keep it as 'generating' to show deployment is in progress
          Rails.logger.info "[V5_FINALIZE] Deployment queued with job ID: #{deploy_result[:job_id]}"
          
          # Broadcasting will be handled by DeployAppJob when deployment completes
          Rails.logger.info "[V5_FINALIZE] Preview frame will update when deployment completes"
          
          # Create AppVersion for the generated code
          app_version = create_app_version_for_generation
          
          Rails.logger.info "[V5_FINALIZE] Before finalize_with_app_version, conversation_flow size: #{@assistant_message.conversation_flow&.size}"
          
          # Preserve the conversation_flow explicitly
          preserved_flow = @assistant_message.conversation_flow || []
          
          # Update message content with success message (deployment is in progress)
          if is_app_update
            @assistant_message.content = "✨ Your app has been updated successfully!\n\n📦 **Version**: #{app_version.version_number}\n📁 **Files Modified**: #{@agent_state[:modified_files].count}\n\n🚀 **Deployment Status**: In progress...\n\nThe preview will refresh automatically once deployment completes."
          else
            @assistant_message.content = "✨ Your app has been generated successfully!\n\n📦 **Version**: #{app_version.version_number}\n📁 **Files Created**: #{app_version.app_version_files.count}\n\n🚀 **Deployment Status**: In progress...\n\nThe preview will be available once deployment completes."
          end
          @assistant_message.conversation_flow = preserved_flow
          
          # Finalize with app_version (sets is_code_generation=true and associates version)
          finalize_with_app_version(app_version)
          
          Rails.logger.info "[V5_FINALIZE] After finalize_with_app_version, app_version: #{@assistant_message.reload.app_version_id}, is_code_generation: #{@assistant_message.is_code_generation}"
        else
          app.update!(status: 'failed')
          # Preserve the conversation_flow explicitly
          preserved_flow = @assistant_message.conversation_flow || []
          
          @assistant_message.update!(
            thinking_status: nil,
            status: 'failed',
            content: "Deployment failed: #{deploy_result[:error]}",
            conversation_flow: preserved_flow  # Explicitly preserve
          )
        end
      else
        app.update!(status: 'failed')
        # Preserve the conversation_flow explicitly
        preserved_flow = @assistant_message.conversation_flow || []
        
        # Check if files were created even though generation is incomplete
        files_created = app.app_files.count
        if files_created > 0
          @assistant_message.update!(
            thinking_status: nil,
            status: 'failed',
            content: "⚠️ Generation stopped after #{@iteration_count} iterations.\n\n#{files_created} files were created but the app may be incomplete. You can try continuing the generation or start fresh.",
            conversation_flow: preserved_flow  # Explicitly preserve
          )
        else
          @assistant_message.update!(
            thinking_status: nil,
            status: 'failed',
            content: "Generation could not be completed. Please try again with a clearer description of what you'd like to build.",
            conversation_flow: preserved_flow  # Explicitly preserve
          )
        end
      end
    end
    
    # Queue deployment via DeployAppJob or use fast preview with EdgePreviewService
    def deploy_app
      Rails.logger.info "[V5_DEPLOY] Starting deployment for app #{@app.id}"
      
      # Fast preview is now the default (can be disabled by setting FAST_PREVIEW_ENABLED=false)
      if ENV['FAST_PREVIEW_ENABLED'] != 'false'
        Rails.logger.info "[V5_FAST_DEPLOY] Using EdgePreviewService for instant preview deployment (default)"
        deploy_fast_preview
      else
        Rails.logger.info "[V5_DEPLOY] Using legacy standard deployment pipeline (FAST_PREVIEW_ENABLED=false)"
        deploy_standard
      end
    end
    
    # Fast preview deployment using EdgePreviewService (5-10s)
    def deploy_fast_preview
      Rails.logger.info "[V5_FAST_DEPLOY] Starting fast preview deployment for app #{@app.id}"
      
      # Broadcast initial fast deployment progress
      broadcast_deployment_progress(
        status: 'deploying',
        progress: 10,
        phase: 'Initializing fast preview...',
        deployment_type: 'fast_preview',
        deployment_steps: [
          { name: 'Bundle with Vite', current: true, completed: false },
          { name: 'Deploy to Edge', current: false, completed: false },
          { name: 'Enable HMR', current: false, completed: false }
        ]
      )
      
      begin
        # Use EdgePreviewService for instant deployment
        service = EdgePreviewService.new(@app)
        
        # Build and deploy in one step
        broadcast_deployment_progress(
          status: 'deploying',
          progress: 40,
          phase: 'Building with Vite...',
          deployment_steps: [
            { name: 'Bundle with Vite', current: true, completed: false },
            { name: 'Deploy to Edge', current: false, completed: false },
            { name: 'Enable HMR', current: false, completed: false }
          ]
        )
        
        result = service.deploy_preview do |progress|
          # Update progress during deployment
          broadcast_deployment_progress(
            status: 'deploying',
            progress: 40 + (progress * 0.4).to_i,
            phase: 'Deploying to edge...',
            deployment_steps: [
              { name: 'Bundle with Vite', current: false, completed: true },
              { name: 'Deploy to Edge', current: true, completed: false },
              { name: 'Enable HMR', current: false, completed: false }
            ]
          )
        end
        
        if result[:success]
          @app.update!(
            preview_url: result[:preview_url],
            status: 'ready'
          )
          
          # Final success broadcast
          broadcast_deployment_progress(
            status: 'deployed',
            progress: 100,
            phase: 'Preview ready with HMR!',
            deployment_url: result[:preview_url],
            deployment_steps: [
              { name: 'Bundle with Vite', current: false, completed: true },
              { name: 'Deploy to Edge', current: false, completed: true },
              { name: 'Enable HMR', current: false, completed: true }
            ]
          )
          
          Rails.logger.info "[V5_FAST_DEPLOY] Successfully deployed to #{result[:preview_url]} in #{result[:deploy_time_ms]}ms"
          
          # Queue GitHub sync as a non-blocking background job
          GitHubSyncJob.set(wait: 5.seconds).perform_later(@app.id) if defined?(GitHubSyncJob)
          
          {
            success: true,
            message: "Fast preview deployed in #{result[:deploy_time_ms]}ms",
            preview_url: result[:preview_url]
          }
        else
          raise "Fast deployment failed: #{result[:error]}"
        end
        
      rescue => e
        Rails.logger.error "[V5_FAST_DEPLOY] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        # Fall back to standard deployment
        Rails.logger.info "[V5_FAST_DEPLOY] Falling back to standard deployment"
        deploy_standard
      end
    end
    
    # Standard deployment via DeployAppJob (3-5 minutes)
    def deploy_standard
      Rails.logger.info "[V5_DEPLOY] Queueing standard deployment job for app #{@app.id}"
      
      # Broadcast initial deployment progress
      broadcast_deployment_progress(
        status: 'deploying',
        progress: 0,
        phase: 'Queuing deployment...',
        deployment_type: 'preview',
        deployment_steps: [
          { name: 'Build app', current: false, completed: false },
          { name: 'Deploy to Cloudflare', current: false, completed: false },
          { name: 'Configure routes', current: false, completed: false },
          { name: 'Setup environment', current: false, completed: false }
        ]
      )
      
      # FIX: Actually queue the DeployAppJob now that generation is complete
      # The comment was misleading - we need to trigger deployment here
      Rails.logger.info "[V5_DEPLOY] Queueing DeployAppJob for app #{@app.id}"
      
      # Queue deployment with a small delay to ensure all database writes are committed
      job = DeployAppJob.set(wait: 5.seconds).perform_later(@app.id, "production")
      job_id = job.job_id if job.respond_to?(:job_id)
      
      Rails.logger.info "[V5_DEPLOY] DeployAppJob queued with ID: #{job_id}"
      
      # Return success with job ID for tracking
      {
        success: true,
        message: "Generation complete, deployment queued",
        job_id: job_id,
        preview_url: @app.preview_url # Return existing URL if available
      }
    rescue => e
      Rails.logger.error "[V5_DEPLOY] Failed to queue deployment: #{e.message} #{e.backtrace.join("\n")}"
      # Broadcast deployment failure
      broadcast_deployment_progress(
        status: 'failed',
        deployment_error: e.message
      )
      { success: false, error: e.message }
    end
    
    # Original synchronous deployment method (kept for reference/fallback)
    def deploy_app_sync
      # Ensure postcss.config.js exists with proper ES module format
      ensure_postcss_config
      
      # Validate imports before building
      import_errors = validate_imports
      if import_errors.any?
        Rails.logger.warn "[V5_DEPLOY] Import validation failed: #{import_errors.join('; ')}"
        
        # First attempt: Fix imports automatically
        auto_fix_success = auto_fix_imports(import_errors)
        
        if auto_fix_success
          Rails.logger.info "[V5_DEPLOY] Successfully auto-fixed import errors"
          # Re-validate after auto fix
          import_errors = validate_imports
          if import_errors.empty?
            Rails.logger.info "[V5_DEPLOY] All import errors resolved automatically"
          else
            Rails.logger.warn "[V5_DEPLOY] Some import errors remain after auto-fix: #{import_errors.join('; ')}"
          end
        end
        
        # If auto-fix didn't resolve all errors, try AI as fallback
        if import_errors.any?
          Rails.logger.info "[V5_DEPLOY] Falling back to AI import fixing"
          ai_fix_success = send_import_errors_to_ai(import_errors)
          
          if !ai_fix_success
            return { success: false, error: "Import validation failed: #{import_errors.first}" }
          end
          
          # Re-validate after AI fix
          import_errors = validate_imports
          if import_errors.any?
            return { success: false, error: "Import validation still failing after fix attempt: #{import_errors.first}" }
          end
        end
      end
      
      # Build the app with R2 asset optimization
      builder = Deployment::ExternalViteBuilder.new(app)
      build_result = builder.build_for_preview_with_r2
      
      unless build_result[:success]
        return { success: false, error: build_result[:error] }
      end
      
      Rails.logger.info "[V5_DEPLOY] Build completed with R2 optimization: #{build_result[:size_stats][:r2_assets_count]} assets uploaded"
      
      # Deploy to Cloudflare with R2 asset URLs
      deployer = Deployment::CloudflareWorkersDeployer.new(app)
      deploy_result = deployer.deploy_with_secrets(
        built_code: build_result[:built_code],
        r2_asset_urls: build_result[:r2_asset_urls],
        deployment_type: :preview
      )
      
      if deploy_result[:success]
        # Clear Cloudflare cache to ensure fresh content is served
        Rails.logger.info "[V5_DEPLOY] Clearing Cloudflare cache for fresh deployment"
        cache_result = deployer.clear_cache(:preview)
        
        if cache_result[:success]
          Rails.logger.info "[V5_DEPLOY] Cache cleared successfully"
        else
          Rails.logger.warn "[V5_DEPLOY] Cache clear failed: #{cache_result[:error]}"
        end
        
        # Update app with preview URL so preview frame can display it
        preview_url = deploy_result[:worker_url]
        @app.update!(preview_url: preview_url, status: 'generated')
        Rails.logger.info "[V5_DEPLOY] Updated app preview_url: #{preview_url}"
        
        # Broadcast preview frame update when app is deployed
        begin
          if @app&.preview_url.present?
          
            Rails.logger.info "[V5_BROADCAST] Broadcasting preview frame update for app #{@app.id}"
            
            # Broadcast to the app channel that users are subscribed to
            Turbo::StreamsChannel.broadcast_replace_to(
              "app_#{@app.id}",
              target: "preview_frame",
              partial: "account/app_editors/preview_frame",
              locals: { app: @app }
            )
            
            # Also broadcast a refresh action to the chat channel for better UX
            Turbo::StreamsChannel.broadcast_action_to(
              "app_#{@app.id}_chat",
              action: "refresh",
              target: "preview_frame"
            )
          end
        rescue => e
          Rails.logger.error "[V5_BROADCAST] Failed to broadcast preview frame update: #{e.message}"
        end
        
        { 
          success: true, 
          preview_url: preview_url,
          cache_cleared: cache_result[:success]
        }
      else
        { 
          success: false, 
          error: deploy_result[:error]
        }
      end
    rescue => e
      Rails.logger.error "[V5_DEPLOY] Error: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Validate that all component imports are present
    def validate_imports
      errors = []
      
      # HTML elements and React built-ins that don't need imports
      html_elements = %w[div span section article main header footer nav aside p h1 h2 h3 h4 h5 h6 
                        a ul ol li button input form label select option textarea img svg path
                        table thead tbody tr td th pre code strong em small iframe video audio
                        canvas details summary dialog template slot]
      
      react_builtins = %w[Fragment StrictMode Suspense]
      
      # TypeScript types and internal references that don't need imports
      ts_types = %w[HTMLDivElement HTMLButtonElement HTMLInputElement HTMLTextAreaElement 
                    HTMLTableElement HTMLTableSectionElement HTMLTableRowElement HTMLTableCellElement
                    HTMLTableCaptionElement HTMLHeadingElement HTMLParagraphElement HTMLSpanElement
                    HTMLAnchorElement HTMLImageElement HTMLFormElement HTMLSelectElement
                    HTMLUListElement HTMLLIElement HTMLOListElement HTMLElement KeyboardEvent
                    VariantProps BadgeProps ButtonProps CalendarProps CommandDialogProps
                    SheetContentProps ToasterProps TextareaProps ToastProps ToastActionElement
                    UseEmblaCarouselType CarouselApi UseCarouselParameters CarouselOptions
                    CarouselPlugin CarouselProps ChartConfig PaginationLinkProps TName TFieldValues]
      
      # Common internal/context values that are defined in same file
      internal_refs = %w[Comp FormField FormFieldContextValue FormItemContextValue ChartContextProps
                         ChartStyle CarouselContextProps DialogPortal SheetPortal DrawerPortal
                         AlertDialogPortal TFieldValues ResizablePanelGroup ResizableHandle
                         CommandDialog Skeleton Badge BrowserRouter Toaster]
      
      # Common words from comments/strings that aren't components
      common_words = %w[This We Helper Adds Tailwind Adjust Increases Random Initialize RLS Error
                       Go Home Background Hero Offer Creation Platform Main That Convert Subheadline
                       Transform Build CTA Buttons Start Your Free Trial Watch Demo Social Conversion
                       Decorative Our Maximize See SOC Share OfferLab Handle Everything You Need More
                       Powerful Hover Simple Choose All Most Popular No Cancel We The Marketing ROI
                       Highly Loved Rating Author Trust Average Happy Ready Headline Join Schedule
                       Bottom In Mobile Brand Create Product Company Resources Legal Sign Desktop
                       Navigation Features Pricing Reviews OverSkill Branding Get URL Earn
                       SIDEBAR_COOKIE_NAME SIDEBAR_COOKIE_MAX_AGE SIDEBAR_WIDTH SIDEBAR_WIDTH_MOBILE
                       SIDEBAR_WIDTH_ICON SIDEBAR_KEYBOARD_SHORTCUT CSS_SELECTOR THEMES
                       MOBILE_BREAKPOINT Icon]
      
      app.app_files.where("path LIKE '%.tsx' OR path LIKE '%.jsx'").each do |file|
        next if file.path.include?('test') || file.path.include?('spec')
        
        content = file.content
        
        # Find all JSX component usage (CapitalCase tags)
        used_components = content.scan(/<([A-Z]\w+)/).flatten.uniq
        
        # ENHANCED: Also find components used as values (not in JSX)
        # Only in specific patterns to avoid false positives:
        # 1. Object property: { icon: Component }
        # 2. Array literal: [Component, OtherComponent]  
        # 3. Function argument: doSomething(Component)
        value_components = []
        
        # Pattern 1: Object property with colon (e.g., { icon: Zap })
        # Must be CamelCase (capital followed by lowercase)
        value_components.concat(content.scan(/:\s*([A-Z][a-z]\w*)(?=\s*[,}])/).flatten)
        
        # Pattern 2: Array of components (e.g., [Zap, Target])
        value_components.concat(content.scan(/\[\s*([A-Z][a-z]\w*)(?:\s*,\s*[A-Z][a-z]\w*)*\s*\]/).flatten)
        
        # Pattern 3: Function arguments that look like components
        value_components.concat(content.scan(/\(\s*([A-Z][a-z]\w*)\s*\)/).flatten)
        
        value_components.uniq!
        
        # Find local variables that hold components dynamically
        # e.g., const Icon = feature.icon or const Comp = items[0]
        dynamic_vars = content.scan(/const\s+(\w+)\s*=\s*\w+\.\w+/).flatten
        dynamic_vars += content.scan(/const\s+(\w+)\s*=\s*\w+\[/).flatten
        dynamic_vars += content.scan(/let\s+(\w+)\s*=\s*\w+\.\w+/).flatten
        
        # Combine all potential component references
        all_potential_components = (used_components + value_components).uniq
        
        # Remove dynamic variables from the check (they're not imports)
        all_potential_components.reject! { |comp| dynamic_vars.include?(comp) }
        
        # Find all imports
        imported_components = []
        
        # Standard imports: import { Component } from
        content.scan(/import\s*{([^}]+)}\s*from/).each do |imports|
          imported_components.concat(imports[0].split(',').map(&:strip))
        end
        
        # Default imports: import Component from
        content.scan(/import\s+([A-Z]\w+)\s+from/).each do |import|
          imported_components << import[0]
        end
        
        # Namespace imports: import * as Something
        content.scan(/import\s+\*\s+as\s+(\w+)/).each do |import|
          imported_components << import[0]
        end
        
        # Find missing components (use all potential components, not just JSX)
        missing = all_potential_components - imported_components - html_elements - react_builtins - ts_types - internal_refs - common_words
        
        # Check for components that might be from destructured namespace imports
        missing.reject! do |comp|
          # Check if it's used as Namespace.Component
          content.include?("#{comp}.") || 
          # Check if there's a matching import path
          content.match?(/from\s+['"].*#{comp.downcase}['"]/) ||
          # Skip platform-specific components
          comp == 'OverSkillBadge' || comp == 'Router' ||
          # Skip if it's a type reference (used in extends/implements)
          content.match?(/extends\s+#{comp}/) ||
          content.match?(/implements\s+#{comp}/)
        end
        
        if missing.any?
          errors << "#{file.path}: Missing imports for #{missing.join(', ')}"
          Rails.logger.warn "[V5_IMPORT_CHECK] #{file.path} missing: #{missing.join(', ')}"
        end
      end
      
      errors
    end
    
    # Automatically fix import errors without AI intervention
    def auto_fix_imports(errors)
      Rails.logger.info "[V5_AUTO_FIX] Attempting to automatically fix #{errors.count} import errors"
      
      success_count = 0
      
      errors.each do |error|
        begin
          # Parse the error: "src/components/FeaturesSection.tsx: Missing imports for Badge, Button"
          file_path = error.split(":").first.strip
          missing_components = error.split("Missing imports for ").last.split(", ").map(&:strip)
          
          # Find the app file
          app_file = app.app_files.find_by(path: file_path)
          unless app_file
            Rails.logger.warn "[V5_AUTO_FIX] Could not find app file: #{file_path}"
            next
          end
          
          original_content = app_file.content
          updated_content = original_content.dup
          
          # Find the import section (after React import, before other code)
          react_import_match = updated_content.match(/(import React[^;]+;)/)
          unless react_import_match
            Rails.logger.warn "[V5_AUTO_FIX] Could not find React import in #{file_path}"
            next
          end
          
          react_import_line = react_import_match[1]
          
          # Generate import statements for missing components
          new_imports = missing_components.map do |component|
            generate_import_statement_for_component(component)
          end.join("\n")
          
          # Insert new imports after React import
          updated_content = updated_content.sub(
            react_import_line,
            "#{react_import_line}\n#{new_imports}"
          )
          
          # Update the file
          app_file.update!(content: updated_content)
          @agent_state[:modified_files][file_path] = {
            original_content: original_content,
            new_content: updated_content,
            timestamp: Time.current
          }
          
          Rails.logger.info "[V5_AUTO_FIX] Fixed imports in #{file_path}: #{missing_components.join(', ')}"
          success_count += 1
          
        rescue => e
          Rails.logger.error "[V5_AUTO_FIX] Error fixing imports in #{file_path}: #{e.message}"
          Rails.logger.error "[V5_AUTO_FIX] Backtrace: #{e.backtrace&.first(3)&.join("\n")}"
        end
      end
      
      if success_count > 0
        Rails.logger.info "[V5_AUTO_FIX] Successfully fixed imports in #{success_count}/#{errors.count} files"
        # Update assistant message with auto-fix status  
        if @assistant_message
          current_content = @assistant_message.content || ''
          auto_fix_note = "\n\n✅ Auto-fixed #{success_count} import error#{success_count == 1 ? '' : 's'}"
          @assistant_message.update!(content: current_content + auto_fix_note)
        end
        return true
      else
        Rails.logger.warn "[V5_AUTO_FIX] Failed to automatically fix any import errors"
        return false
      end
    end
    
    # Generate exact import statement for a missing component
    def generate_import_statement_for_component(component)
      case component
      # shadcn/ui components
      when 'Badge'
        "import { Badge } from '@/components/ui/badge';"
      when 'Button'  
        "import { Button } from '@/components/ui/button';"
      when 'Card'
        "import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';"
      when 'Dialog'
        "import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog';"
      when 'Sheet'
        "import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from '@/components/ui/sheet';"
      when 'Tabs'
        "import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';"
      when 'Input'
        "import { Input } from '@/components/ui/input';"
      when 'Label'
        "import { Label } from '@/components/ui/label';"
      when 'Select'
        "import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';"
      when 'Textarea'
        "import { Textarea } from '@/components/ui/textarea';"
      when 'Checkbox'
        "import { Checkbox } from '@/components/ui/checkbox';"
      when 'Avatar'
        "import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';"
      when 'Alert'
        "import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';"
      when 'Toast'
        "import { Toast } from '@/components/ui/toast';"
      # Lucide React icons - check if it's a known icon
      when /^[A-Z][a-zA-Z]+$/ # CapitalCase pattern for icons
        if is_lucide_icon?(component)
          "import { #{component} } from 'lucide-react';"
        else
          # Default to shadcn component with lowercase path
          component_path = component.gsub(/([A-Z])/, '-\\1').downcase.sub(/^-/, '')
          "import { #{component} } from '@/components/ui/#{component_path}';"
        end
      else
        # Default fallback
        "import { #{component} } from '@/components/ui/#{component.downcase}';"
      end
    end
    
    # Check if component is a valid Lucide React icon
    def is_lucide_icon?(component)
      # Comprehensive list of Lucide React icons (commonly used)
      common_icons = %w[
        Menu X ChevronDown ChevronUp ChevronLeft ChevronRight ArrowLeft ArrowRight 
        ArrowUp ArrowDown Check Plus Minus Edit Trash Save Download Upload Share Copy
        Search Filter Calendar Clock User Users Settings Bell Home Star Heart
        Mail Phone Globe Shield Lock CreditCard DollarSign Zap Crown Rocket Award
        Trophy TrendingUp TrendingDown BarChart LineChart PieChart Play Pause Volume
        Camera Image Video File Folder Cloud Upload2 Download2 ExternalLink
        Github Twitter Linkedin Facebook Instagram Youtube MapPin
        Target Sparkles Sun Moon CloudRain CloudSnow Wind Droplet Thermometer
        Activity Airplay Anchor Aperture Archive BarChart2 Bold Book Box Briefcase
        Compass Code Coffee Command Crosshair Disc Divide Feather Grid Hexagon
        Layers Layout LifeBuoy Map Maximize Minimize Move Navigation Package Package2
        PenTool Percent Power Sliders Square Terminal Tool Type Umbrella Underline
        Unlock Cpu Monitor Smartphone Tablet Watch Headphones Speaker Printer Mouse
        Keyboard HardDrive AlertCircle Info CheckCircle XCircle AlertTriangle
        HelpCircle Loader RefreshCw RotateCw Send LogIn LogOut UserPlus UserMinus
        UserCheck UserX ShoppingCart ShoppingBag Gift Bookmark Tag Hash AtSign Link
        Paperclip Mic SkipForward SkipBack Repeat Shuffle Music Film Radio Tv Wifi
        Battery Bluetooth Cast Database Server Eye EyeOff ThumbsUp MessageCircle
      ]
      
      common_icons.include?(component)
    end
    
    # Send import errors to AI for fixing
    def send_import_errors_to_ai(errors)
      Rails.logger.info "[V5_IMPORT_FIX] Sending import errors to AI for fixing"
      
      # Create a detailed error message for the AI with specific import fixes
      error_message = "CRITICAL: Fix these missing imports immediately using os-line-replace tool:\n\n"
      
      errors.each do |error|
        file_path = error.split(":").first
        missing_components = error.split("Missing imports for ").last.split(", ")
        
        error_message += "**File: #{file_path}**\n"
        missing_components.each do |component|
          import_statement = generate_import_statement_for_component(component.strip)
          error_message += "• Add: `#{import_statement}`\n"
        end
        error_message += "\n"
      end
      
      error_message += "**EXACT INSTRUCTIONS:**\n" +
        "1. Use os-line-replace tool for each file\n" +
        "2. Find the existing import section (after React import)\n" +
        "3. Add the missing import statements in the exact format shown above\n" +
        "4. Place UI component imports before custom component imports\n" +
        "5. CRITICAL: Use the EXACT import statements provided - do not modify them\n\n" +
        "**Example os-line-replace usage:**\n" +
        "```\n" +
        "os-line-replace path/to/file.tsx \"import React from 'react';\" \"import React from 'react';\nimport { Badge } from '@/components/ui/badge';\"\n" +
        "```"
      
      # Create a user message in the chat
      fix_message = app.app_chat_messages.create!(
        user: @chat_message.user,
        team: app.team,
        role: 'user',
        content: error_message,
        status: 'sent'
      )
      
      # Create assistant message for the fix attempt
      fix_assistant_message = app.app_chat_messages.create!(
        user: @chat_message.user,
        team: app.team,
        role: 'assistant',
        content: '',
        status: 'executing'
      )
      
      # Store current assistant message and replace it temporarily
      original_assistant_message = @assistant_message
      @assistant_message = fix_assistant_message
      
      begin
        # Store initial state to detect changes
        initial_files_count = @agent_state[:generated_files].count
        initial_modified_files = @agent_state[:modified_files].dup
        
        # Let AI process the fix using the standard flow
        response = call_ai_with_context(error_message)
        
        # Check if AI made any file changes
        files_added = @agent_state[:generated_files].count > initial_files_count
        files_modified = @agent_state[:modified_files].keys != initial_modified_files.keys
        files_changed = files_added || files_modified
        
        if files_changed
          changes_summary = "Added #{@agent_state[:generated_files].count - initial_files_count} files, modified #{@agent_state[:modified_files].keys.size - initial_modified_files.keys.size} files"
          Rails.logger.info "[V5_IMPORT_FIX] AI successfully made changes: #{changes_summary}"
          fix_assistant_message.update!(status: 'complete', content: "Fixed missing imports: #{changes_summary}")
          return true
        else
          Rails.logger.warn "[V5_IMPORT_FIX] AI did not make any file changes (initial_files: #{initial_files_count}, current_files: #{@agent_state[:generated_files].count})"
          Rails.logger.warn "[V5_IMPORT_FIX] Initial modified files: #{initial_modified_files.keys.join(', ')}"
          Rails.logger.warn "[V5_IMPORT_FIX] Current modified files: #{@agent_state[:modified_files].keys.join(', ')}"
          fix_assistant_message.update!(status: 'failed', content: "Could not fix the import errors automatically")
          return false
        end
      ensure
        # Restore original assistant message
        @assistant_message = original_assistant_message
      end
    rescue => e
      Rails.logger.error "[V5_IMPORT_FIX] Error sending to AI: #{e.message}"
      fix_assistant_message&.update!(status: 'failed', content: "Error: #{e.message}")
      return false
    end
    
    # Ensure postcss.config.js exists with proper ES module format
    # This prevents parent project's postcss.config.js from interfering
    def ensure_postcss_config
      postcss_file = app.app_files.find_or_initialize_by(path: 'postcss.config.js')
      
      # Only update if it doesn't exist or has wrong format
      if postcss_file.new_record? || postcss_file.content.include?('module.exports')
        Rails.logger.info "[V5_BUILD_FIX] Creating/fixing postcss.config.js with ES module format"
        postcss_file.update!(
          content: "export default { plugins: {} };",
          team: app.team
        )
      end
    end
    
    def call_ai_with_context(prompt)
      log_claude_event("API_CALL_START", {
        iteration: @iteration_count,
        prompt_preview: prompt.to_s[0..200]
      })
      
      # Use Anthropic client singleton with caching
      client = Ai::AnthropicClient.instance
      
      messages = build_messages_with_context(prompt)
      tools = @prompt_service.generate_tools
      
      log_claude_event("API_CALL_MESSAGES", {
        message_count: messages.size,
        tool_count: tools.size,
        first_msg_role: messages.first&.dig(:role),
        last_msg_role: messages.last&.dig(:role)
      })
      
      # Debug: log actual messages content
      Rails.logger.debug "[V5_DEBUG] Messages being sent to Claude:"
      messages.each_with_index do |msg, i|
        Rails.logger.debug "[V5_DEBUG]   Message #{i}: role=#{msg[:role]}, content_length=#{msg[:content]&.length}"
      end
      
      # Generate Helicone session for tracking with proper path hierarchy
      helicone_session = "overskill-v5-#{@app.id}-#{Time.current.to_i}"
      helicone_path = "/app-#{@app.id}/generation"
      
      # CRITICAL FIX: Implement proper tool calling cycle with result feedback
      final_response = execute_tool_calling_cycle(client, messages, tools, helicone_session, helicone_path)
      
      log_claude_event("API_CALL_COMPLETE", {
        final_content: final_response[:content].present?,
        thinking_blocks: final_response[:thinking_blocks]&.size || 0,
        tool_cycles: final_response[:tool_cycles] || 0
      })
      
      final_response
    end

    # CRITICAL FIX: Implement proper tool calling cycle according to Anthropic docs
    def execute_tool_calling_cycle(client, messages, tools, helicone_session, helicone_path = nil)
      # Check if incremental streaming is enabled
      if @incremental_streaming_enabled
        Rails.logger.info "[V5_INCREMENTAL] Using incremental tool streaming"
        return execute_tool_calling_cycle_incremental(client, messages, tools, helicone_session, helicone_path)
      end
      
      # Fallback to traditional streaming
      conversation_messages = messages.dup
      tool_cycles = 0
      max_tool_cycles = 30  # Prevent infinite loops
      response = nil  # Define response outside the loop
      content_added_to_flow = false  # Track whether we've added current response content
      
      # Log initial message structure
      system_msg = conversation_messages.find { |m| m[:role] == 'system' }
      Rails.logger.info "[V5_TOOLS] Initial messages: #{conversation_messages.size} total, system_prompt: #{system_msg.present?}"
      if system_msg
        Rails.logger.info "[V5_TOOLS] System prompt type: #{system_msg[:content].is_a?(Array) ? 'array' : 'string'}"
        if system_msg[:content].is_a?(Array)
          Rails.logger.info "[V5_TOOLS] System prompt blocks: #{system_msg[:content].map { |b| b[:type] }.join(', ')}"
        end
      end
      
      loop do
        # Reset content tracking for each new API response
        content_added_to_flow = false
        
        # Log messages being sent to API
        Rails.logger.info "[V5_TOOLS] API Call #{tool_cycles + 1}: Sending #{conversation_messages.size} messages"
        Rails.logger.info "[V5_TOOLS] Message roles: #{conversation_messages.map { |m| m[:role] }.join(' -> ')}"
        
        # Validate conversation structure before API call (only in verbose mode)
        if ENV["VERBOSE_AI_LOGGING"] == "true" && conversation_messages.size >= 2
          validate_tool_calling_structure(conversation_messages)
        end
        
        # Make API call to Claude
        begin
          response = client.chat_with_tools(
            conversation_messages,
            tools,
            model: :claude_sonnet_4,
            stream: @api_streaming_enabled,
            use_cache: true,
            temperature: 0.7,
            max_tokens: 48000,
            helicone_session: helicone_session,
            helicone_path: "#{helicone_path || '/app-generation'}/cycle-#{tool_cycles}",
            extended_thinking: false, # Testing costs around thinking vs non TODO: evaluate more
            thinking_budget: 16000
          )
        rescue => e
          log_claude_event("API_CALL_ERROR", {
            error: e.message,
            class: e.class.name
          })
          raise e
        end
        
        # Handle different stop reasons
        stop_reason = response[:stop_reason] || 'stop'
        
        case stop_reason
        when 'tool_use'
          # Claude wants to use tools - execute them and continue conversation
          if response[:tool_calls].present?
            Rails.logger.info "[V5_TOOLS] Claude made #{response[:tool_calls].size} tool calls"
            
            # CRITICAL: Add text content to conversation_flow BEFORE tools
            if response[:content].present?
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
              content_added_to_flow = true  # Mark that we've added this response content
              Rails.logger.info "[V5_TOOLS] Added text content to conversation_flow before tools"
            end
            
            # CRITICAL: Add Claude's tool_use message to conversation history FIRST
            assistant_message = {
              role: 'assistant',
              content: build_assistant_content_with_tools(response)
            }
            conversation_messages << assistant_message
            
            # Log the assistant message structure for verification
            if ENV["VERBOSE_AI_LOGGING"] == "true"
              Rails.logger.info "[V5_TOOLS] Assistant tool_use message added:"
              assistant_message[:content].each do |block|
                if block[:type] == 'tool_use'
                  Rails.logger.info "  - tool_use: id=#{block[:id]}, name=#{block[:name]}"
                end
              end
            end
            
            # Execute all tool calls and collect results
            tool_results = execute_and_format_tool_results(response[:tool_calls])
            
            # CRITICAL: Add tool results as user message with correct formatting
            # Tool results MUST come FIRST in content array (per Anthropic docs)
            user_message = {
              role: 'user',
              content: tool_results  # All tool results in single message
            }
            conversation_messages << user_message
            
            # Log the user message structure for verification
            if ENV["VERBOSE_AI_LOGGING"] == "true"
              Rails.logger.info "[V5_TOOLS] User tool_result message added:"
              user_message[:content].each do |block|
                if block[:type] == 'tool_result'
                  Rails.logger.info "  - tool_result: tool_use_id=#{block[:tool_use_id]}, has_content=#{block[:content].present?}"
                end
              end
              Rails.logger.info "[V5_TOOLS] Conversation now has #{conversation_messages.size} messages"
            end
            
            tool_cycles += 1
            
            # Safety check for infinite tool loops
            if tool_cycles >= max_tool_cycles
              Rails.logger.warn "[V5_TOOLS] Max tool cycles reached (#{max_tool_cycles})"
              # Create a response indicating we hit the limit
              response[:content] = "I've completed multiple rounds of file operations. The app structure has been updated." if response[:content].blank?
              response[:stop_reason] = 'max_tool_cycles'
              break
            end
            
            # Continue the loop to get Claude's next response
            next
          else
            Rails.logger.warn "[V5_TOOLS] Stop reason 'tool_use' but no tool calls found"
            break
          end
          
        when 'max_tokens'
          # Response was truncated - need to handle this
          Rails.logger.warn "[V5_TOOLS] Response truncated (max_tokens reached)"
          last_content = response[:content]
          if last_content && last_content.end_with?('...')
            # Attempt to continue with higher token limit
            Rails.logger.info "[V5_TOOLS] Attempting to continue truncated response"
            # TODO: Implement truncation recovery
          end
          break
          
        when 'stop', 'end_turn'
          # CRITICAL FIX: API streaming sets stop_reason='stop' even with tool calls
          # Check for tool calls even when stop_reason is 'stop'
          if response[:tool_calls].present?
            Rails.logger.info "[V5_TOOLS] STREAMING FIX: Found #{response[:tool_calls].size} tool calls with stop_reason='stop'"
            
            # CRITICAL: Add text content to conversation_flow BEFORE tools
            if response[:content].present?
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
              content_added_to_flow = true  # Mark that we've added this response content
              Rails.logger.info "[V5_TOOLS] Added text content to conversation_flow before tools"
            end
            
            # CRITICAL: Add Claude's tool_use message to conversation history FIRST
            assistant_message = {
              role: 'assistant',
              content: build_assistant_content_with_tools(response)
            }
            conversation_messages << assistant_message
            
            # Log the assistant message structure for verification
            if ENV["VERBOSE_AI_LOGGING"] == "true"
              Rails.logger.info "[V5_TOOLS] Assistant tool_use message added:"
              assistant_message[:content].each do |block|
                if block[:type] == 'tool_use'
                  Rails.logger.info "  - tool_use: id=#{block[:id]}, name=#{block[:name]}"
                end
              end
            end
            
            # Execute all tool calls and collect results
            tool_results = execute_and_format_tool_results(response[:tool_calls])
            
            # CRITICAL: Add tool results as user message with correct formatting
            # Tool results MUST come FIRST in content array (per Anthropic docs)
            user_message = {
              role: 'user',
              content: tool_results  # All tool results in single message
            }
            conversation_messages << user_message
            
            # Log the user message structure for verification
            if ENV["VERBOSE_AI_LOGGING"] == "true"
              Rails.logger.info "[V5_TOOLS] User tool_result message added:"
              user_message[:content].each do |block|
                if block[:type] == 'tool_result'
                  Rails.logger.info "  - tool_result: tool_use_id=#{block[:tool_use_id]}, has_content=#{block[:content].present?}"
                end
              end
              Rails.logger.info "[V5_TOOLS] Conversation now has #{conversation_messages.size} messages"
            end
            
            tool_cycles += 1
            
            # Safety check for infinite tool loops
            if tool_cycles >= max_tool_cycles
              Rails.logger.warn "[V5_TOOLS] Max tool cycles reached (#{max_tool_cycles})"
              # Create a response indicating we hit the limit
              response[:content] = "I've completed multiple rounds of file operations. The app structure has been updated." if response[:content].blank?
              response[:stop_reason] = 'max_tool_cycles'
              break
            end
            
            # Continue the loop to get Claude's next response
            next
          else
            # Claude finished normally without tool calls
            Rails.logger.info "[V5_TOOLS] Claude completed response normally without tool calls"
            
            # Add text content to conversation_flow if present and not already added
            if response[:content].present? && !content_added_to_flow
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
              Rails.logger.info "[V5_TOOLS] Added final text content to conversation_flow"
            elsif content_added_to_flow
              Rails.logger.info "[V5_TOOLS] Skipped adding text content - already added before tools"
            end
            
            break
          end
          
        else
          Rails.logger.warn "[V5_TOOLS] Unknown stop reason: #{stop_reason}"
          break
        end
      end
      
      # Return final response with tool cycle count
      # Handle case where response might be nil if we never got a successful API call
      if response.nil?
        Rails.logger.error "[V5_TOOLS] No response available after tool cycles"
        { success: false, error: "No response from API", tool_cycles: tool_cycles }
      else
        response.merge(tool_cycles: tool_cycles)
      end
    end

    # Build assistant content with tool calls in correct format
    def build_assistant_content_with_tools(response)
      content_blocks = []
      
      # Add text content first if present
      if response[:content].present?
        content_blocks << {
          type: 'text',
          text: response[:content]
        }
      end
      
      # Add thinking blocks if present (for interleaved thinking)
      if response[:thinking_blocks]&.any?
        response[:thinking_blocks].each do |thinking_block|
          content_blocks << thinking_block
        end
      end
      
      # Add tool_use blocks
      if response[:tool_calls]&.any?
        response[:tool_calls].each do |tool_call|
          # CRITICAL NIL SAFETY: Validate tool_call structure before accessing
          next unless tool_call.is_a?(Hash) && tool_call['function'].is_a?(Hash)
          
          function_name = tool_call['function']['name']
          function_args = tool_call['function']['arguments']
          
          unless function_name && function_args
            Rails.logger.error "[V5_CRITICAL] *** TOOL PROCESSING ERROR *** Missing function name or arguments: #{tool_call.inspect}"
            next
          end
          
          begin
            parsed_input = JSON.parse(function_args)
            content_blocks << {
              type: 'tool_use',
              id: tool_call['id'],
              name: function_name,
              input: parsed_input
            }
            Rails.logger.debug "[V5_CRITICAL] Successfully processed tool: #{function_name}"
          rescue JSON::ParserError => e
            Rails.logger.error "[V5_CRITICAL] JSON parsing failed for tool #{function_name}: #{e.message}"
            # Add tool anyway with raw arguments
            content_blocks << {
              type: 'tool_use',
              id: tool_call['id'],
              name: function_name,
              input: function_args
            }
          end
        end
      end
      
      content_blocks
    end

    # Check if deployment should be triggered after incremental completion
    def trigger_deployment_if_ready
      Rails.logger.info "[V5_INCREMENTAL] Checking if deployment should be triggered"
      
      # Check if app has files ready for deployment
      if @app.app_files.any?
        Rails.logger.info "[V5_INCREMENTAL] App has #{@app.app_files.count} files, triggering deployment"
        
        # Update status to trigger deployment
        @app.update(status: 'ready_to_deploy')
        
        # Trigger deployment job
        if @deploy_preview
          deploy_preview_if_ready
        else
          deploy_app
        end
      else
        Rails.logger.warn "[V5_INCREMENTAL] No files found, skipping deployment"
      end
    end
    
    # Continue incremental conversation after async tools complete
    def continue_incremental_conversation(messages, iteration_count = 0)
      @iteration_count = iteration_count
      
      Rails.logger.info "[V5_INCREMENTAL] Continuing conversation after async tool completion"
      
      # CRITICAL FIX: Find and reuse the existing assistant message to prevent splitting
      # Look for the most recent assistant message that is still processing
      # CRITICAL FIX 2: Also check for recently completed messages that might be part of ongoing conversation
      @assistant_message = @app.app_chat_messages
        .where(role: 'assistant')
        .where(status: ['processing', 'executing'])
        .order(created_at: :desc)
        .first
      
      # If no processing/executing message, check if there's a very recent completed one (within 5 seconds)
      # This handles the case where a message was marked completed between tool cycles
      if @assistant_message.nil?
        recent_completed = @app.app_chat_messages
          .where(role: 'assistant')
          .where(status: 'completed')
          .where('created_at > ?', 30.seconds.ago)
          .order(created_at: :desc)
          .first
        
        if recent_completed && recent_completed.conversation_flow.present?
          Rails.logger.info "[V5_INCREMENTAL] Found recently completed message ##{recent_completed.id}, reusing it"
          @assistant_message = recent_completed
          @assistant_message.update!(status: 'executing')  # Resume execution
        end
      end
      
      if @assistant_message.nil?
        Rails.logger.error "[V5_INCREMENTAL] No existing assistant message found! Creating new one"
        @assistant_message = @app.app_chat_messages.create!(
          role: 'assistant',
          content: '',
          status: 'processing',
          conversation_flow: []
        )
      else
        Rails.logger.info "[V5_INCREMENTAL] Reusing existing assistant message ##{@assistant_message.id}"
      end
      
      # Initialize prompt service if not already initialized
      if @prompt_service.nil?
        agent_vars = {
          app_id: @app.id,
          user_prompt: @chat_message.content,
          template_path: Rails.root.join("app/services/ai/templates/overskill_20250728"),
          iteration_limit: MAX_ITERATIONS,
          features: []  # Basic features for continuation
        }
        @prompt_service = Prompts::AgentPromptService.new(agent_vars)
      end
      
      # Reinitialize client and continue the conversation
      client = Ai::AnthropicClient.instance
      tools = @prompt_service.generate_tools
      helicone_session = SecureRandom.uuid
      helicone_path = "/app-#{@app.id}/resume"
      
      # Continue the tool calling cycle
      result = execute_tool_calling_cycle_incremental(client, messages, tools, helicone_session, helicone_path)
      
      # Handle the result
      if result[:async_execution]
        Rails.logger.info "[V5_INCREMENTAL] Another async execution started"
      else
        Rails.logger.info "[V5_INCREMENTAL] Conversation completed"
        
        # Trigger deployment if this was the final response
        if result[:content].present? && !result[:tool_calls]&.any?
          trigger_deployment_if_ready
        end
      end
      
      result
    rescue => e
      Rails.logger.error "[V5_INCREMENTAL] Error continuing conversation: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      
      # Update app status on error
      @app.update(status: 'error')
    end
    
    # NEW: Incremental tool streaming implementation
    # Tools are dispatched AS they arrive in the stream, not after completion
    def execute_tool_calling_cycle_incremental(client, messages, tools, helicone_session, helicone_path = nil)
      conversation_messages = messages.dup
      tool_cycles = 0
      max_tool_cycles = 30
      response = nil
      # Remove this variable as we'll use content_state per loop iteration
      
      Rails.logger.info "[V5_INCREMENTAL] Starting incremental tool calling cycle"
      
      loop do
        # Use hash to make it mutable within lambdas (Ruby closure workaround)
        content_state = { added: false }
        
        # Initialize incremental coordinator for this cycle
        coordinator = Ai::IncrementalToolCoordinator.new(@assistant_message, @app, @iteration_count)
        execution_id = coordinator.initialize_incremental_execution
        
        # Track tools as they arrive incrementally
        dispatched_tools = []
        text_content = ""
        thinking_blocks = []
        
        Rails.logger.info "[V5_INCREMENTAL] Cycle #{tool_cycles + 1}: Starting stream with incremental dispatch"
        
        # Pre-add text entry to conversation_flow to ensure correct ordering
        text_entry_index = nil
        if !content_state[:added]
          # Add placeholder text entry that will be updated as content streams in
          add_to_conversation_flow(
            type: 'message',
            content: '',
            iteration: @iteration_count
          )
          # Track the index of this text entry
          text_entry_index = (@assistant_message.conversation_flow || []).length - 1
          content_state[:added] = true
          content_state[:index] = text_entry_index
          Rails.logger.info "[V5_INCREMENTAL] Pre-added text entry at index #{text_entry_index}"
        end
        
        begin
          # Use incremental streaming with immediate tool dispatch
          callbacks = {
            on_tool_start: ->(tool_info) {
              Rails.logger.info "[V5_INCREMENTAL] Tool detected: #{tool_info[:name]} at index #{tool_info[:index]}"
              
              # Update UI immediately to show tool appearing
              coordinator.broadcast_tool_detected(execution_id, tool_info)
            },
            
            on_tool_complete: ->(tool_call) {
              Rails.logger.info "[V5_INCREMENTAL] Tool ready: #{tool_call[:function][:name]}"
              
              # CRITICAL: Dispatch to Sidekiq IMMEDIATELY
              tool_index = coordinator.dispatch_tool_incrementally(execution_id, tool_call)
              
              # Track for conversation history
              dispatched_tools << {
                index: tool_index,
                call: tool_call,
                dispatched_at: Time.current
              }
              
              Rails.logger.info "[V5_INCREMENTAL] Tool #{tool_index} dispatched immediately!"
            },
            
            on_text: ->(text_chunk) {
              text_content += text_chunk
              Rails.logger.info "[V5_INCREMENTAL] Text chunk received, total length: #{text_content.length}"
              
              # Update the pre-added text entry at the specific index
              if text_chunk.present? && content_state[:added] && content_state[:index]
                # Update the text entry at the tracked index
                if @assistant_message.conversation_flow && @assistant_message.conversation_flow[content_state[:index]]
                  @assistant_message.conversation_flow[content_state[:index]]['content'] = text_content
                  @assistant_message.conversation_flow[content_state[:index]]['updated_at'] = Time.current.iso8601
                  @assistant_message.save!
                  broadcast_conversation_update
                  Rails.logger.info "[V5_INCREMENTAL] Updated text at index #{content_state[:index]} (#{text_content.length} chars)"
                end
              end
            },
            
            on_thinking: ->(thinking_block) {
              thinking_blocks << thinking_block
            },
            
            on_complete: ->(result) {
              Rails.logger.info "[V5_INCREMENTAL] Stream complete. Stop reason: #{result[:stop_reason]}"
              Rails.logger.info "[V5_INCREMENTAL] #{dispatched_tools.size} tools already executing"
              
              # CRITICAL: Convert tool_call keys to strings for compatibility with build_assistant_content_with_tools
              stringified_tool_calls = dispatched_tools.map do |t|
                tool_call = t[:call]
                {
                  'id' => tool_call[:id],
                  'function' => {
                    'name' => tool_call[:function][:name],
                    'arguments' => tool_call[:function][:arguments]
                  }
                }
              end
              
              response = result.merge(
                tool_calls: stringified_tool_calls,
                content: text_content,
                thinking_blocks: thinking_blocks
              )
            },
            
            on_error: ->(error) {
              # Handle both hash and exception formats for safety
              error_message = error.is_a?(Hash) ? error[:message] : error.message
              Rails.logger.error "[V5_INCREMENTAL] Stream error: #{error_message}"
              
              # Clean up HTML error responses before raising
              clean_message = if error_message.include?("<html") || error_message.include?("<!DOCTYPE")
                if error_message.include?("Worker exceeded resource limits")
                  "Worker exceeded resource limits"
                elsif error_message.include?("502") || error_message.include?("Bad Gateway")
                  "Service temporarily unavailable (502)"
                elsif error_message.include?("503") || error_message.include?("Service Unavailable")
                  "Service temporarily unavailable (503)"
                else
                  "Invalid server response"
                end
              else
                error_message
              end
              
              raise StandardError.new("Incremental streaming failed: #{clean_message}")
            }
          }
          
          options = {
            model: :claude_sonnet_4,
            temperature: 0.7,
            max_tokens: 48000,
            helicone_session: helicone_session,
            helicone_path: "#{helicone_path || '/app-generation'}/cycle-#{tool_cycles}"
          }
          
          client.stream_chat_with_tools_incremental(
            conversation_messages,
            tools,
            callbacks,
            options
          )
          
        rescue => e
          log_claude_event("INCREMENTAL_STREAM_ERROR", {
            error: e.message,
            class: e.class.name,
            dispatched_tools: dispatched_tools.size
          })
          raise e
        end
        
        # Handle response based on stop reason
        stop_reason = response[:stop_reason] || 'stop'
        
        case stop_reason
        when 'tool_use'
          # Tools are already dispatched and running!
          if dispatched_tools.any?
            Rails.logger.info "[V5_INCREMENTAL] #{dispatched_tools.size} tools already executing"
            
            # Add text content to flow only if not already added during streaming
            if response[:content].present? && !content_state[:added]
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
              content_state[:added] = true
            end
            
            # Add assistant message with tool calls to conversation
            assistant_content = build_assistant_content_with_tools(response)
            assistant_message = {
              role: 'assistant',
              content: assistant_content
            }
            
            # Log the assistant content structure for debugging
            Rails.logger.info "[V5_INCREMENTAL] Assistant message content structure:"
            Rails.logger.info "[V5_INCREMENTAL] - Text blocks: #{assistant_content.select { |b| b[:type] == 'text' }.size}"
            Rails.logger.info "[V5_INCREMENTAL] - Tool use blocks: #{assistant_content.select { |b| b[:type] == 'tool_use' }.size}"
            Rails.logger.info "[V5_INCREMENTAL] - Tool IDs: #{assistant_content.select { |b| b[:type] == 'tool_use' }.map { |b| b[:id] }.join(', ')}"
            
            conversation_messages << assistant_message
            
            # ASYNC: Don't wait! Schedule completion check instead
            coordinator.finalize_tool_count(execution_id, dispatched_tools.size)
            
            Rails.logger.info "[V5_INCREMENTAL] Scheduling async completion check for #{dispatched_tools.size} tools"
            
            # Schedule job to check completion and continue conversation
            IncrementalToolCompletionJob.perform_later(
              @assistant_message.id,
              execution_id,
              conversation_messages,
              @iteration_count || 0
            )
            
            # Return immediately - tools are executing in background
            Rails.logger.info "[V5_INCREMENTAL] Returning immediately - tools executing asynchronously"
            return response.merge(
              tool_cycles: tool_cycles,
              async_execution: true,
              execution_id: execution_id
            )
            
            # Add tool results as user message
            user_message = {
              role: 'user',
              content: tool_results
            }
            conversation_messages << user_message
            
            tool_cycles += 1
            
            # Safety check
            if tool_cycles >= max_tool_cycles
              Rails.logger.warn "[V5_INCREMENTAL] Max tool cycles reached (#{max_tool_cycles})"
              response[:content] = "I've completed multiple rounds of file operations. The app structure has been updated." if response[:content].blank?
              response[:stop_reason] = 'max_tool_cycles'
              break
            end
            
            # Continue the conversation loop
            next
          else
            Rails.logger.warn "[V5_INCREMENTAL] Stop reason 'tool_use' but no tools dispatched"
            break
          end
          
        when 'stop', 'end_turn'
          # Check for tool calls even with stop reason (API streaming quirk)
          if dispatched_tools.any?
            Rails.logger.info "[V5_INCREMENTAL] Found #{dispatched_tools.size} tools with stop_reason='#{stop_reason}'"
            
            # Same flow as tool_use case above
            if response[:content].present? && !content_state[:added]
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
              content_state[:added] = true
            end
            
            assistant_message = {
              role: 'assistant',
              content: build_assistant_content_with_tools(response)
            }
            conversation_messages << assistant_message
            
            # ASYNC: Same as tool_use case - don't wait!
            coordinator.finalize_tool_count(execution_id, dispatched_tools.size)
            
            Rails.logger.info "[V5_INCREMENTAL] Stop with tools - scheduling async completion"
            
            IncrementalToolCompletionJob.perform_later(
              @assistant_message.id,
              execution_id,
              conversation_messages,
              @iteration_count || 0
            )
            
            return response.merge(
              tool_cycles: tool_cycles,
              async_execution: true,
              execution_id: execution_id
            )
            
            tool_cycles += 1
            
            if tool_cycles >= max_tool_cycles
              Rails.logger.warn "[V5_INCREMENTAL] Max tool cycles reached"
              response[:content] = "I've completed multiple rounds of file operations. The app structure has been updated." if response[:content].blank?
              response[:stop_reason] = 'max_tool_cycles'
              break
            end
            
            next
          else
            # Normal completion without tools
            Rails.logger.info "[V5_INCREMENTAL] Completed normally without tools"
            
            if response[:content].present? && !content_state[:added]
              add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
            end
            
            break
          end
          
        else
          Rails.logger.warn "[V5_INCREMENTAL] Unknown stop reason: #{stop_reason}"
          break
        end
      end
      
      # Return final response
      if response.nil?
        Rails.logger.error "[V5_INCREMENTAL] No response available"
        { success: false, error: "No response from incremental streaming", tool_cycles: tool_cycles }
      else
        response.merge(tool_cycles: tool_cycles, incremental_streaming: true)
      end
    end
    
    # Format tool results from incremental execution
    def format_incremental_tool_results(dispatched_tools, tool_results_raw)
      formatted_results = []
      
      dispatched_tools.each_with_index do |dispatched_tool, index|
        tool_call = dispatched_tool[:call]
        result_data = tool_results_raw[index] || { 'status' => 'error', 'error' => 'No result available' }
        
        formatted_results << {
          type: 'tool_result',
          tool_use_id: tool_call[:id],
          content: result_data['status'] == 'success' ? result_data['result'] : "Error: #{result_data['error']}"
        }
      end
      
      formatted_results
    end

    # Execute tools and format results according to Anthropic specs
    def execute_and_format_tool_results(tool_calls)
      tool_results = []
      
      # Clear pending tools at start to batch this group together
      @pending_tool_calls = []
      
      Rails.logger.info "[V5_TOOLS] Executing #{tool_calls.size} tools with incremental UI updates"
      
      # Use simple streaming tool coordinator for immediate parallel execution
      Rails.logger.info "[V5_TOOLS] Streaming tool execution enabled: #{@streaming_enabled}"
      
      if @streaming_enabled
        # Launch all tools immediately as parallel Sidekiq jobs and wait for completion
        # Using V2 coordinator with Rails.cache and deployment trigger
        coordinator = Ai::StreamingToolCoordinatorV2.new(@assistant_message, @iteration_count)
        tool_results = coordinator.execute_tools_in_parallel(tool_calls)
        
        Rails.logger.info "[V5_TOOLS] #{tool_calls.size} tools executed in parallel, received real results"
      else
        # Fallback to synchronous execution
        Rails.logger.info "[V5_TOOLS] Using synchronous tool execution"
        tool_results = execute_tools_synchronously(tool_calls)
      end
      
      # CRITICAL: Return array of tool_result blocks (they must come first in content array)
      tool_results
    end

    # Initialize tools section in conversation_flow for parallel execution
    def initialize_tools_in_conversation_flow(tool_calls)
      flow = @assistant_message.conversation_flow || []
      
      # Check if tools entry already exists
      existing_tools = flow.reverse.find { |item| item['type'] == 'tools' }
      
      if existing_tools.nil?
        tools_entry = {
          'type' => 'tools',
          'status' => 'executing',
          'started_at' => Time.current.iso8601,
          'tools' => tool_calls.map.with_index do |tool_call, index|
            tool_args = JSON.parse(tool_call['function']['arguments']) rescue {}
            {
              'id' => index + 1,
              'name' => tool_call['function']['name'],
              'args' => extract_display_args(tool_args),
              'status' => 'pending',
              'started_at' => nil,
              'completed_at' => nil,
              'error' => nil
            }
          end
        }
        flow << tools_entry
        @assistant_message.conversation_flow = flow
        @assistant_message.save!
        broadcast_message_update
      end
    end
    
    # Fallback method for synchronous tool execution
    def execute_tools_synchronously(tool_calls)
      tool_results = []
      
      tool_calls.each_with_index do |tool_call, index|
        tool_name = tool_call['function']['name']
        tool_args = JSON.parse(tool_call['function']['arguments'])
        tool_id = tool_call['id']
        
        Rails.logger.info "[V5_TOOLS] Synchronous execution: #{tool_name}"
        
        # Execute the tool synchronously
        result = execute_single_tool(tool_name, tool_args)
        
        # Format result according to Anthropic tool_result spec
        tool_result_block = {
          type: 'tool_result',
          tool_use_id: tool_id
        }
        
        if result[:error]
          tool_result_block[:content] = result[:error]
        else
          tool_result_block[:content] = result[:content] || "Tool completed successfully"
        end
        
        tool_results << tool_result_block
      end
      
      tool_results
    end
    
    # Execute a single tool and return result in consistent format
    def execute_single_tool(tool_name, tool_args)
      log_claude_event("TOOL_EXECUTE_START", {
        tool: tool_name,
        file: tool_args['file_path'],
        content_length: tool_args['content']&.length || 0
      })
      
      # Skip os-write calls with blank content to prevent validation errors
      if tool_name == 'os-write' && tool_args['content'].blank?
        Rails.logger.warn "[V5_TOOL] Skipping os-write with blank content for #{tool_args['file_path']}"
        return { error: "Skipped os-write with blank content for #{tool_args['file_path']}" }
      end
      
      # Update UI with tool execution - mark as running initially
      add_tool_call(tool_name, file_path: tool_args['file_path'], status: 'running')
      
      # Don't flush here - let the caller handle batching
      
      # Execute tool through centralized tool service
      # All tool implementations are in app/services/ai/ai_tool_service.rb
      # This delegation pattern keeps AppBuilderV5 focused on orchestration
      result = case tool_name
      when 'os-write'
        @tool_service.write_file(tool_args['file_path'], tool_args['content'])
      when 'os-view', 'os-read'
        @tool_service.read_file(tool_args['file_path'], tool_args['lines'])
      when 'os-line-replace'
        Rails.logger.info "[V5_TOOL] Processing os-line-replace with args: #{tool_args.inspect}"
        @tool_service.replace_file_content(tool_args)
      when 'os-delete'
        @tool_service.delete_file(tool_args['file_path'])
      when 'os-add-dependency'
        @tool_service.add_dependency(tool_args['package'])
      when 'os-remove-dependency'
        @tool_service.remove_dependency(tool_args['package'])
      when 'os-rename'
        @tool_service.rename_file(tool_args['old_path'], tool_args['new_path'])
      when 'os-search-files'
        @tool_service.search_files(tool_args)
      when 'os-download-to-repo'
        @tool_service.download_to_repo(tool_args['source_url'], tool_args['target_path'])
      when 'os-fetch-website'
        @tool_service.fetch_website(tool_args['url'], tool_args['formats'])
      when 'os-read-console-logs'
        @tool_service.read_console_logs(tool_args['search'])
      when 'os-read-network-requests'
        @tool_service.read_network_requests(tool_args['search'])
      when 'generate_image'
        @tool_service.generate_image(tool_args)
      when 'edit_image'
        @tool_service.edit_image(tool_args)
      when 'web_search'
        @tool_service.web_search(tool_args)
      when 'os-fetch-webpage'
        @tool_service.fetch_webpage(tool_args['url'], tool_args['use_cache'])
      when 'perplexity-research'
        # NEW: Perplexity AI-powered research tool
        @tool_service.perplexity_research(tool_args)
      when 'read_project_analytics'
        @tool_service.read_project_analytics(tool_args)
      when 'rename-app'
        @tool_service.rename_app(tool_args)
      when 'generate-new-app-logo'
        @tool_service.generate_app_logo(tool_args)
      else
        { error: "Unknown tool: #{tool_name}" }
      end
      
      log_claude_event("TOOL_EXECUTE_COMPLETE", {
        tool: tool_name,
        success: !result[:error],
        error: result[:error]
      })
      
      # Update tool status - find the specific tool call for this tool
      tool_call_to_update = @assistant_message.tool_calls.reverse.find do |tc|
        tc['name'] == tool_name && 
        tc['file_path'] == tool_args['file_path'] && 
        tc['status'] == 'running'
      end
      
      if tool_call_to_update
        new_status = result[:error] ? 'error' : 'complete'
        tool_call_to_update['status'] = new_status
        
        # Also update status in pending_tool_calls if not yet flushed
        if @pending_tool_calls.present?
          @pending_tool_calls.each do |pending_tool|
            if pending_tool['name'] == tool_name && 
               pending_tool['file_path'] == tool_args['file_path'] && 
               pending_tool['status'] == 'running'
              pending_tool['status'] = new_status
              Rails.logger.info "[V5_TOOLS] Updated pending tool status: #{tool_name} #{tool_args['file_path']} -> #{new_status}"
            end
          end
        end
        
        # Also update status in conversation_flow if already flushed
        update_tool_status_in_flow(tool_name, tool_args['file_path'], new_status)
        
        @assistant_message.save!
      end
      
      # Format result consistently with rich feedback for Claude
      if result[:success]
        # Convert successful results to text content for Claude with detailed confirmation
        content = case tool_name
        when 'os-write'
          lines_written = tool_args['content'].lines.count
          file_size = tool_args['content'].bytesize
          "✅ File written successfully: #{result[:path]}\n" \
          "• Lines written: #{lines_written}\n" \
          "• File size: #{file_size} bytes\n" \
          "• Status: File created/updated and saved to disk"
        when 'os-view', 'os-read'
          if result[:content]
            lines_read = result[:content].lines.count
            # Add line numbers to content for AI reference
            numbered_content = result[:content].lines.map.with_index(1) do |line, num|
              "#{num.to_s.rjust(4)}: #{line}"
            end.join
            "File contents retrieved:\n#{numbered_content}\n" \
            "📄 File: #{tool_args['file_path']}\n" \
            "• Lines: #{lines_read}\n" \
            "• Status: Successfully read with line numbers"
          else
            "File read successfully"
          end
        when 'os-line-replace'
          lines_replaced = (tool_args['last_replaced_line'].to_i - tool_args['first_replaced_line'].to_i + 1)
          new_lines = tool_args['replace'].lines.count
          
          message = "✅ File content replaced successfully: #{result[:path]}\n" \
            "• Lines replaced: #{tool_args['first_replaced_line']}-#{tool_args['last_replaced_line']} (#{lines_replaced} lines)\n" \
            "• New content: #{new_lines} lines inserted\n"
          
          # Add warning if fuzzy match was used
          if result[:fuzzy_match_used]
            message += "• Note: Fuzzy pattern matching was used (exact match failed)\n"
          end
          
          # Add warning if file was previously modified
          if @agent_state[:modified_files][result[:path]] && @agent_state[:modified_files].size > 1
            message += "• ⚠️ File has been modified multiple times - use os-view to see current state\n"
          end
          
          message += "• Status: Changes saved to disk"
          message
        when 'os-delete'
          "✅ File deleted successfully: #{result[:path]}\n" \
          "• Status: File removed from project"
        when 'os-add-dependency'
          "✅ Dependency added: #{tool_args['package']}\n" \
          "• Status: Package added to project dependencies"
        when 'os-rename'
          "✅ File renamed successfully\n" \
          "• From: #{tool_args['old_path']}\n" \
          "• To: #{tool_args['new_path']}\n" \
          "• Status: File moved and all references updated"
        else
          result.to_json
        end
        { content: content }
      else
        { error: result[:error] || "Tool execution failed" }
      end
    end
    
    def process_tool_calls(tool_calls)
      results = []
      
      # Clear pending tools at start to batch this group together
      @pending_tool_calls = []
      
      # Create a line offset tracker for this batch of tool calls
      # This handles the case where multiple line-replace operations on the same file
      # need adjusted line numbers after each replacement changes the file size
      # The tracker maintains separate offsets for EACH file being modified
      line_offset_tracker = Ai::LineOffsetTracker.new
      @tool_service.line_offset_tracker = line_offset_tracker if @tool_service
      Rails.logger.info "[V5_TOOLS] Created LineOffsetTracker for batch of #{tool_calls.size} tool calls"
      
      # Initialize streaming executor if enabled
      Rails.logger.info "[V5_DEBUG] Streaming enabled: #{@streaming_enabled}"
      streaming_executor = @streaming_enabled ? Ai::StreamingToolExecutor.new(@assistant_message, @app, @iteration_count) : nil
      Rails.logger.info "[V5_DEBUG] Streaming executor created: #{streaming_executor.present?}"
      
      tool_calls.each_with_index do |tool_call, tool_index|
        tool_name = tool_call['function']['name']
        tool_args = JSON.parse(tool_call['function']['arguments'])
        
        Rails.logger.info "[V5_DEBUG] Processing tool: #{tool_name}, streaming_executor present: #{streaming_executor.present?}"
        
        log_claude_event("TOOL_EXECUTE_START", {
          tool: tool_name,
          file: tool_args['file_path'],
          content_length: tool_args['content']&.length || 0
        })
        
        # Skip os-write calls with blank content to prevent validation errors
        if tool_name == 'os-write' && tool_args['content'].blank?
          Rails.logger.warn "[V5_TOOL] Skipping os-write with blank content for #{tool_args['file_path']}"
          Rails.logger.warn "[V5_TOOL] Full tool_args: #{tool_args.inspect}"
          results << { error: "Skipped os-write with blank content for #{tool_args['file_path']}" }
          next
        end
        
        # Update UI with tool execution - mark as running
        add_tool_call(tool_name, file_path: tool_args['file_path'], status: 'running')
        
        # Flush pending tools immediately for real-time updates
        flush_pending_tool_calls
        broadcast_message_update # Trigger immediate UI update
        
        # Execute with streaming or standard execution
        Rails.logger.info "[V5_DEBUG] About to execute tool, streaming_executor: #{streaming_executor.class.name rescue 'nil'}"
        result = begin
          if streaming_executor
            Rails.logger.info "[V5_DEBUG] Using streaming executor for #{tool_name}"
            # Use streaming executor for real-time updates
            streaming_result = streaming_executor.execute_with_streaming(
              { 'name' => tool_name, 'arguments' => tool_args },
              tool_index
            )
            Rails.logger.info "[V5_DEBUG] Streaming result: #{streaming_result.inspect[0..100]}"
            streaming_result
          else
            Rails.logger.info "[V5_DEBUG] Using standard execution for #{tool_name}"
            # Fallback to standard execution
            case tool_name
          when 'os-write'
            @tool_service.write_file(tool_args['file_path'], tool_args['content'])
          when 'os-view', 'os-read'
            @tool_service.read_file(tool_args['file_path'], tool_args['lines'])
          when 'os-line-replace'
            Rails.logger.info "[V5_TOOL_PROCESS] Processing os-line-replace in process_tool_calls"
            @tool_service.replace_file_content(tool_args)
          when 'os-delete'
            @tool_service.delete_file(tool_args['file_path'])
          when 'os-add-dependency'
            @tool_service.add_dependency(tool_args['package'])
          when 'os-remove-dependency'
            @tool_service.remove_dependency(tool_args['package'])
          when 'os-rename'
            @tool_service.rename_file(tool_args['old_path'], tool_args['new_path'])
          when 'os-search-files'
            @tool_service.search_files(tool_args)
          when 'os-download-to-repo'
            @tool_service.download_to_repo(tool_args['source_url'], tool_args['target_path'])
          when 'os-fetch-website'
            @tool_service.fetch_website(tool_args['url'], tool_args['formats'])
          when 'os-read-console-logs'
            @tool_service.read_console_logs(tool_args['search'])
          when 'os-read-network-requests'
            @tool_service.read_network_requests(tool_args['search'])
          when 'generate_image'
            @tool_service.generate_image(tool_args)
          when 'edit_image'
            @tool_service.edit_image(tool_args)
          when 'web_search'
            @tool_service.web_search(tool_args)
          when 'os-fetch-webpage'
            @tool_service.fetch_webpage(tool_args['url'], tool_args['use_cache'])
          when 'perplexity-research'
            # NEW: Perplexity AI-powered research tool
            @tool_service.perplexity_research(tool_args)
          when 'read_project_analytics'
            @tool_service.read_project_analytics(tool_args)
          when 'rename-app'
            @tool_service.rename_app(tool_args)
          when 'generate-new-app-logo'
            @tool_service.generate_app_logo(tool_args)
          when 'write_files', 'create_files'
            # Proper implementation for batch file operations
            process_batch_file_operation(tool_name, tool_args)
          else
            Rails.logger.error "=" * 60
            Rails.logger.error "❌ UNKNOWN TOOL: #{tool_name}"
            Rails.logger.error "=" * 60
            { error: "Unknown tool: #{tool_name}" }
          end
          end # End of streaming_executor if-else
        rescue StandardError => e
          Rails.logger.error "[V5_TOOLS] Tool execution failed in process_tool_calls: #{tool_name} - #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
          
          # Ensure status is updated to error on exception
          update_tool_status_to_error(tool_name, tool_args['file_path'], e.message)
          
          # Return error result
          { error: "Tool execution failed: #{e.message}" }
        end
        
        log_claude_event("TOOL_EXECUTE_COMPLETE", {
          tool: tool_name,
          success: !result[:error],
          error: result[:error]
        })
        
        # ENHANCEMENT 2: Enhanced tool success verification
        # Verify actual success vs false positive reporting
        actual_success = verify_tool_success(tool_name, result, tool_args)
        
        # Update tool status - find and update the specific tool call
        new_status = actual_success ? 'complete' : 'error'
        
        # Clone the array to trigger change detection
        updated_tool_calls = @assistant_message.tool_calls.deep_dup
        tool_updated = false
        
        updated_tool_calls.reverse.each do |tc|
          if tc['name'] == tool_name && 
             tc['file_path'] == tool_args['file_path'] && 
             tc['status'] == 'running'
            tc['status'] = new_status
            tool_updated = true
            break
          end
        end
        
        if tool_updated
          # Reassign to trigger ActiveRecord change detection for JSONB field
          @assistant_message.tool_calls = updated_tool_calls
          
          # Also update status in pending_tool_calls if not yet flushed
          if @pending_tool_calls.present?
            @pending_tool_calls.each do |pending_tool|
              if pending_tool['name'] == tool_name && 
                 pending_tool['file_path'] == tool_args['file_path'] && 
                 pending_tool['status'] == 'running'
                pending_tool['status'] = new_status
                Rails.logger.info "[V5_TOOLS_BATCH] Updated pending tool status: #{tool_name} #{tool_args['file_path']} -> #{new_status}"
              end
            end
          end
          
          # Also update status in conversation_flow if already flushed
          update_tool_status_in_flow(tool_name, tool_args['file_path'], new_status)
          
          @assistant_message.save!
        else
          Rails.logger.warn "[V5_TOOL] Could not find running tool call to update: #{tool_name} #{tool_args['file_path']}"
        end
        
        results << result
      end
      
      # Flush all pending tool calls as a batch to conversation_flow
      flush_pending_tool_calls
      
      # Clear the line offset tracker after processing this batch
      if @tool_service && line_offset_tracker
        Rails.logger.info "[V5_TOOLS] Clearing LineOffsetTracker after batch completion"
        @tool_service.line_offset_tracker = nil
      end
      
      results
    end
    
    def write_file(path, content)
      # Validate content is not blank
      if content.blank?
        Rails.logger.error "[V5_ERROR] write_file called with blank content for path: #{path}"
        return { error: "Cannot write file with blank content: #{path}" }
      end
      
      file = @app.app_files.find_or_initialize_by(path: path)
      is_update = file.persisted? && file.content != content
      file.content = content
      file.file_type = determine_file_type(path)
      file.team = @app.team  # Ensure team is set
      
      begin
        file.save!
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[V5_ERROR] Failed to save file #{path}: #{e.message}"
        return { error: "Failed to save file #{path}: #{e.message}" }
      end
      
      # Track modifications
      if is_update
        @agent_state[:modified_files][path] = Time.current
      end
      
      @agent_state[:generated_files] << file unless @agent_state[:generated_files].include?(file)
      
      { success: true, path: path, file_id: file.id }
    end
    
    def read_file(path)
      # First check if we have a template AppVersion v1.0.0
      template_version = get_or_create_template_version
      
      # Check template version files first
      if template_version && (template_file = template_version.app_version_files
                                                          .joins(:app_file)
                                                          .find_by(app_files: { path: path }))
        { success: true, content: template_file.app_file.content, source: 'template_version' }
      # Then check template directory as fallback
      elsif ::File.exist?(template_path = Rails.root.join("app/services/ai/templates/overskill_20250728", path))
        # Check if it's a directory
        if ::File.directory?(template_path)
          # Return directory listing instead of trying to read it as a file
          entries = Dir.entries(template_path).reject { |e| e.start_with?('.') }
          content = "Directory: #{path}\nContents:\n#{entries.map { |e| "  - #{e}" }.join("\n")}"
          { success: true, content: content, source: 'template_directory_listing' }
        else
          { success: true, content: ::File.read(template_path), source: 'template_directory' }
        end
      # Finally check generated files
      elsif file = @app.app_files.find_by(path: path)
        { success: true, content: file.content, source: 'generated' }
      else
        { error: "File not found: #{path}" }
      end
    end
    
    def replace_file_content(args)
      Rails.logger.info "[V5_LINE_REPLACE] Starting replacement for #{args['file_path']}"
      Rails.logger.info "[V5_LINE_REPLACE] Original lines #{args['first_replaced_line']}-#{args['last_replaced_line']}"
      
      file = @app.app_files.find_by(path: args['file_path'])
      unless file
        Rails.logger.error "[V5_LINE_REPLACE] File not found: #{args['file_path']}"
        return { error: "File not found: #{args['file_path']}" }
      end
      
      # Adjust line numbers using the offset tracker if available
      first_line = args['first_replaced_line'].to_i
      last_line = args['last_replaced_line'].to_i
      
      if @tool_service&.line_offset_tracker
        adjusted_first, adjusted_last = @tool_service.line_offset_tracker.adjust_line_range(
          args['file_path'], 
          first_line, 
          last_line
        )
        
        if adjusted_first != first_line || adjusted_last != last_line
          Rails.logger.info "[V5_LINE_REPLACE] Adjusted lines #{first_line}-#{last_line} → #{adjusted_first}-#{adjusted_last}"
          first_line = adjusted_first
          last_line = adjusted_last
        end
      end
      
      # Use LineReplaceService for proper validation and replacement
      if defined?(Ai::LineReplaceService)
        result = Ai::LineReplaceService.replace_lines(
          file,
          args['search'],
          first_line,
          last_line,
          args['replace']
        )
        
        if result[:success]
          Rails.logger.info "[V5_LINE_REPLACE] Success for #{args['file_path']}"
          
          # Record the replacement in the offset tracker
          if @tool_service&.line_offset_tracker
            replacement_lines = args['replace'].lines.count
            @tool_service.line_offset_tracker.record_replacement(
              args['file_path'],
              args['first_replaced_line'].to_i,  # Use original line numbers for tracking
              args['last_replaced_line'].to_i,
              replacement_lines
            )
          end
          
          # Track that this file has been modified
          @agent_state[:modified_files][args['file_path']] = Time.current
          { success: true, path: args['file_path'], file_modified: true }
        else
          Rails.logger.warn "[V5_LINE_REPLACE] Exact match failed, trying fuzzy replacement"
          
          # Try fuzzy replacement as fallback
          if defined?(Ai::FuzzyReplaceService) && args['search'].present?
            fuzzy_result = Ai::FuzzyReplaceService.replace(
              file,
              args['search'],
              args['replace']
            )
            
            if fuzzy_result[:success]
              Rails.logger.info "[V5_LINE_REPLACE] Fuzzy replacement succeeded: #{fuzzy_result[:message]}"
              # Track that this file has been modified
              @agent_state[:modified_files][args['file_path']] = Time.current
              { success: true, path: args['file_path'], file_modified: true, fuzzy_match_used: true }
            else
              Rails.logger.error "[V5_LINE_REPLACE] Both exact and fuzzy replacement failed"
              { error: result[:message] || "Line replacement failed" }
            end
          else
            Rails.logger.error "[V5_LINE_REPLACE] Failed: #{result[:message]}"
            { error: result[:message] || "Line replacement failed" }
          end
        end
      else
        # Fallback to improved basic implementation
        lines = file.content.lines(chomp: true)  # Preserve line endings properly
        start_line = args['first_replaced_line'].to_i - 1
        end_line = args['last_replaced_line'].to_i - 1
        
        # Validate line range
        if start_line < 0 || end_line >= lines.length || start_line > end_line
          return { error: "Invalid line range: #{args['first_replaced_line']}-#{args['last_replaced_line']}" }
        end
        
        # If search pattern provided, validate it matches
        if args['search'].present?
          existing_content = lines[start_line..end_line].join("\n")
          search_pattern = args['search'].strip
          
          # Handle ellipsis patterns
          if search_pattern.include?('...')
            parts = search_pattern.split('...')
            if parts.size == 2
              prefix = parts[0].strip
              suffix = parts[1].strip
              unless existing_content.strip.start_with?(prefix) && existing_content.strip.end_with?(suffix)
                Rails.logger.warn "[V5] Pattern mismatch: search doesn't match content at lines #{args['first_replaced_line']}-#{args['last_replaced_line']}"
                # Continue anyway for backward compatibility
              end
            end
          elsif existing_content.strip != search_pattern
            Rails.logger.warn "[V5] Pattern mismatch: search doesn't match content at lines #{args['first_replaced_line']}-#{args['last_replaced_line']}"
            # Continue anyway for backward compatibility
          end
        end
        
        # Replace the specified lines
        replacement_text = args['replace'] || ""
        replacement_lines = replacement_text.lines(chomp: true)
        
        # Perform replacement
        lines[start_line..end_line] = replacement_lines
        
        # Join with proper line endings
        file.content = lines.join("\n")
        file.content += "\n" unless file.content.end_with?("\n")
        file.save!
        
        # Track that this file has been modified
        @agent_state[:modified_files][args['file_path']] = Time.current
        { success: true, path: args['file_path'], file_modified: true }
      end
    end
    
    def delete_file(path)
      if file = @app.app_files.find_by(path: path)
        file.destroy
        @agent_state[:generated_files].delete(file)
        { success: true, path: path }
      else
        { error: "File not found: #{path}" }
      end
    end
    
    def add_dependency(package_spec)
      # Parse package name and version
      package, version = parse_package_spec(package_spec)
      
      # Get or create package.json
      package_file = @app.app_files.find_or_initialize_by(path: 'package.json')
      
      if package_file.new_record?
        # Create new package.json
        package_data = {
          "name" => @app.name.parameterize,
          "version" => "1.0.0",
          "private" => true,
          "dependencies" => {}
        }
        package_file.content = JSON.pretty_generate(package_data)
        package_file.team = @app.team
        package_file.save!
      end
      
      # Parse existing package.json
      package_data = JSON.parse(package_file.content)
      package_data["dependencies"] ||= {}
      
      # Add the dependency
      package_data["dependencies"][package] = version || "latest"
      
      # Save updated package.json
      package_file.update!(content: JSON.pretty_generate(package_data))
      
      { success: true, package: package, version: version || "latest" }
    rescue JSON::ParserError => e
      { error: "Invalid package.json: #{e.message}" }
    end
    
    def remove_dependency(package_name)
      package_file = @app.app_files.find_by(path: 'package.json')
      return { error: "package.json not found" } unless package_file
      
      package_data = JSON.parse(package_file.content)
      
      if package_data["dependencies"]&.delete(package_name)
        package_file.update!(content: JSON.pretty_generate(package_data))
        { success: true, package: package_name }
      else
        { error: "Dependency #{package_name} not found" }
      end
    rescue JSON::ParserError => e
      { error: "Invalid package.json: #{e.message}" }
    end
    
    def rename_file(old_path, new_path)
      file = @app.app_files.find_by(path: old_path)
      return { error: "File not found: #{old_path}" } unless file
      
      # Check if new path already exists
      if @app.app_files.exists?(path: new_path)
        return { error: "File already exists: #{new_path}" }
      end
      
      file.update!(path: new_path)
      { success: true, old_path: old_path, new_path: new_path }
    end
    
    def search_files(args)
      query = args['query']
      include_pattern = args['include_pattern'] || '**/*'
      exclude_pattern = args['exclude_pattern']
      case_sensitive = args['case_sensitive'] || false
      
      # Build regex
      regex_options = case_sensitive ? 0 : Regexp::IGNORECASE
      regex = Regexp.new(query, regex_options)
      
      # Find matching files
      matches = []
      
      @app.app_files.each do |file|
        # Check include pattern (handle both glob patterns and simple paths)
        if include_pattern.end_with?('/')
          # Simple directory pattern like 'src/'
          next unless file.path.start_with?(include_pattern)
        elsif include_pattern.include?('*')
          # Glob pattern
          next unless ::File.fnmatch(include_pattern, file.path, ::File::FNM_PATHNAME)
        else
          # Exact match
          next unless file.path == include_pattern
        end
        
        # Check exclude pattern
        next if exclude_pattern && ::File.fnmatch(exclude_pattern, file.path, ::File::FNM_PATHNAME)
        
        # Search content
        if file.content =~ regex
          matches << {
            path: file.path,
            matches: file.content.scan(regex).take(5) # Limit matches per file
          }
        end
      end
      
      { success: true, matches: matches, total: matches.count }
    rescue RegexpError => e
      { error: "Invalid regex: #{e.message}" }
    end
    
    # Process batch file operations (write_files, create_files)
    def process_batch_file_operation(tool_name, tool_args)
      Rails.logger.info "[V5_BATCH] Processing #{tool_name} with #{tool_args['files']&.size || 0} files"
      
      unless tool_args['files'].is_a?(Array)
        return { error: "Invalid arguments: 'files' must be an array" }
      end
      
      results = []
      success_count = 0
      error_count = 0
      
      tool_args['files'].each do |file_spec|
        unless file_spec['path'] && file_spec['content']
          Rails.logger.warn "[V5_BATCH] Skipping invalid file spec: #{file_spec.inspect}"
          error_count += 1
          next
        end
        
        # Process each file
        result = write_file(file_spec['path'], file_spec['content'])
        
        if result[:success]
          success_count += 1
          Rails.logger.info "[V5_BATCH] ✅ Created/updated: #{file_spec['path']}"
        else
          error_count += 1
          Rails.logger.error "[V5_BATCH] ❌ Failed: #{file_spec['path']} - #{result[:error]}"
        end
        
        results << result
      end
      
      # Return summary
      {
        success: error_count == 0,
        message: "Processed #{tool_args['files'].size} files: #{success_count} successful, #{error_count} failed",
        results: results,
        success_count: success_count,
        error_count: error_count
      }
    end
    
    def download_to_repo(source_url, target_path)
      # For V5, we'll just create a placeholder - actual download would require HTTP client
      # In production, this would download the file
      
      file = @app.app_files.find_or_initialize_by(path: target_path)
      file.content = "// Downloaded from: #{source_url}\n// Placeholder content for testing"
      file.team = @app.team
      file.save!
      
      { success: true, path: target_path, source: source_url }
    end
    
    def fetch_website(url, formats = 'markdown')
      # For V5, return placeholder content
      # In production, this would fetch and convert website content
      
      { 
        success: true, 
        url: url,
        content: "# Website Content\nFetched from: #{url}\n\nPlaceholder content for testing.",
        formats: formats || 'markdown'
      }
    end
    
    def read_console_logs(search_query)
      # For V5, return placeholder logs
      # In production, this would integrate with browser console logs API
      
      mock_logs = [
        "[INFO] App initialization complete",
        "[WARN] Deprecated API usage detected",
        "[ERROR] Failed to load resource: network timeout"
      ]
      
      filtered_logs = search_query.present? ? 
        mock_logs.select { |log| log.downcase.include?(search_query.downcase) } : 
        mock_logs
      
      {
        success: true,
        logs: filtered_logs,
        search_query: search_query,
        total_found: filtered_logs.count
      }
    end
    
    def read_network_requests(search_query)
      # For V5, return placeholder network requests
      # In production, this would integrate with browser network API
      
      mock_requests = [
        "GET /api/users - 200 OK (150ms)",
        "POST /api/auth/login - 401 Unauthorized (250ms)",
        "GET /api/data - 500 Internal Server Error (1200ms)"
      ]
      
      filtered_requests = search_query.present? ?
        mock_requests.select { |req| req.downcase.include?(search_query.downcase) } :
        mock_requests
      
      {
        success: true,
        requests: filtered_requests,
        search_query: search_query,
        total_found: filtered_requests.count
      }
    end
    
    def generate_image(args)
      prompt = args['prompt']
      target_path = args['target_path']
      width = args['width'] || 512
      height = args['height'] || 512
      model = args['model'] || 'flux.schnell'
      
      Rails.logger.info "[V5_IMAGE] Generating image: #{prompt} (#{width}x#{height})"
      
      # Use shared image generation service
      image_service = Ai::ImageGenerationService.new(@app)
      
      result = image_service.generate_and_save_image(
        prompt: prompt,
        width: width,
        height: height,
        target_path: target_path,
        model: model,
        options: {
          # OpenAI gpt-image-1 options (primary provider)
          quality: model == 'flux.dev' ? 'high' : 'medium',
          # style removed: OpenAI images API no longer accepts 'style'
          
          # Ideogram options (fallback provider)
          rendering_speed: model == 'flux.dev' ? 'DEFAULT' : 'TURBO',
          style_type: 'GENERAL'
        }
      )
      
      if result[:success]
        # Track the generated file in agent state
        generated_file = @app.app_files.find_by(path: target_path)
        @agent_state[:generated_files] << generated_file if generated_file && !@agent_state[:generated_files].include?(generated_file)
        
        # Process image URLs after generation to ensure components can reference them
        begin
          Rails.logger.info "[V5_IMAGE] Processing image URLs for easy component access"
          image_extractor = Ai::ImageUrlExtractorService.new(@app)
          image_extractor.process_all_images
        rescue => e
          Rails.logger.warn "[V5_IMAGE] Failed to process image URLs: #{e.message}"
        end
        
        Rails.logger.info "[V5_IMAGE] Successfully generated and saved image: #{target_path}"
        {
          success: true,
          path: target_path,
          prompt: prompt,
          dimensions: result[:dimensions],
          provider: result[:provider]
        }
      else
        Rails.logger.error "[V5_IMAGE] Failed to generate image: #{result[:error]}"
        result
      end
    end
    
    def edit_image(args)
      # For V5, return placeholder image editing
      # In production, this would integrate with image editing API
      
      image_paths = args['image_paths']
      prompt = args['prompt']
      target_path = args['target_path']
      strength = args['strength'] || 0.8
      
      # Validate inputs
      if image_paths.blank? || image_paths.empty?
        return { error: "At least one image path is required" }
      end
      
      if strength < 0.0 || strength > 1.0
        return { error: "Strength must be between 0.0 and 1.0" }
      end
      
      # Check if source images exist
      missing_files = image_paths.reject { |path| @app.app_files.exists?(path: path) }
      if missing_files.any?
        return { error: "Source images not found: #{missing_files.join(', ')}" }
      end
      
      # Create placeholder edited image
      placeholder_content = "// Edited image placeholder\n// Source images: #{image_paths.join(', ')}\n// Edit prompt: #{prompt}\n// Strength: #{strength}\n// TODO: Replace with actual image editing API"
      
      file = @app.app_files.find_or_initialize_by(path: target_path)
      file.content = placeholder_content
      file.file_type = determine_file_type(target_path)
      file.team = @app.team
      file.save!
      
      {
        success: true,
        path: target_path,
        source_images: image_paths,
        prompt: prompt,
        strength: strength,
        note: "Placeholder implementation - requires image editing API integration"
      }
    end
    

    
    def fetch_webpage_content(args)
      # Use the WebContentTool to fetch and extract webpage content
      url = args['url']
      use_cache = args.fetch('use_cache', true)
      
      if url.blank?
        return { success: false, error: "URL parameter is required" }
      end
      
      Rails.logger.info "[V5_TOOL] Fetching webpage content from: #{url}"
      
      begin
        # Use the web content tool
        tool = Ai::Tools::WebContentTool.new(@app)
        result = tool.execute(args)
        
        if result[:success]
          Rails.logger.info "[V5_TOOL] Successfully fetched content from #{url}"
          { 
            success: true, 
            content: result[:content]
          }
        else
          Rails.logger.error "[V5_TOOL] Failed to fetch webpage: #{result[:error]}"
          { 
            success: false, 
            error: result[:error],
            content: "Failed to fetch webpage: #{result[:error]}"
          }
        end
      rescue => e
        Rails.logger.error "[V5_TOOL] Error fetching webpage: #{e.message}"
        { 
          success: false, 
          error: e.message,
          content: "Error fetching webpage: #{e.message}"
        }
      end
    end
    
    def web_search(args)
      # SERPAPI-backed web search with safe fallbacks for test/dev
      query = args['query']
      num_results = args['numResults'] || 5
      image_links = args['imageLinks'] || 0
      category = args['category']
      engine = (args['engine'] || 'google').to_s

      if query.blank?
        return { success: false, error: "Missing required 'query'" }
      end

      # Prefer ENV, fallback to credentials if present
      serpapi_key = ENV['SERPAPI_KEY']
      serpapi_key ||= Rails.application.credentials.dig(:serpapi_key) rescue nil

      # For CI/tests or when key missing, return deterministic mock results
      if Rails.env.test? && ENV['SERPAPI_TEST_LIVE'] != '1'
        return web_search_mock_response(query, num_results, category)
      end

      if serpapi_key.blank?
        Rails.logger.warn "[WebSearch] SERPAPI_KEY missing. Returning mock results."
        return web_search_mock_response(query, num_results, category)
      end

      begin
        require 'serpapi'

        # Initialize client with defaults
        client = SerpApi::Client.new(
          engine: engine,
          api_key: serpapi_key,
          async: false,
          persistent: true,
          timeout: 15,
          symbolize_names: true
        )

        # Main web search (organic results)
        search_params = {
          q: query,
          num: num_results,
          safe: 'active',
          hl: 'en'
        }

        raw = client.search(search_params)

        organic = (raw[:organic_results] || raw['organic_results'] || []).first(num_results)
        mapped_results = organic.map do |r|
          {
            title: r[:title] || r['title'],
            url: r[:link] || r['link'],
            display_url: r[:displayed_link] || r['displayed_link'],
            snippet: r[:snippet] || r['snippet'],
            position: r[:position] || r['position'],
            sitelinks: begin
              sl = r[:sitelinks] || r['sitelinks'] || r[:sitelinks_inline] || r['sitelinks_inline']
              Array(sl).map { |slr| { title: slr[:title] || slr['title'], url: slr[:link] || slr['link'] } }
            rescue
              []
            end
          }
        end

        images = []
        if image_links.to_i > 0
          images_params = {
            engine: 'google_images',
            q: query,
            num: image_links.to_i,
            safe: 'active'
          }
          images_raw = client.search(images_params)
          images_results = images_raw[:images_results] || images_raw['images_results'] || []
          images = images_results.first(image_links.to_i).map do |im|
            {
              title: im[:title] || im['title'],
              source: im[:source] || im['source'],
              thumbnail: im[:thumbnail] || im['thumbnail'],
              original: im[:original] || im['original'],
              link: im[:link] || im['link']
            }
          end
        end

        total_results = begin
          info = raw[:search_information] || raw['search_information']
          info && (info[:total_results] || info['total_results'])
        rescue
          nil
        end

        {
          success: true,
          provider: 'serpapi',
          engine: engine,
          query: query,
          category: category,
          results: mapped_results,
          images: images,
          total_results: total_results || mapped_results.length
        }
      rescue => e
        Rails.logger.error "[WebSearch] SERPAPI error: #{e.class} #{e.message}"
        # Graceful fallback on errors
        web_search_mock_response(query, num_results, category).merge(note: 'SerpAPI error, returned mock results')
      end
    end

    def web_search_mock_response(query, num_results, category)
      mock_results = [
        {
          title: "#{query} - Documentation",
          url: "https://example.com/docs/#{query.to_s.parameterize}",
          snippet: "Official documentation for #{query}. Learn how to implement and use #{query} effectively.",
          category: category || "documentation"
        },
        {
          title: "#{query} Tutorial - Getting Started",
          url: "https://tutorial-site.com/#{query.to_s.parameterize}",
          snippet: "Step-by-step tutorial covering #{query} basics and advanced techniques.",
          category: category || "tutorial"
        },
        {
          title: "#{query} GitHub Repository",
          url: "https://github.com/example/#{query.to_s.parameterize}",
          snippet: "Open source implementation of #{query} with examples and community contributions.",
          category: "github"
        }
      ].first(num_results)

      {
        success: true,
        provider: 'mock',
        engine: 'google',
        query: query,
        results: mock_results,
        images: [],
        total_results: mock_results.count,
        category: category
      }
    end
    
    def read_project_analytics(args)
      # For V5, return placeholder analytics data
      # In production, this would integrate with analytics API (Google Analytics, etc.)
      
      start_date = args['startdate']
      end_date = args['enddate']
      granularity = args['granularity'] || 'daily'
      
      # Mock analytics data
      mock_data = {
        date_range: {
          start: start_date,
          end: end_date,
          granularity: granularity
        },
        metrics: {
          page_views: 1250,
          unique_visitors: 892,
          bounce_rate: 0.35,
          average_session_duration: 180
        },
        top_pages: [
          { path: "/", views: 450, title: "Home" },
          { path: "/features", views: 320, title: "Features" },
          { path: "/pricing", views: 180, title: "Pricing" }
        ],
        traffic_sources: {
          organic: 0.45,
          direct: 0.30,
          social: 0.15,
          referral: 0.10
        }
      }
      
      {
        success: true,
        data: mock_data,
        app_id: @app.id,
        note: "Placeholder implementation - requires analytics API integration"
      }
    end
    
    def parse_package_spec(spec)
      # Parse package@version format
      if spec.include?('@')
        parts = spec.split('@')
        # Handle scoped packages like @types/node
        if spec.start_with?('@')
          package = parts[0..1].join('@')
          version = parts[2]
        else
          package = parts[0]
          version = parts[1]
        end
        [package, version]
      else
        [spec, nil]
      end
    end
    
    def build_messages_with_context(prompt)
      # OPTIMIZED: Use cached prompt builder for better performance
      # Long-form data (template files) goes at TOP of system prompt for caching
      
      # Build optimized system prompt with caching
      system_prompt = build_cached_system_prompt
      
      # Start with optimized system prompt
      messages = [
        { role: 'system', content: system_prompt }
      ]
      
      # For continuation conversations, include previous messages
      if @app.app_chat_messages.count > 1
        # Add previous conversation history (excluding current message)
        add_previous_chat_messages(messages)
      end
      
      # Add current user message
      # First check for security issues
      user_content = @chat_message.content
      
      # Security check for prompt injection
      if @security_filter.detect_injection?(user_content)
        Rails.logger.warn "[SECURITY] Prompt injection detected for user #{@chat_message.user_id}"
        
        # Record the attempt
        if @chat_message.user
          @security_filter.record_injection_attempt(
            @chat_message.user,
            @app,
            user_content
          )
        end
        
        # Check if user should be rate limited
        if @chat_message.user && @security_filter.should_rate_limit?(@chat_message.user, @app)
          raise Security::PromptInjectionFilter::InjectionAttemptDetected,
                "Too many injection attempts. Please contact support if you believe this is an error."
        end
        
        # Sanitize the input
        user_content = @security_filter.sanitize_input(user_content)
        Rails.logger.info "[SECURITY] Input sanitized after injection detection"
      end
      

      # TODO Implement a is_discussion variable on the app chat message based on if they have it toggled on or off in UI
      is_discussion = false

      # If not a discussion and appears to be a change request, append the instruction
      if !is_discussion
        user_content = "#{user_content} <system-reminder>Think ahead around tool calling needs, and update all necessary APPLICATION files in one response. IMPORTANT: Use existing UI components from @/components/ui/ - DO NOT create new UI component files (button.tsx, card.tsx, etc.) as they already exist in the template. IMPORTANT: If you need to update the UI, use the existing UI components from @/components/ui/ - DO NOT create new UI component files (button.tsx, card.tsx, etc.) as they already exist in the template.</system-reminder>"
        Rails.logger.info "[V5_PROMPT] Appended batch update instruction to user prompt with component clarification"
      end
      
      messages << { role: 'user', content: user_content }
      
      # CRITICAL FIX: Add conversation history from previous iterations within this message
      if @iteration_count > 1
        add_conversation_history(messages)
      end
      
      # Add specific prompt for this iteration if different from user message
      if prompt.is_a?(String) && prompt != @chat_message.content
        messages << { role: 'user', content: prompt }
      end
      
      messages
    end
    
    def add_previous_chat_messages(messages)
      # Get previous messages from the app's chat history (excluding current)
      previous_messages = @app.app_chat_messages
                              .where.not(id: @chat_message.id)
                              .order(created_at: :asc)
                              .last(5) # Keep last 5 messages for context
      
      previous_messages.each do |msg|
        # Skip failed or error messages
        next if msg.status == 'failed'
        
        if msg.role == 'user'
          messages << { role: 'user', content: msg.content }
        elsif msg.role == 'assistant'
          # For assistant messages in continuation, we need to include thinking blocks
          # when thinking is enabled to satisfy Anthropic API requirements
          content_blocks = []
          
          # IMPORTANT: Thinking block must come FIRST in the content array
          # Check if we have thinking content from previous iterations
          thinking_added = false
          if msg.loop_messages.present? && msg.loop_messages.any? { |lm| lm['thinking'].present? || lm['type'] == 'thinking' }
            # Extract thinking from loop messages
            msg.loop_messages.each do |loop_msg|
              if loop_msg['type'] == 'thinking' && loop_msg['content'].present?
                # Loop messages store thinking as 'content' internally
                content_blocks << { 
                  type: 'thinking', 
                  thinking: loop_msg['content'],
                  signature: loop_msg['signature'] || "sig_#{SecureRandom.hex(8)}"
                }
                thinking_added = true
                break # Only need one thinking block per message
              elsif loop_msg['thinking'].present?
                content_blocks << { 
                  type: 'thinking', 
                  thinking: loop_msg['thinking'],
                  signature: loop_msg['signature'] || "sig_#{SecureRandom.hex(8)}"
                }
                thinking_added = true
                break # Only need one thinking block per message
              end
            end
          end
          
          if !thinking_added && msg.metadata.present? && msg.metadata['thinking'].present?
            # Use metadata thinking if available
            content_blocks << { 
              type: 'thinking', 
              thinking: msg.metadata['thinking'],
              signature: msg.metadata['thinking_signature'] || "sig_#{SecureRandom.hex(8)}"
            }
            thinking_added = true
          end
          
          if !thinking_added
            # Add a minimal thinking block to satisfy API requirements
            content_blocks << { 
              type: 'thinking', 
              thinking: "Processing the user's request to modify the app.",
              signature: "sig_#{SecureRandom.hex(8)}"
            }
          end
          
          # Add the actual text content AFTER the thinking block
          assistant_content = msg.content.presence || "I processed your request and made changes to the app."
          content_blocks << { type: 'text', text: assistant_content }
          
          # Add tool use/results if they exist in the message
          if msg.tool_calls.present? && msg.tool_calls.any?
            msg.tool_calls.each do |tool_call|
              if tool_call['type'] == 'tool_use'
                content_blocks << tool_call
              elsif tool_call['tool_use_id'].present?
                # Add tool result
                content_blocks << {
                  type: 'tool_result',
                  tool_use_id: tool_call['tool_use_id'],
                  content: tool_call['content'] || tool_call['output'] || 'Tool executed successfully'
                }
              end
            end
          end
          
          messages << { role: 'assistant', content: content_blocks }
        end
      end
      
      Rails.logger.info "[V5_CONTEXT] Added #{previous_messages.size} previous messages to context with thinking blocks"
    end
    
    # Build optimized system prompt with caching support
    def build_cached_system_prompt
      # Use granular caching if enabled
      use_granular = ENV['ENABLE_GRANULAR_CACHING'] != 'false'
      
      # Detect any external file changes before building prompt
      if use_granular && @file_tracker
        detect_external_changes
      end
      
      template_files = get_template_files_for_caching
      base_prompt = @prompt_service.generate_prompt(include_context: false)
      context_data = build_current_context_data
      
      # Add component requirements analysis to context
      context_data = add_component_requirements_to_context(context_data)
      
      # Use GranularCachedPromptBuilder for file-level caching
      builder_class = use_granular ? Ai::Prompts::GranularCachedPromptBuilder : Ai::Prompts::CachedPromptBuilder
      
      builder = builder_class.new(
        base_prompt: base_prompt,
        template_files: template_files,
        context_data: context_data,
        app_id: @app.id  # Pass app_id for granular caching
      )
      
      # Log caching decision
      total_template_size = template_files.sum { |f| f.content&.length || 0 }
      will_use_array = use_array_system_prompt?
      
      Rails.logger.info "[V5_CACHE] Caching mode: #{use_granular ? 'GRANULAR file-level' : 'MONOLITHIC'}"
      Rails.logger.info "[V5_CACHE] System prompt format: #{will_use_array ? 'ARRAY with cache_control' : 'STRING (no caching)'}"
      Rails.logger.info "[V5_CACHE] Template size: #{total_template_size} chars (threshold: 10,000)"
      Rails.logger.info "[V5_CACHE] Base prompt size: #{base_prompt&.length || 0} chars"
      
      # Use array format for optimal caching when enabled
      if will_use_array
        # Array format enables cache_control on specific blocks
        system_prompt = builder.build_system_prompt_array
        Rails.logger.info "[V5_CACHE] Built array system prompt with #{system_prompt.size} blocks"
        system_prompt.each_with_index do |block, i|
          has_cache = block[:cache_control].present?
          ttl = block.dig(:cache_control, :ttl) || 'default'
          Rails.logger.info "[V5_CACHE]   Block #{i+1}: #{block[:text]&.length || 0} chars, cache: #{has_cache ? "YES (#{ttl})" : 'NO'}"
        end
        system_prompt
      else
        # String format for backward compatibility
        builder.build_system_prompt_string
      end
    end
    
    # Check if we should use array format for system prompts
    def use_array_system_prompt?
      # Enable when we have substantial template content to cache
      template_size = get_template_files_for_caching.sum { |f| f.content&.length || 0 }
      template_size > 10_000  # Use array format for 10K+ chars of template content
    end
    
    # Add component requirements analysis to context
    def add_component_requirements_to_context(context_data)
      # Analyze the user's request to determine required components
      analysis = Ai::ComponentRequirementsAnalyzer.analyze_with_confidence(
        @chat_message.content,
        @app.app_files
      )
      
      Rails.logger.info "[V5_CACHE] Component analysis: #{analysis[:components].join(', ')}"
      Rails.logger.info "[V5_CACHE] App type detected: #{analysis[:app_type]}"
      
      # Store for use in context building
      @predicted_components = analysis[:components]
      @detected_app_type = analysis[:app_type]
      
      # Add requirements to context as a helpful guide
      requirements_text = <<~REQUIREMENTS
        
        ## Component Requirements Analysis
        Based on the user's request, you will likely need these components:
        
        **App Type Detected**: #{analysis[:app_type] || 'general'}
        **Pre-loaded Components**: #{analysis[:components].join(', ')}
        **Analysis Confidence**: #{analysis[:confidence].present? ? (analysis[:confidence].values.sum / analysis[:confidence].size * 100).round : 0}%
        
        **Reasoning**: #{analysis[:reasoning].join('; ') if analysis[:reasoning]}
        
        IMPORTANT: The above components have been pre-loaded in your context. Use them as needed for the implementation.
      REQUIREMENTS
      
      # Append to context data
      if context_data.is_a?(String)
        context_data + requirements_text
      elsif context_data.is_a?(Array)
        context_data + [requirements_text]
      else
        context_data
      end
    end
    
    # Get template files for caching (long-form data goes first)
    def get_template_files_for_caching
      # FIXED: Don't disable caching after first iteration - use cache throughout conversation
      # Cache key will include iteration count for proper invalidation when needed
      template_files = []
      
      # Include context based on what hasn't been modified yet
      # This ensures we get cache benefits throughout the conversation
      if @iteration_count <= 5  # Reasonable limit to prevent infinite caching
        # Get the optimized complete context (consolidates useful + existing files)
        base_context_service = Ai::BaseContextService.new(@app, {
          app_type: @detected_app_type,
          component_requirements: @predicted_components
        })
        complete_context = base_context_service.build_complete_context(@app, {
          component_requirements: @predicted_components,
          app_type: @detected_app_type
        })
        
        # Create a pseudo-file object for the optimized context
        if complete_context.present? && complete_context.length > 1000
          template_files << OpenStruct.new(
            path: "optimized_context",
            content: complete_context
          )
        end
      end
      
      # Don't cache existing app files as they may have been modified
      # Let them go in the dynamic context section instead
      
      Rails.logger.info "[V5_CACHE] Template files for caching: #{template_files.size} files, #{template_files.sum { |f| f.content&.length || 0 }} total chars (iteration #{@iteration_count})"
      
      template_files
    end
    
    # Build current context data (changes frequently, don't cache)
    def build_current_context_data
      # Always include base context, even on first iteration
      context = {}
      
      # Add optimized complete context (replaces separate base + existing files context)
      base_context_service = Ai::BaseContextService.new(@app, {
        app_type: @detected_app_type,
        component_requirements: @predicted_components,
        load_components: true
      })
      
      # Single optimized context method replaces the duplicate logic
      complete_context = base_context_service.build_complete_context(@app, {
        component_requirements: @predicted_components,
        app_type: @detected_app_type
      })
      
      # Use single context instead of two separate ones
      context[:optimized_context] = complete_context if complete_context.present?
      
      # Add iteration-specific context if not first iteration
      if @iteration_count > 1
        context[:iteration_data] = {
          iteration: @iteration_count,
          max_iterations: MAX_ITERATIONS,
          files_generated: @agent_state[:generated_files].count,
          last_action: @agent_state[:history].last&.dig(:action, :type),
          confidence: (@agent_state[:verification_results].last&.dig(:confidence) || 0) * 100
        }
        context[:recent_operations] = format_recent_operations_for_context
        context[:verification_results] = @agent_state[:verification_results].last
      end
      
      context
    end
    
    def format_recent_operations_for_context
      return [] unless @recent_operations&.any?
      
      @recent_operations.last(5).map do |op|
        {
          type: op[:key].split(':').first,
          description: op[:key]
        }
      end
    end
    
    # NEW METHOD: Add conversation history so Claude sees what it has already done
    def add_conversation_history(messages)
      # Add key loop messages as assistant responses so Claude sees its own work
      @assistant_message.loop_messages.each_with_index do |loop_msg, index|
        next unless loop_msg['content'].present?
        
        # Skip status messages, include substantive responses
        next if loop_msg['type'] == 'status'
        
        assistant_message = {
          role: 'assistant',
          content: loop_msg['content']
        }
        
        # Skip thinking blocks in conversation history for now
        # The API doesn't accept thinking blocks in assistant messages sent as context
        # Only the API itself can generate thinking blocks
        if loop_msg['thinking_blocks']&.any?
          Rails.logger.debug "[V5_THINKING] Skipping #{loop_msg['thinking_blocks'].size} thinking blocks in conversation history (not supported in context)" if ENV["VERBOSE_AI_LOGGING"] == "true"
        end
        
        messages << assistant_message
        
        # Limit history to avoid token overload (keep last 3 substantial messages with thinking)
        break if index >= 2
      end
    end
    
    def build_iteration_context
      recent_ops = format_recent_operations
      stagnation_warnings = check_stagnation_warnings
      
      context = <<~CONTEXT
        AGENT LOOP ITERATION #{@iteration_count} OF #{MAX_ITERATIONS}
        
        LOOP DETECTION STATUS:
        #{recent_ops.present? ? recent_ops : "No repetitive operations detected"}
        
        PREVIOUS ACTIONS TAKEN:
        #{format_previous_actions(@agent_state[:history])}
        
        GENERATED FILES SO FAR (#{@agent_state[:generated_files].count} files):
        #{format_generated_files(@agent_state[:generated_files])}
        
        CURRENT CONTEXT COMPLETENESS: #{@context_manager.completeness_score}%
        
        LAST VERIFICATION RESULTS:
        #{format_verification_results(@agent_state[:verification_results].last)}
        #{stagnation_warnings}
        
        GUIDANCE:
        #{generate_iteration_guidance}
      CONTEXT
      
      context
    end
    
    def agent_variables
      {
        app_id: app.id,
        user_prompt: @chat_message.content,
        template_path: Rails.root.join("app/services/ai/templates/overskill_20250728"),
        iteration_limit: MAX_ITERATIONS,
        features: extract_required_features
      }
    end
    
    def extract_required_features
      # Extract features from user prompt
      features = []
      prompt_lower = @chat_message.content.downcase
      
      features << 'authentication' if prompt_lower.include?('login') || prompt_lower.include?('auth')
      features << 'database' if prompt_lower.include?('data') || prompt_lower.include?('store')
      features << 'payments' if prompt_lower.include?('payment') || prompt_lower.include?('stripe')
      features << 'charts' if prompt_lower.include?('chart') || prompt_lower.include?('graph')
      
      features
    end
    
    def create_app
      # Return existing app if already associated with the message
      return @chat_message.app if @chat_message.app.present?
      
      # Create new app
      team = @chat_message.user.teams.first || @chat_message.user.teams.create!(name: "Default Team")
      membership = team.memberships.find_by(user: @chat_message.user) || 
                   team.memberships.create!(user: @chat_message.user, roles: ['admin'])
      
      app = team.apps.create!(
        name: generate_app_name(@chat_message.content),
        status: 'generating',
        prompt: @chat_message.content,
        creator: membership,
        app_type: 'tool'  # Default to tool type
      )
      
      @chat_message.update!(app: app)
      app
    end
    
    def generate_app_name(prompt)
      # Extract a meaningful name from the prompt
      if prompt.downcase.include?('todo')
        "Todo App #{Time.current.strftime('%m%d')}"
      elsif prompt.downcase.include?('chat')
        "Chat App #{Time.current.strftime('%m%d')}"
      elsif prompt.downcase.include?('dashboard')
        "Dashboard #{Time.current.strftime('%m%d')}"
      else
        "App #{Time.current.strftime('%m%d%H%M')}"
      end
    end
    
    def handle_error(error)
      Rails.logger.error "[AppBuilderV5] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      # Output error to console for debugging
      puts "\n❌ AppBuilderV5 Error: #{error.message}"
      puts error.backtrace.first(5).join("\n")
      
      # Mark generation as failed to prevent any deployment attempts
      @completion_status = :failed
      app.update!(status: 'failed')
      
      # Preserve the conversation_flow explicitly
      preserved_flow = @assistant_message.conversation_flow || []
      
      @assistant_message.update!(
        thinking_status: nil,
        status: 'failed',
        content: "An error occurred: #{error.message}. Please try again.",
        conversation_flow: preserved_flow  # Explicitly preserve
      )
      
      # Track error in analytics (disabled for now - class not implemented)
      # Analytics::EventTracker.new.track_event(
      #   'app_generation_failed',
      #   app_id: app.id,
      #   error: error.message,
      #   iteration: @iteration_count
      # )
    end
    
    # Removed format_goals_status - no longer using GoalTracker
    
    def format_previous_actions(history)
      return "None yet" if history.empty?
      
      history.last(3).map do |h|
        status = h[:verification][:success] ? '✅ Success' : '❌ Failed'
        confidence = h[:verification][:confidence] ? " (#{(h[:verification][:confidence] * 100).to_i}% confidence)" : ""
        "- Iteration #{h[:iteration]}: #{h[:action][:type]}#{confidence} #{status}"
      end.join("\n")
    end
    
    # Enhanced Context Formatting Methods
    
    def format_recent_operations
      return "" unless @recent_operations&.any?
      
      # Group by file path and show counts
      operation_counts = @recent_operations.group_by { |op| op[:key].split(':').first }.transform_values(&:count)
      repeated_files = operation_counts.select { |file, count| count >= 2 }
      
      if repeated_files.any?
        warning = "⚠️  REPEATED OPERATIONS DETECTED:\n"
        repeated_files.each do |file, count|
          iterations = @recent_operations.select { |op| op[:key].start_with?(file) }.map { |op| op[:iteration] }.join(', ')
          warning += "   #{file}: #{count} operations in iterations #{iterations}\n"
        end
        warning += "   Avoid repeating these operations unless necessary.\n"
        warning
      else
        ""
      end
    end
    
    def format_generated_files(files)
      return "None yet" if files.empty?
      
      # Group by file type for better organization
      grouped = files.group_by { |f| ::File.extname(f.path) }
      
      result = []
      grouped.each do |ext, group|
        type_label = case ext
        when '.tsx' then "React Components (#{group.count})"
        when '.ts' then "TypeScript Files (#{group.count})"
        when '.json' then "Config Files (#{group.count})"
        when '.css' then "Stylesheets (#{group.count})"
        else "#{ext} Files (#{group.count})"
        end
        
        result << "#{type_label}:"
        group.each { |f| result << "  - #{f.path}" }
      end
      
      result.join("\n")
    end
    
    def format_verification_results(result)
      return "None yet" unless result
      
      if result[:success]
        "✅ Success (#{(result[:confidence] * 100).to_i}% confidence)"
      else
        error_info = result[:errors]&.any? ? " - #{result[:errors].count} errors" : ""
        "❌ Failed (#{(result[:confidence] * 100).to_i}% confidence)#{error_info}"
      end
    end
    
    def check_stagnation_warnings
      return "" if @iteration_count < 3
      
      warnings = []
      
      # Check for low file generation progress
      files_generated = @agent_state[:generated_files].count
      if @iteration_count >= 5 && files_generated < 3
        warnings << "⚠️  LOW PROGRESS WARNING: Only #{files_generated} files generated after #{@iteration_count} iterations"
      end
      
      # Check verification confidence trend
      if @agent_state[:verification_results].count >= 3
        recent_confidence = @agent_state[:verification_results].last(3).map { |r| r[:confidence] || 0 }
        avg_confidence = recent_confidence.sum / recent_confidence.count.to_f
        if avg_confidence < 0.4
          warnings << "⚠️  LOW CONFIDENCE TREND: Average #{(avg_confidence * 100).to_i}% over last 3 verifications"
        end
      end
      
      warnings.any? ? "\n\nWARNINGS:\n#{warnings.join("\n")}" : ""
    end
    
    def generate_iteration_guidance
      guidance = []
      
      # Stage-specific guidance based on iteration
      case @iteration_count
      when 1..2
        guidance << "📋 SETUP PHASE: Focus on project structure and dependencies"
      when 3..5
        guidance << "🏗️  BUILD PHASE: Implement core features and components"
      when 6..8
        guidance << "🔍 REFINEMENT PHASE: Test, debug, and optimize"
      else
        guidance << "🚀 COMPLETION PHASE: Finalize and deploy"
      end
      
      # Progress-based guidance
      files_count = @agent_state[:generated_files].count
      if files_count >= 5
        guidance << "✨ GOOD PROGRESS: #{files_count} files created - focus on quality over quantity"
      elsif @iteration_count >= 5 && files_count < 3
        guidance << "📝 FOCUS NEEDED: Consider creating more substantial implementation"
      end
      
      guidance.join("\n")
    end
    
    # Stub methods for component classes that need to be implemented
    
    def build_planning_prompt
      "Create a detailed implementation plan for: #{@chat_message.content}"
    end
    
    def extract_implementation_plan(response)
      # Extract structured plan from AI response
      { steps: [], components: [], integrations: [] }
    end
    
    def generate_file_content(tool, template_path)
      file_path = tool[:file_path]
      base_content = nil
      
      # First try to get content from AppVersion v1.0.0
      template_version = get_or_create_template_version
      if template_version
        template_file = template_version.app_version_files
                                      .joins(:app_file)
                                      .find_by(app_files: { path: file_path })
        base_content = template_file.app_file.content if template_file
      end
      
      # Fallback to template directory
      if base_content.nil?
        template_file_path = ::File.join(template_path, file_path)
        base_content = ::File.read(template_file_path) if ::File.exist?(template_file_path)
      end
      
      if base_content
        # If it's a static file (like package.json, tsconfig), use as-is
        return base_content if static_file?(file_path)
        
        # For dynamic files, enhance with AI based on requirements
        enhance_prompt = build_file_enhancement_prompt(file_path, base_content, tool[:description])
        response = call_ai_with_context(enhance_prompt)
        
        response[:content] || base_content
      else
        # Generate from scratch using AI
        generation_prompt = build_file_generation_prompt(file_path, tool[:description])
        response = call_ai_with_context(generation_prompt)
        
        response[:content] || default_file_content(file_path)
      end
    end
    
    def static_file?(path)
      # Files that should be used as-is from template
      static_files = [
        'package.json',
        'tsconfig.json',
        'vite.config.ts',
        'tailwind.config.ts',
        'postcss.config.js',
        '.gitignore',
        'index.html'
      ]
      
      static_files.include?(::File.basename(path))
    end
    
    def build_file_enhancement_prompt(path, base_content, description)
      <<~PROMPT
        Enhance the following #{::File.extname(path)} file based on the requirements.
        
        Current file (#{path}):
        ```
        #{base_content}
        ```
        
        Requirements: #{description}
        User's original request: #{@chat_message.content}
        
        Modify the file to implement the requested functionality while maintaining the existing structure and patterns.
        Return ONLY the complete file content, no explanations.
      PROMPT
    end
    
    def build_file_generation_prompt(path, description)
      <<~PROMPT
        Generate a #{::File.extname(path)} file for path: #{path}
        
        Requirements: #{description}
        User's original request: #{@chat_message.content}
        
        Technology stack: React, TypeScript, Vite, Tailwind CSS, Supabase
        
        Return ONLY the complete file content, no explanations.
        Follow best practices and modern patterns.
      PROMPT
    end
    
    def default_file_content(path)
      # Fallback content for common files
      case ::File.basename(path)
      when 'App.tsx'
        <<~TSX
        import React from 'react';

        function App() {
          return (
            <div className="min-h-screen bg-gray-50">
              <div className="container mx-auto px-4 py-8">
                <h1 className="text-3xl font-bold text-gray-900">
                  Welcome to Your App
                </h1>
              </div>
            </div>
          );
        }

        export default App;
        TSX
      when 'main.tsx'
        <<~TSX
        import React from 'react';
        import ReactDOM from 'react-dom/client';
        import App from './App';
        import './index.css';

        ReactDOM.createRoot(document.getElementById('root')!).render(
          <React.StrictMode>
            <App />
          </React.StrictMode>
        );
        TSX
      else
        "// Generated file: #{path}\n"
      end
    end
    
    def store_generated_file(path, content)
      # Validation is now handled in AiToolService.write_file
      # This ensures validation happens for ALL file writes, not just during initial generation
      app.app_files.create!(
        path: path,
        content: content,
        file_type: determine_file_type(path),
        team: app.team
      )
    end
    
    def determine_file_type(path)
      case path
      when /\.html?$/ then 'html'
      when /\.tsx?$/ then 'typescript'
      when /\.jsx?$/ then 'javascript'
      when /\.css$/ then 'css'
      when /\.json$/ then 'json'
      else 'text'
      end
    end
    
    def validate_and_fix_typescript(path, content)
      # Auto-fix common TypeScript/JavaScript syntax errors
      fixed = content.dup
      
      # Fix unescaped quotes in string literals
      # Pattern: strings containing code examples with quotes
      fixed.gsub!(/"System\.out\.println\("([^"]*)"\);"/, '"System.out.println(\"\1\");"')
      fixed.gsub!(/"std::cout\s*<<\s*"([^"]*)"([^"]*);"/,  '"std::cout << \"\1\"\2;"')
      fixed.gsub!(/"fmt\.Println\("([^"]*)"\)"/, '"fmt.Println(\"\1\")"')
      fixed.gsub!(/"println!\("([^"]*)"\);"/, '"println!(\"\1\");"')
      
      # Log if we made changes
      if fixed != content
        Rails.logger.info "[AppBuilderV5] Auto-fixed TypeScript syntax in #{path}"
        Rails.logger.info "[AppBuilderV5] Fixed unescaped quotes in string literals"
        
        # Add system message about the fix
        if @user_message
          @app.app_chat_messages.create!(
            role: 'system',
            content: "🔧 Auto-fixed TypeScript syntax errors in #{path} (unescaped quotes)",
            status: 'completed'
          )
        end
      end
      
      fixed
    end
    
    def validate_typescript_file(file)
      # Legacy method kept for compatibility
      { valid: true, errors: [] }
    end
    
    def validate_dependencies(file)
      # TODO: Implement dependency validation
      { valid: true, errors: [] }
    end
    
    def attempt_build
      # TODO: Implement build attempt
      { success: true, errors: [] }
    end
    
    def build_fix_prompt(issue)
      "Fix the following issue: #{issue}"
    end
    
    def apply_file_fix(update)
      # Apply fix to file
    end
    
    def perform_final_validation
      # Final validation checks
      { success: true }
    end
    
    def request_user_feedback(action)
      # Handle user feedback request
      { type: :feedback_requested }
    end
    
    def handle_unknown_action(action)
      Rails.logger.warn "[AppBuilderV5] Unknown action type: #{action[:type]}"
      { type: :unknown_action, error: "Unknown action: #{action[:type]}" }
    end
    
    def update_existing_file(tool)
      # Handle file updates
      { type: :file_updated, path: tool[:file_path] }
    end
    
    def create_ui_component(tool)
      # Handle UI component creation
      { type: :component_created, name: tool[:component_name] }
    end
    
    def setup_integration(tool)
      # Handle integration setup
      { type: :integration_setup, name: tool[:integration_name] }
    end
    
    # V5 UI Integration Methods - Save & Broadcast Pattern
    
    def create_assistant_message
      # Find existing assistant placeholder created by App#initiate_generation!
      # This ensures Action Cable updates work from the start
      # Use a more relaxed time window to handle timing issues (within 5 seconds)
      Rails.logger.debug "[V5_DEBUG] @chat_message.created_at: #{@chat_message.created_at.inspect}"
      
      # Safety check for nil created_at
      if @chat_message.created_at.nil?
        Rails.logger.error "[V5_ERROR] @chat_message.created_at is nil! Message ID: #{@chat_message.id}"
        search_time = Time.current - 5.seconds
      else
        search_time = @chat_message.created_at - 5.seconds
      end
      
      Rails.logger.debug "[V5_DEBUG] Searching for assistant messages >= #{search_time}"
      
      existing_assistant = @app.app_chat_messages
        .where(role: 'assistant')
        .where('created_at >= ?', search_time)
        .where(status: 'executing')
        .order(created_at: :desc)
        .first
      
      if existing_assistant
        Rails.logger.info "[V5_INIT] Using existing assistant placeholder ##{existing_assistant.id}"
        Rails.logger.debug "[V5_DEBUG] Placeholder created at: #{existing_assistant.created_at}, chat message at: #{@chat_message.created_at}"
        existing_assistant
      else
        # Log why we couldn't find a placeholder
        Rails.logger.warn "[V5_INIT] No placeholder found, creating new assistant message"
        Rails.logger.debug "[V5_DEBUG] Searched for assistant messages after #{search_time}"
        Rails.logger.debug "[V5_DEBUG] Found assistant messages: #{@app.app_chat_messages.where(role: 'assistant').pluck(:id, :created_at, :status).inspect}"
        
        # Fallback: create new message if none exists
        AppChatMessage.create!(
          app: @app,
          user: @chat_message.user,
          role: 'assistant',
          content: 'Thinking..', # Required field
          status: 'executing',
          iteration_count: 0,
          tool_calls: [],
          conversation_flow: [],
          thinking_status: "Initializing Overskill AI...",
          is_code_generation: false
        )
      end
    end
    
    def update_thinking_status(status, seconds = nil)
      @assistant_message.thinking_status = status
      @assistant_message.thought_for_seconds = seconds
      @assistant_message.save!
    end
    
    # Helper to update the last text content entry during streaming
    def update_last_text_content(new_content)
      return unless @assistant_message.conversation_flow.present?
      
      # Find the last content entry and update it
      @assistant_message.conversation_flow.reverse_each do |entry|
        if entry['type'] == 'content'
          entry['content'] = new_content
          entry['updated_at'] = Time.current.iso8601
          break
        end
      end
      
      # Save and broadcast the update
      @assistant_message.save!
      broadcast_conversation_update
    end
    
    def add_loop_message(content, type: 'content', thinking_blocks: nil)
      # Add thinking blocks as separate messages in conversation flow
      if thinking_blocks&.any?
        thinking_blocks.each do |block|
          # Use 'thinking' field, not 'content' (per API spec)
          thinking_content = block['thinking'] || block[:thinking]
          next if thinking_content.blank?
          
          thinking_message = {
            'content' => thinking_content,  # Store internally as 'content' for display
            'type' => 'thinking',
            'iteration' => @iteration_count,
            'timestamp' => Time.current.iso8601,
            'signature' => block['signature'] || block[:signature] || "sig_#{SecureRandom.hex(8)}"
          }
          
          
          # Add to conversation_flow for display
          add_to_conversation_flow(
            type: 'thinking',
            content: thinking_content  # Pass just the content string, not the whole message hash
          )
          
          Rails.logger.info "[V5_THINKING] Added thinking block to conversation flow (#{thinking_content.length} chars)"
        end
      end
      
      # Add the main content message if present
      if content.present?
        loop_message = {
          'content' => content,
          'type' => type,
          'iteration' => @iteration_count,
          'timestamp' => Time.current.iso8601
        }
        
        
        # Also add to conversation_flow for interleaved display
        add_to_conversation_flow(
          type: type == 'status' ? 'status' : 'message',
          content: content  # Pass just the content string, not the whole message hash
        )
      end
      
      @assistant_message.save!
    end
    
    def add_tool_call(tool_name, file_path: nil, status: 'complete')
      tool_call = {
        'name' => tool_name,
        'file_path' => file_path,
        'status' => status,
        'timestamp' => Time.current.iso8601
      }
      
      # Must reassign the array for ActiveRecord to detect the change in JSONB field
      @assistant_message.tool_calls = @assistant_message.tool_calls + [tool_call]
      
      # Accumulate tool calls for batching
      @pending_tool_calls ||= []
      @pending_tool_calls << tool_call.dup  # Use dup to avoid reference issues
      
      # Don't flush immediately - let the caller decide when to flush
      @assistant_message.save!
    end
    
    def flush_pending_tool_calls
      return if @pending_tool_calls.blank?
      
      # Add all pending tool calls to conversation_flow as a batch
      add_to_conversation_flow(
        type: 'tools',
        tool_calls: @pending_tool_calls.dup
      )
      
      @pending_tool_calls = []
    end
    
    def update_tool_status_to_error(tool_name, file_path, error_message)
      # Immediately update tool status to error when exception occurs
      if @assistant_message.present? && @assistant_message.tool_calls.present?
        updated_tool_calls = @assistant_message.tool_calls.deep_dup
        
        # Find the running tool and update to error
        updated_tool_calls.reverse.each do |tc|
          if tc['name'] == tool_name && 
             tc['file_path'] == file_path && 
             tc['status'] == 'running'
            tc['status'] = 'error'
            tc['error'] = error_message
            break
          end
        end
        
        # Save immediately to prevent stuck "running" status
        @assistant_message.tool_calls = updated_tool_calls
        @assistant_message.save!
        
        # Also update in conversation flow
        update_tool_status_in_flow(tool_name, file_path, 'error')
        
        Rails.logger.info "[V5_TOOLS] Updated tool status to error: #{tool_name} #{file_path}"
      end
    end
    
    def update_tool_status_in_flow(tool_name, file_path, new_status)
      # Update the status in conversation_flow when tool completes
      return unless @assistant_message.conversation_flow.present?
      
      Rails.logger.info "[V5_FLOW_UPDATE] Starting update for tool: #{tool_name}, file: #{file_path}, new_status: #{new_status}"
      
      # Clone the array to trigger change detection
      updated_flow = @assistant_message.conversation_flow.deep_dup
      found_and_updated = false
      
      updated_flow.each_with_index do |item, idx|
        next unless item['type'] == 'tools'
        
        # Support both 'calls' (legacy) and 'tools' (SimpleToolStreamer) arrays
        tools_array = item['calls'] || item['tools'] || []
        
        if tools_array.present?
          tools_array.each do |tool|
            # Log what we're comparing
            Rails.logger.debug "[V5_FLOW_UPDATE] Checking tool: name=#{tool['name']} vs #{tool_name}, file=#{tool['file_path']} vs #{file_path}"
            
            # Handle matching logic for tools with and without file_path
            name_matches = tool['name'] == tool_name
            
            # For tools like rename-app that don't have file_path, match on name only
            # For file-based tools, require both name and file_path to match
            file_matches = if file_path.nil? && tool['file_path'].nil?
                             true  # Both are nil, this is a non-file-based tool like rename-app
                           elsif file_path.nil? || tool['file_path'].nil?
                             false # One is nil, the other isn't - no match
                           else
                             tool['file_path'] == file_path # Both present, compare them
                           end
            
            if name_matches && file_matches
              Rails.logger.info "[V5_FLOW_UPDATE] Found match! Updating from #{tool['status']} to #{new_status}"
              tool['status'] = new_status
              found_and_updated = true
            end
          end
        end
      end
      
      if found_and_updated
        # Reassign to trigger ActiveRecord change detection for JSONB field
        @assistant_message.conversation_flow = updated_flow
        @assistant_message.save!
        Rails.logger.info "[V5_FLOW_UPDATE] ✅ Updated conversation_flow for #{tool_name}(#{file_path}) -> #{new_status}"
        
        # Broadcast UI update for real-time streaming
        broadcast_message_update
      else
        Rails.logger.warn "[V5_FLOW_UPDATE] ❌ No matching tool found to update in conversation_flow for #{tool_name}(#{file_path})"
        
        # Debug: show what tools we actually have
        if @assistant_message.conversation_flow.present?
          @assistant_message.conversation_flow.each do |item|
            next unless item['type'] == 'tools'
            tools_array = item['tools'] || item['calls'] || []
            Rails.logger.debug "[V5_FLOW_UPDATE] Available tools: #{tools_array.map { |t| "#{t['name']}(#{t['file_path']})" }.join(', ')}"
          end
        end
      end
    end
    
    def update_iteration_count
      @assistant_message.iteration_count = @iteration_count
      @assistant_message.save!
    end
    
    def finalize_with_app_version(app_version)
      # Preserve conversation flow before updating
      preserved_flow = @assistant_message.conversation_flow
      
      @assistant_message.app_version = app_version
      @assistant_message.is_code_generation = true
      @assistant_message.status = 'completed'
      @assistant_message.thinking_status = nil
      
      # Ensure conversation_flow is preserved during finalization
      @assistant_message.conversation_flow = preserved_flow if preserved_flow.present?
      
      @assistant_message.save!
      
      # Broadcast the final update
      broadcast_message_update
    end
    
    def mark_as_discussion_only
      # Preserve conversation flow before updating
      preserved_flow = @assistant_message.conversation_flow
      
      @assistant_message.is_code_generation = false
      @assistant_message.status = 'completed'
      @assistant_message.thinking_status = nil
      
      # Ensure conversation_flow is preserved during finalization
      @assistant_message.conversation_flow = preserved_flow if preserved_flow.present?
      
      @assistant_message.save!
      
      # Broadcast the final update
      broadcast_message_update
    end
    
    # Create AppVersion for generated code - tracks changes from previous version
    def create_app_version_for_generation
      Rails.logger.info "[V5_VERSION] Creating AppVersion for generated code"
      
      # Get the most recent version to build upon
      previous_version = @app.app_versions.order(:created_at).last
      
      # Calculate next version number
      if previous_version
        current_version = previous_version.version_number.gsub('v', '').split('.').map(&:to_i)
        current_version[1] += 1  # Increment minor version
        next_version = "v#{current_version.join('.')}"
      else
        next_version = "v1.0.0"  # First version if no template exists
      end
      
      # Create the version
      version = @app.app_versions.create!(
        version_number: next_version,
        team: @app.team,
        user: @chat_message.user,
        changelog: "AI-generated changes: #{@chat_message.content.truncate(100)}",
        deployed: true,
        external_commit: false,
        published_at: Time.current,
        environment: 'preview',
        ai_tokens_input: @total_tokens_input || 0,
        ai_tokens_output: @total_tokens_output || 0,
        ai_model_used: 'claude-sonnet-4',
        metadata: {
          generated_files: @app.app_files.count,
          changes_from_previous: 0,  # Will be updated below
          iterations: @iteration_count,
          preview_url: @app.preview_url,
          based_on_version: previous_version&.version_number
        }
      )
      
      changes_count = 0
      
      if previous_version
        # Build index of files from previous version
        previous_files = {}
        previous_version.app_version_files.includes(:app_file).each do |vf|
          # Use the path from app_file if exists, or from metadata if file was deleted
          path = vf.app_file&.path || vf.metadata&.dig('deleted_path')
          previous_files[path] = vf.content if path
        end
        
        # Track changes in current version
        current_files = @app.app_files.index_by(&:path)
        
        # Check each current file against previous version
        current_files.each do |path, file|
          if previous_files[path]
            # File existed in previous version - check if modified
            if previous_files[path] != file.content
              # File was modified
              version.app_version_files.create!(
                app_file: file,
                action: 'updated',
                content: file.content
              )
              changes_count += 1
            else
              # File unchanged - still include for complete version snapshot
              version.app_version_files.create!(
                app_file: file,
                action: 'unchanged',
                content: file.content
              )
            end
          else
            # New file not in previous version
            version.app_version_files.create!(
              app_file: file,
              action: 'created',
              content: file.content
            )
            changes_count += 1
          end
        end
        
        # Track deleted files
        previous_files.each do |path, content|
          unless current_files[path]
            # File was deleted
            version.app_version_files.create!(
              app_file_id: nil,  # File no longer exists
              action: 'deleted',
              content: content,  # Preserve the deleted content
              metadata: { deleted_path: path }
            )
            changes_count += 1
          end
        end
      else
        # First version - all files are new
        @app.app_files.each do |file|
          version.app_version_files.create!(
            app_file: file,
            action: 'created',
            content: file.content
          )
          changes_count += 1
        end
      end
      
      # Update metadata with actual change count
      version.update!(metadata: version.metadata.merge(changes_from_previous: changes_count))
      
      Rails.logger.info "[V5_VERSION] Created AppVersion #{next_version} with #{version.app_version_files.count} file records"
      Rails.logger.info "[V5_VERSION] Changes: #{version.app_version_files.where(action: 'created').count} new, #{version.app_version_files.where(action: 'updated').count} modified, #{version.app_version_files.where(action: 'deleted').count} deleted, #{version.app_version_files.where(action: 'unchanged').count} unchanged"
      
      # Create GitHub tag for version control and restoration capability
      begin
        if @app.repository_name.present?
          tagging_service = Deployment::GithubVersionTaggingService.new(version)
          tag_result = tagging_service.create_version_tag
          
          if tag_result[:success]
            Rails.logger.info "[V5_VERSION] Created GitHub tag: #{tag_result[:tag_name]}"
          else
            Rails.logger.warn "[V5_VERSION] Failed to create GitHub tag: #{tag_result[:error]}"
          end
        end
      rescue => e
        Rails.logger.error "[V5_VERSION] GitHub tagging error: #{e.message}"
        # Don't fail the build if tagging fails
      end
      
      version
    end
    
    # Validate tool calling structure follows Anthropic requirements
    def validate_tool_calling_structure(messages)
      # Check for assistant tool_use followed by user tool_result pattern
      messages.each_cons(2) do |msg1, msg2|
        if msg1[:role] == 'assistant' && msg1[:content].is_a?(Array)
          tool_use_blocks = msg1[:content].select { |b| b[:type] == 'tool_use' }
          
          if tool_use_blocks.any? && msg2[:role] == 'user' && msg2[:content].is_a?(Array)
            tool_result_blocks = msg2[:content].select { |b| b[:type] == 'tool_result' }
            
            # Verify IDs match
            tool_use_ids = tool_use_blocks.map { |b| b[:id] }.sort
            tool_result_ids = tool_result_blocks.map { |b| b[:tool_use_id] }.sort
            
            if tool_use_ids != tool_result_ids
              Rails.logger.warn "[V5_TOOLS] Tool ID mismatch!"
              Rails.logger.warn "  Tool use IDs: #{tool_use_ids.join(', ')}"
              Rails.logger.warn "  Tool result IDs: #{tool_result_ids.join(', ')}"
            else
              Rails.logger.debug "[V5_TOOLS] ✅ Tool structure valid: #{tool_use_ids.size} tools with matching IDs"
            end
          end
        end
      end
    end
    
    # Add entry to conversation_flow for interleaved display
    def add_to_conversation_flow(type:, content: nil, tool_calls: nil, iteration: nil)
      @assistant_message.conversation_flow ||= []
      
      # CRITICAL FIX: Check if a tools entry already exists (created by SimpleToolStreamer)
      # If it does, update it instead of creating a duplicate
      if type == 'tools'
        existing_tools_entry = @assistant_message.conversation_flow.reverse.find { |item| item['type'] == 'tools' }
        
        if existing_tools_entry && tool_calls.present?
          Rails.logger.info "[V5_FLOW_DEBUG] BEFORE MERGE: existing tools count: #{existing_tools_entry['tools']&.size || 0}"
          existing_tools_entry['tools']&.each_with_index do |tool, i|
            Rails.logger.info "[V5_FLOW_DEBUG]   Existing[#{i}]: #{tool['name']} | #{tool['file_path']} | #{tool['status']}"
          end
          
          Rails.logger.info "[V5_FLOW_DEBUG] INCOMING tool_calls count: #{tool_calls.size}"
          tool_calls.each_with_index do |tc, i|
            Rails.logger.info "[V5_FLOW_DEBUG]   Incoming[#{i}]: #{tc['name']} | #{tc['file_path']} | #{tc['status']}"
          end
          
          # Update the existing entry's calls/tools array
          # Use 'tools' key for consistency with SimpleToolStreamer
          existing_tools_entry['tools'] ||= []
          original_count = existing_tools_entry['tools'].size
          
          # Append new tool calls to existing ones
          tool_calls.each_with_index do |tc, incoming_index|
            # CRITICAL FIX: Don't merge based on name+file_path - this can cause data loss
            # Instead, use a more specific identifier or always append
            existing_tool = existing_tools_entry['tools'].find { |t| 
              t['name'] == tc['name'] && 
              t['file_path'] == tc['file_path'] &&
              t['index'] == tc['index']  # Include index to be more specific
            }
            
            if existing_tool
              Rails.logger.info "[V5_FLOW_DEBUG] MERGING tool #{incoming_index}: #{tc['name']} (found existing with index #{existing_tool['index']})"
              existing_tool.merge!(tc)
            else
              Rails.logger.info "[V5_FLOW_DEBUG] APPENDING new tool #{incoming_index}: #{tc['name']}"
              existing_tools_entry['tools'] << tc
            end
          end
          
          # Must reassign array for ActiveRecord to detect change
          @assistant_message.conversation_flow = @assistant_message.conversation_flow.deep_dup
          @assistant_message.save!
          
          Rails.logger.info "[V5_FLOW_DEBUG] AFTER MERGE: total tools: #{existing_tools_entry['tools'].size} (was #{original_count})"
          existing_tools_entry['tools'].each_with_index do |tool, i|
            Rails.logger.info "[V5_FLOW_DEBUG]   Final[#{i}]: #{tool['name']} | #{tool['file_path']} | #{tool['status']} | index:#{tool['index']}"
          end
          
          return
        end
      end
      
      # FIX: Add small delay between conversation flow entries to ensure unique timestamps
      # This prevents ordering ambiguity when tools and messages are logged simultaneously
      if @last_flow_timestamp && (Time.current.to_f - @last_flow_timestamp) < 0.001
        # If less than 1ms has passed, add a small delay
        sleep(0.1)  # 100ms delay ensures clear chronological ordering
        Rails.logger.debug "[V5_FLOW] Added 100ms delay for timestamp ordering"
      end
      
      # Use ISO8601 with millisecond precision for better granularity
      current_timestamp = Time.current.iso8601(3)
      @last_flow_timestamp = Time.current.to_f
      
      flow_entry = {
        'type' => type,
        'iteration' => iteration || @iteration_count,
        'timestamp' => current_timestamp
      }
      
      Rails.logger.info "[V5_FLOW] Adding to conversation_flow: type=#{type}, flow_size=#{@assistant_message.conversation_flow.size}"
      
      case type
      when 'message'
        flow_entry['content'] = content
        flow_entry['thinking_blocks'] = content.is_a?(Hash) ? content['thinking_blocks'] : nil
      when 'tools'
        # CRITICAL FIX: Use 'tools' instead of 'calls' for consistency with SimpleToolStreamer
        # CRITICAL FIX: Don't add empty tool arrays - they cause consecutive assistant messages
        tools_to_add = tool_calls || []
        if tools_to_add.empty?
          Rails.logger.warn "[V5_FLOW] Skipping empty tools entry - would cause consecutive assistant messages"
          # Don't add the flow entry, but continue with the method to avoid breaking streaming
          @assistant_message.save! if @assistant_message.changed?
          Rails.logger.info "[V5_FLOW] Skipped empty tools, conversation_flow size remains: #{@assistant_message.conversation_flow.size}"
          return  # Exit early but after saving any pending changes
        end
        flow_entry['tools'] = tools_to_add
      when 'status'
        flow_entry['content'] = content
      when 'error'
        flow_entry['content'] = content
      end
      
      # Must reassign the array for ActiveRecord to detect the change in JSONB field
      @assistant_message.conversation_flow = @assistant_message.conversation_flow + [flow_entry]
      @assistant_message.save!
      
      Rails.logger.info "[V5_FLOW] Saved conversation_flow, new size: #{@assistant_message.conversation_flow.size}"
    end
    
    # Template version methods are deprecated - templates are now copied on app creation
    # Keeping minimal stubs for backwards compatibility
    def get_or_create_template_version
      Rails.logger.warn "[V5_DEPRECATED] get_or_create_template_version called - templates are now copied on app creation"
      nil
    end
    
    def template_files_exist?
      Rails.logger.warn "[V5_DEPRECATED] template_files_exist called - templates are now copied on app creation"
      true # Always return true since files are copied on creation
    end
    
    def create_template_version_from_files
      Rails.logger.warn "[V5_DEPRECATED] create_template_version_from_files called - templates are now copied on app creation"
      nil
    end
    
    def log_claude_event(event_type, details = {})
      # Format for easy grep filtering: [V5_CLAUDE]
      Rails.logger.info "[V5_CLAUDE] #{event_type} | #{format_log_details(details)}"
    end
    
    def format_log_details(details)
      details.map { |k, v| "#{k}=#{v.to_s.truncate(200)}" }.join(" | ")
    end
    
    # Goal Progress and Loop Detection Methods
    
    # Simplified progress tracking - let Claude determine completion naturally
    def update_progress_tracking(result)
      return unless result && result[:type]
      
      # Log significant operations for debugging
      case result[:type]
      when :tools_executed
        files_created = result[:data]&.count { |r| r[:success] && r[:path] } || 0
        Rails.logger.info "[V5_PROGRESS] #{files_created} files created/modified in iteration #{@iteration_count}"
        
      when :verification_complete
        success = result[:data]&.dig(:build_successful)
        Rails.logger.info "[V5_PROGRESS] Verification #{success ? 'passed' : 'failed'}"
        
      when :generation_complete
        Rails.logger.info "[V5_PROGRESS] Generation marked complete by agent"
      end
    end
    
    def foundation_file_created?(result)
      return false unless result[:path]
      foundation_files = ['package.json', 'tsconfig.json', 'vite.config.ts', 'src/main.tsx', 'src/App.tsx']
      foundation_files.any? { |file| result[:path].include?(file) }
    end
    
    def feature_file_created?(result)
      return false unless result[:path]
      # Look for app-specific feature files (components, pages, etc.)
      feature_indicators = ['component', 'Component', 'page', 'Page', 'Todo', 'Task', 'List']
      feature_indicators.any? { |indicator| result[:path].include?(indicator) }
    end
    
    def loop_detected?(result)
      return false if @iteration_count < 3
      
      # Track recent operations and failures
      @recent_operations ||= []
      @failed_operations ||= {}
      
      if result[:type] == :tools_executed && result[:data]
        result[:data].each do |operation|
          # Track failed operations to prevent retrying them
          if operation[:status] == 'error' || operation[:status] == 'failed'
            operation_key = "#{operation[:name]}:#{operation[:path] || 'no-path'}"
            @failed_operations[operation_key] ||= 0
            @failed_operations[operation_key] += 1
            
            # If same operation failed 3+ times, it's a loop
            if @failed_operations[operation_key] >= 3
              Rails.logger.error "[V5_LOOP_DETECT] Operation #{operation_key} has failed #{@failed_operations[operation_key]} times - stopping to prevent infinite retry loop"
              add_loop_message("Operation '#{operation[:name]}' has failed multiple times. Stopping to prevent infinite retry.", type: 'error')
              return true
            end
          end
          
          next unless operation[:path]
          
          operation_key = "#{operation[:path]}:#{operation[:type] || 'write'}"
          @recent_operations << {
            key: operation_key,
            iteration: @iteration_count,
            timestamp: Time.current,
            status: operation[:status]
          }
        end
        
        # Keep only recent operations (last 10 iterations)
        @recent_operations = @recent_operations.select { |op| op[:iteration] > @iteration_count - 10 }
        
        # Detect loops - same file written multiple times in recent iterations
        operation_counts = @recent_operations.group_by { |op| op[:key] }.transform_values(&:count)
        repetitive_operations = operation_counts.select { |key, count| count >= 3 }
        
        if repetitive_operations.any?
          Rails.logger.warn "[V5_LOOP_DETECT] Repetitive operations detected: #{repetitive_operations.keys.join(', ')}"
          log_loop_details(repetitive_operations)
          return true
        end
      end
      
      # Check for iteration counter restarting (mentioned by user)
      if @iteration_count < (@last_iteration_count || 0)
        Rails.logger.error "[V5_LOOP_DETECT] Iteration counter restarted! Current: #{@iteration_count}, Last: #{@last_iteration_count}"
        return true
      end
      @last_iteration_count = @iteration_count
      
      false
    end
    
    def log_loop_details(repetitive_operations)
      repetitive_operations.each do |operation_key, count|
        recent_ops = @recent_operations.select { |op| op[:key] == operation_key }
        iterations = recent_ops.map { |op| op[:iteration] }.join(', ')
        Rails.logger.warn "[V5_LOOP_DETECT] #{operation_key} repeated #{count} times in iterations: #{iterations}"
      end
    end
    
    def assess_loop_risk
      return :low if (@recent_operations&.count || 0) < 2
      
      operation_counts = @recent_operations.group_by { |op| op[:key] }.transform_values(&:count)
      max_repetitions = operation_counts.values.max || 0
      
      case max_repetitions
      when 0..1 then :low
      when 2 then :medium
      else :high
      end
    end

    # Determine when to flush tool calls incrementally for better UX
    def should_flush_incrementally?(index, total_tools)
      return false # TODO: Investigate why rename-app fails everytime, seeing if this is the issue
      # Strategy: Show progress frequently for better UX while avoiding spam
      case total_tools
      when 1..2
        # For 1-2 tools, flush immediately after each
        true
      when 3..5
        # For 3-5 tools, flush after first tool, then every 2 tools
        index == 0 || (index + 1) % 2 == 0 || index == total_tools - 1
      when 6..10
        # For 6-10 tools, flush after first tool, then every 3 tools  
        index == 0 || (index + 1) % 3 == 0 || index == total_tools - 1
      else
        # For 11+ tools, flush after first, then every 4 tools (more batching for performance)
        index == 0 || (index + 1) % 4 == 0 || index == total_tools - 1
      end
    end

    # Broadcast message update for incremental tool call progress
    def broadcast_message_update
      return unless @assistant_message && @app
      
      Rails.logger.info "[V5_BROADCAST] Broadcasting incremental message update for message #{@assistant_message.id}"
      
      # Broadcast the updated message to the chat channel for real-time tool progress
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "app_chat_message_#{@assistant_message.id}",
        partial: "account/app_editors/agent_reply_v5",
        locals: { message: @assistant_message, app: @app }
      )
    rescue => e
      Rails.logger.error "[V5_BROADCAST] Failed to broadcast incremental message update: #{e.message}"
    end

    # Broadcast conversation update for real-time text streaming
    def broadcast_conversation_update
      return unless @assistant_message && @app
      
      Rails.logger.info "[V5_BROADCAST] Broadcasting conversation update for text streaming"
      
      # Broadcast the updated message to show streaming text
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "app_chat_message_#{@assistant_message.id}",
        partial: "account/app_editors/agent_reply_v5",
        locals: { message: @assistant_message, app: @app }
      )
    rescue => e
      Rails.logger.error "[V5_BROADCAST] Failed to broadcast conversation update: #{e.message}"
    end
    
    # Broadcast preview frame update when app is deployed
    def broadcast_preview_frame_update
      return unless @app&.preview_url.present?
      
      Rails.logger.info "[V5_BROADCAST] Broadcasting preview frame update for app #{@app.id}"
      
      # Broadcast to the app channel that users are subscribed to
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}",
        target: "preview_frame",
        partial: "account/app_editors/preview_frame",
        locals: { app: @app }
      )
      
      # Also broadcast a refresh action to the chat channel for better UX
      Turbo::StreamsChannel.broadcast_action_to(
        "app_#{@app.id}_chat",
        action: "refresh",
        target: "preview_frame"
      )
    rescue => e
      Rails.logger.error "[V5_BROADCAST] Failed to broadcast preview frame update: #{e.message}"
    end
    
    # ENHANCEMENT 2: Verify tool success to prevent AI false positive reporting
    def verify_tool_success(tool_name, result, tool_args)
      # If result already indicates error, it's clearly not successful
      return false if result[:error].present?
      
      # Default to success indication from result
      base_success = result[:success] != false
      
      # Enhanced verification for line-replace operations
      if tool_name == 'os-line-replace'
        # Check for specific failure patterns that indicate blocked syntax fixes
        if result[:message]&.include?("unchanged") || 
           result[:error]&.include?("unchanged") ||
           result[:error]&.include?("duplicate detection")
          Rails.logger.warn "[V5_SUCCESS_VERIFICATION] Line-replace may have failed due to duplicate detection"
          
          # Additional verification: check if the file actually contains the expected content
          file_path = tool_args['file_path']
          replacement = tool_args['replacement'] || tool_args['replace']
          
          if file_path && replacement
            file = @app.app_files.find_by(path: file_path)
            if file && replacement.strip.present?
              # Check if the replacement content is actually in the file
              # This helps detect cases where LineReplaceService blocked needed changes
              normalized_file_content = file.content.gsub(/\s+/, ' ')
              normalized_replacement = replacement.gsub(/\s+/, ' ')
              
              content_actually_present = normalized_file_content.include?(normalized_replacement)
              
              unless content_actually_present
                Rails.logger.error "[V5_SUCCESS_VERIFICATION] Line-replace claimed success but replacement content not found in file"
                Rails.logger.error "[V5_SUCCESS_VERIFICATION] This indicates a false positive success - syntax fix was blocked"
                return false
              end
            end
          end
        end
        
        # For line-replace, also verify success wasn't due to fuzzy matching that didn't help
        if result[:fuzzy_match_used] && result[:message]&.include?("already replaced")
          Rails.logger.info "[V5_SUCCESS_VERIFICATION] Line-replace used fuzzy matching - content may already be correct"
        end
      end
      
      # For write operations, verify the file was actually created/updated
      if tool_name == 'os-write'
        file_path = tool_args['file_path']
        expected_content = tool_args['content']
        
        if file_path && expected_content.present?
          file = @app.app_files.find_by(path: file_path)
          if file.nil?
            Rails.logger.error "[V5_SUCCESS_VERIFICATION] os-write claimed success but file not found: #{file_path}"
            return false
          elsif file.content != expected_content
            Rails.logger.warn "[V5_SUCCESS_VERIFICATION] os-write content differs from expected - may indicate partial success"
          end
        end
      end
      
      # Log verification result for debugging
      Rails.logger.info "[V5_SUCCESS_VERIFICATION] #{tool_name}: base_success=#{base_success}, verified=true"
      base_success
    end
    
    # Broadcast deployment progress updates to the chat message
    def broadcast_deployment_progress(options = {})
      return unless @message
      
      Rails.logger.info "[V5_BROADCAST] Broadcasting deployment progress for message #{@message.id}: #{options[:phase] || options[:status]}"
      
      # Update the message with deployment progress data
      deployment_data = {
        deployment_status: options[:status],
        deployment_progress: options[:progress],
        deployment_phase: options[:phase],
        deployment_type: options[:deployment_type],
        deployment_steps: options[:deployment_steps],
        deployment_eta: options[:deployment_eta],
        deployment_url: options[:deployment_url],
        deployment_error: options[:deployment_error]
      }.compact
      
      # IMPORTANT: Dynamically add deployment attributes to message object for view rendering
      # These methods are checked with respond_to? in _agent_reply_v5.html.erb to avoid NoMethodError
      # when deployment is not active. Non-persistent, just for broadcasting.
      deployment_data.each { |key, value| @message.define_singleton_method(key) { value } }
      
      # Broadcast the updated message to the chat channel
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "app_chat_message_#{@message.id}",
        partial: "account/app_editors/agent_reply_v5",
        locals: { message: @message, app: @app }
      )
      
      # Also broadcast generic deployment update for any other listeners
      ActionCable.server.broadcast(
        "app_#{@app.id}_deployment",
        deployment_data.merge(
          message_id: @message.id,
          timestamp: Time.current.iso8601
        )
      )
    rescue => e
      Rails.logger.error "[V5_BROADCAST] Failed to broadcast deployment progress: #{e.message}"
    end
  end
  
  # Supporting classes have been extracted to separate files:
  # - app/services/ai/context_manager.rb
  # - app/services/ai/agent_decision_engine.rb  
  # - app/services/ai/termination_evaluator.rb
end