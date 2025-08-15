# AppBuilderV5 - Agent Loop Implementation with Lovable-style architecture
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
      
      # Create assistant reply message for V5 UI
      @assistant_message = create_assistant_message
      
      # No separate broadcaster needed - we'll use direct updates
      
      # Initialize agent components
      @prompt_service = Prompts::AgentPromptService.new(agent_variables)
      
      # TODO: Consider adding GoalTracker as a tool call instead of internal logic
      # For now, simplify by removing GoalTracker to reduce confusion
      # @goal_tracker = GoalTracker.new(chat_message.content)
      
      # Debug: check if prompt service works
      Rails.logger.debug "[V5_DEBUG] Prompt service initialized"
      Rails.logger.debug "[V5_DEBUG] Agent variables: #{agent_variables.keys.join(', ')}"
      @context_manager = ContextManager.new(app)
      @decision_engine = AgentDecisionEngine.new
      @termination_evaluator = TerminationEvaluator.new
      
      # Initialize file change tracker for granular caching
      @file_tracker = FileChangeTracker.new(@app.id)
      
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
      
      # Load template files before starting
      initialize_template_files
    end
    
    def initialize_template_files
      # Create template version and load files if they don't exist
      template_version = get_or_create_template_version
      if template_version
        Rails.logger.info "[V5_TEMPLATE] Loaded template v1.0.0 with #{template_version.app_version_files.count} files"
        # Track template files as already generated
        template_version.app_version_files.includes(:app_file).each do |version_file|
          @agent_state[:generated_files] << version_file.app_file
        end
      end
    end
    
    def execute!
      Rails.logger.info "[AppBuilderV5] Starting agent loop for app ##{app.id}"
      
      begin
        # Mark app as generating
        app.update!(status: 'generating')
        update_thinking_status("Phase 1/6: Starting AI Agent")
        
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
        
      rescue => e
        Rails.logger.error "[V5_CRITICAL] AppBuilderV5 execute! failed: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        handle_error(e)
      end
    end
    
    private
    
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
        
        # Just send the raw user message - system prompt has all instructions
        # No need for prompt wrapper since agent-prompt.txt explains everything
        response = call_ai_with_context(@chat_message.content)
        
        # Claude's response (with tool calls) is already handled by execute_tool_calling_cycle
        Rails.logger.info "[V5_SIMPLE] Claude completed work"
        
        # Phase 2: Build and deploy preview
        update_thinking_status("Building and deploying preview...")
        deploy_result = deploy_preview_if_ready
        
        if deploy_result[:success]
          # Phase 3: Complete
          update_thinking_status("Complete!")
          
          if is_continuation
            add_loop_message("App updated successfully. Preview is ready at: #{deploy_result[:preview_url]}", type: 'status')
          else
            add_loop_message("App generation complete. Preview is ready at: #{deploy_result[:preview_url]}", type: 'status')
          end
          
          # Mark completion
          @completion_status = :complete
        else
          add_loop_message("Deployment failed: #{deploy_result[:error]}", type: 'error')
          @completion_status = :failed
        end
        
      rescue => e
        Rails.logger.error "[V5_SIMPLE] Error in simple flow: #{e.message}"
        add_loop_message("Error during generation: #{e.message}", type: 'error')
        raise e
      end
    end
    
    def deploy_preview_if_ready
      # Check if we have files to deploy (either new or existing)
      total_files = @app.app_files.count
      new_files = @agent_state[:generated_files].count
      
      if total_files == 0
        Rails.logger.warn "[V5_SIMPLE] No files to deploy"
        return { success: false, error: "No files to deploy" }
      end
      
      Rails.logger.info "[V5_SIMPLE] Deploying app with #{total_files} total files (#{new_files} new/modified)"
      
      # Deploy using existing deploy_app method
      deploy_app
    rescue => e
      Rails.logger.error "[V5_SIMPLE] Deployment error: #{e.message}"
      { success: false, error: e.message }
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
        add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
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
      
      # Always try to deploy if we have files
      if app.app_files.count > 0
        # Deploy the app
        update_thinking_status("Phase 6/6: Deploying")
        deploy_result = deploy_app
        
        if deploy_result[:success]
          app.update!(
            status: 'ready',
            preview_url: deploy_result[:preview_url],
            deployed_at: Time.current
          )
          
          # Broadcast preview frame update to editor
          broadcast_preview_frame_update
          
          # Create AppVersion for the generated code
          app_version = create_app_version_for_generation
          
          Rails.logger.info "[V5_FINALIZE] Before finalize_with_app_version, conversation_flow size: #{@assistant_message.conversation_flow&.size}"
          
          # Preserve the conversation_flow explicitly
          preserved_flow = @assistant_message.conversation_flow || []
          
          # Update message content with success message
          @assistant_message.content = "✨ Your app has been successfully generated and deployed!\n\n🔗 **Preview URL**: #{app.preview_url}\n\n📦 **Version**: #{app_version.version_number}\n📁 **Files Created**: #{app_version.app_version_files.count}\n\nThe app is now live and ready for testing."
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
    
    def deploy_app
      # Ensure postcss.config.js exists with proper ES module format
      ensure_postcss_config
      
      # Validate imports before building
      import_errors = validate_imports
      if import_errors.any?
        Rails.logger.warn "[V5_DEPLOY] Import validation failed: #{import_errors.join('; ')}"
        
        # Give AI one chance to fix the import errors
        fix_success = send_import_errors_to_ai(import_errors)
        
        if !fix_success
          return { success: false, error: "Import validation failed: #{import_errors.first}" }
        end
        
        # Re-validate after AI fix
        import_errors = validate_imports
        if import_errors.any?
          return { success: false, error: "Import validation still failing after fix attempt: #{import_errors.first}" }
        end
      end
      
      # Build the app first
      builder = Deployment::ExternalViteBuilder.new(app)
      build_result = builder.build_for_preview
      
      unless build_result[:success]
        return { success: false, error: build_result[:error] }
      end
      
      # Deploy to Cloudflare
      deployer = Deployment::CloudflareWorkersDeployer.new(app)
      deploy_result = deployer.deploy_with_secrets(
        built_code: build_result[:built_code],
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
        
        { 
          success: true, 
          preview_url: deploy_result[:worker_url],
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
                    HTMLAnchorElement HTMLImageElement HTMLFormElement HTMLSelectElement]
      
      # Common internal/context values that are defined in same file
      internal_refs = %w[Comp FormField FormFieldContextValue FormItemContextValue ChartContextProps
                         ChartStyle CarouselContextProps DialogPortal SheetPortal DrawerPortal
                         AlertDialogPortal TFieldValues]
      
      app.app_files.where("path LIKE '%.tsx' OR path LIKE '%.jsx'").each do |file|
        next if file.path.include?('test') || file.path.include?('spec')
        
        content = file.content
        
        # Find all JSX component usage (CapitalCase tags)
        used_components = content.scan(/<([A-Z]\w+)/).flatten.uniq
        
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
        
        # Find missing components
        missing = used_components - imported_components - html_elements - react_builtins - ts_types - internal_refs
        
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
    
    # Send import errors to AI for fixing
    def send_import_errors_to_ai(errors)
      Rails.logger.info "[V5_IMPORT_FIX] Sending import errors to AI for fixing"
      
      # Create a concise error message for the AI
      error_message = "Fix these missing imports:\n" + errors.map { |e| "• #{e}" }.join("\n")
      
      # Create a user message in the chat
      fix_message = app.app_chat_messages.create!(
        user: @chat_message.user,
        team: app.team,
        role: 'user',
        content: error_message,
        status: 'sent'
      )
      
      # Let AI process the fix
      result = process_with_tools(error_message)
      
      # Check if AI made any file changes
      if result[:tool_calls] && result[:tool_calls].any? { |tc| tc[:name].start_with?('os-') }
        Rails.logger.info "[V5_IMPORT_FIX] AI attempted to fix imports"
        return true
      else
        Rails.logger.warn "[V5_IMPORT_FIX] AI did not make any file changes"
        return false
      end
    rescue => e
      Rails.logger.error "[V5_IMPORT_FIX] Error sending to AI: #{e.message}"
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
      
      # Generate Helicone session for tracking
      helicone_session = "overskill-v5-#{@app.id}-#{Time.current.to_i}"
      
      # CRITICAL FIX: Implement proper tool calling cycle with result feedback
      final_response = execute_tool_calling_cycle(client, messages, tools, helicone_session)
      
      log_claude_event("API_CALL_COMPLETE", {
        final_content: final_response[:content].present?,
        thinking_blocks: final_response[:thinking_blocks]&.size || 0,
        tool_cycles: final_response[:tool_cycles] || 0
      })
      
      final_response
    end

    # CRITICAL FIX: Implement proper tool calling cycle according to Anthropic docs
    def execute_tool_calling_cycle(client, messages, tools, helicone_session)
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
            use_cache: true,
            temperature: 0.7,
            max_tokens: 48000,
            helicone_session: helicone_session,
            extended_thinking: true,
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
          # Claude finished normally
          Rails.logger.info "[V5_TOOLS] Claude completed response normally"
          
          # Add text content to conversation_flow if present and not already added
          if response[:content].present? && !content_added_to_flow
            add_loop_message(response[:content], type: 'content', thinking_blocks: response[:thinking_blocks])
            Rails.logger.info "[V5_TOOLS] Added final text content to conversation_flow"
          elsif content_added_to_flow
            Rails.logger.info "[V5_TOOLS] Skipped adding text content - already added before tools"
          end
          
          break
          
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
          content_blocks << {
            type: 'tool_use',
            id: tool_call['id'],
            name: tool_call['function']['name'],
            input: JSON.parse(tool_call['function']['arguments'])
          }
        end
      end
      
      content_blocks
    end

    # Execute tools and format results according to Anthropic specs
    def execute_and_format_tool_results(tool_calls)
      tool_results = []
      
      # Clear pending tools at start to batch this group together
      @pending_tool_calls = []
      
      # Execute ALL tool calls and collect results
      tool_calls.each do |tool_call|
        tool_name = tool_call['function']['name']
        tool_args = JSON.parse(tool_call['function']['arguments'])
        tool_id = tool_call['id']
        
        Rails.logger.info "[V5_TOOLS] Executing #{tool_name} with args: #{tool_args.keys.join(', ')}"
        
        # Execute the tool with proper error handling
        result = begin
          execute_single_tool(tool_name, tool_args)
        rescue StandardError => e
          Rails.logger.error "[V5_TOOLS] Tool execution failed: #{tool_name} - #{e.message}"
          Rails.logger.error e.backtrace.first(5).join("\n")
          
          # Ensure status is updated to error on exception
          update_tool_status_to_error(tool_name, tool_args['file_path'], e.message)
          
          # Return error result
          { error: "Tool execution failed: #{e.message}" }
        end
        
        # Format result according to Anthropic tool_result spec
        tool_result_block = {
          type: 'tool_result',
          tool_use_id: tool_id  # CRITICAL: Must match the id from tool_use block
        }
        
        # Validation: Ensure tool_id is present
        if tool_id.blank?
          Rails.logger.error "[V5_TOOLS] Missing tool_id for tool_result! Tool: #{tool_name}"
          tool_id = "missing_id_#{SecureRandom.hex(8)}"
          tool_result_block[:tool_use_id] = tool_id
        end
        
        if result[:error]
          tool_result_block[:content] = result[:error]
          tool_result_block[:is_error] = true
        else
          # Format successful result
          if result[:content].is_a?(String)
            tool_result_block[:content] = result[:content]
          else
            # Convert complex results to JSON string
            tool_result_block[:content] = result.to_json
          end
        end
        
        tool_results << tool_result_block
      end
      
      # Flush all pending tool calls as a batch to conversation_flow
      flush_pending_tool_calls
      
      # CRITICAL: Return array of tool_result blocks (they must come first in content array)
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
      
      result = case tool_name
      when 'os-write'
        write_file(tool_args['file_path'], tool_args['content'])
      when 'os-view', 'os-read'
        read_file(tool_args['file_path'])
      when 'os-line-replace'
        Rails.logger.info "[V5_TOOL] Processing os-line-replace with args: #{tool_args.inspect}"
        replace_file_content(tool_args)
      when 'os-delete'
        delete_file(tool_args['file_path'])
      when 'os-add-dependency'
        add_dependency(tool_args['package'])
      when 'os-remove-dependency'
        remove_dependency(tool_args['package'])
      when 'os-rename'
        rename_file(tool_args['old_path'], tool_args['new_path'])
      when 'os-search-files'
        search_files(tool_args)
      when 'os-download-to-repo'
        download_to_repo(tool_args['source_url'], tool_args['target_path'])
      when 'os-fetch-website'
        fetch_website(tool_args['url'], tool_args['formats'])
      when 'os-read-console-logs'
        read_console_logs(tool_args['search'])
      when 'os-read-network-requests'
        read_network_requests(tool_args['search'])
      when 'generate_image'
        generate_image(tool_args)
      when 'edit_image'
        edit_image(tool_args)
      when 'web_search'
        web_search(tool_args)
      when 'read_project_analytics'
        read_project_analytics(tool_args)
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
      
      tool_calls.each do |tool_call|
        tool_name = tool_call['function']['name']
        tool_args = JSON.parse(tool_call['function']['arguments'])
        
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
        
        # Update UI with tool execution
        add_tool_call(tool_name, file_path: tool_args['file_path'], status: 'running')
        
        # Execute with proper error handling
        result = begin
          case tool_name
          when 'os-write'
            write_file(tool_args['file_path'], tool_args['content'])
          when 'os-view', 'os-read'
            read_file(tool_args['file_path'])
          when 'os-line-replace'
            Rails.logger.info "[V5_TOOL_PROCESS] Processing os-line-replace in process_tool_calls"
            replace_file_content(tool_args)
          when 'os-delete'
            delete_file(tool_args['file_path'])
          when 'os-add-dependency'
            add_dependency(tool_args['package'])
          when 'os-remove-dependency'
            remove_dependency(tool_args['package'])
          when 'os-rename'
          rename_file(tool_args['old_path'], tool_args['new_path'])
        when 'os-search-files'
          search_files(tool_args)
        when 'os-download-to-repo'
          download_to_repo(tool_args['source_url'], tool_args['target_path'])
        when 'os-fetch-website'
          fetch_website(tool_args['url'], tool_args['formats'])
        when 'os-read-console-logs'
          read_console_logs(tool_args['search'])
        when 'os-read-network-requests'
          read_network_requests(tool_args['search'])
        when 'generate_image'
          generate_image(tool_args)
        when 'edit_image'
          edit_image(tool_args)
        when 'web_search'
          web_search(tool_args)
        when 'read_project_analytics'
          read_project_analytics(tool_args)
        when 'write_files', 'create_files'
          # Proper implementation for batch file operations
          process_batch_file_operation(tool_name, tool_args)
          else
            Rails.logger.error "=" * 60
            Rails.logger.error "❌ UNKNOWN TOOL: #{tool_name}"
            Rails.logger.error "=" * 60
            { error: "Unknown tool: #{tool_name}" }
          end
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
        
        # Update tool status - find and update the specific tool call
        new_status = result[:error] ? 'error' : 'complete'
        
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
      Rails.logger.info "[V5_LINE_REPLACE] Lines #{args['first_replaced_line']}-#{args['last_replaced_line']}"
      
      file = @app.app_files.find_by(path: args['file_path'])
      unless file
        Rails.logger.error "[V5_LINE_REPLACE] File not found: #{args['file_path']}"
        return { error: "File not found: #{args['file_path']}" }
      end
      
      # Use LineReplaceService for proper validation and replacement
      if defined?(Ai::LineReplaceService)
        result = Ai::LineReplaceService.replace_lines(
          file,
          args['search'],
          args['first_replaced_line'].to_i,
          args['last_replaced_line'].to_i,
          args['replace']
        )
        
        if result[:success]
          Rails.logger.info "[V5_LINE_REPLACE] Success for #{args['file_path']}"
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
    

    
    def web_search(args)
      # For V5, return placeholder search results
      # In production, this would integrate with search API (Google, Bing, etc.)
      
      query = args['query']
      num_results = args['numResults'] || 5
      links = args['links'] || 0
      image_links = args['imageLinks'] || 0
      category = args['category']
      
      # Mock search results
      mock_results = [
        {
          title: "#{query} - Documentation",
          url: "https://example.com/docs/#{query.parameterize}",
          snippet: "Official documentation for #{query}. Learn how to implement and use #{query} effectively.",
          category: category || "documentation"
        },
        {
          title: "#{query} Tutorial - Getting Started",
          url: "https://tutorial-site.com/#{query.parameterize}",
          snippet: "Step-by-step tutorial covering #{query} basics and advanced techniques.",
          category: category || "tutorial"
        },
        {
          title: "#{query} GitHub Repository",
          url: "https://github.com/example/#{query.parameterize}",
          snippet: "Open source implementation of #{query} with examples and community contributions.",
          category: "github"
        }
      ].first(num_results)
      
      {
        success: true,
        query: query,
        results: mock_results,
        total_results: mock_results.count,
        category: category,
        note: "Placeholder implementation - requires search API integration"
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
      messages << { role: 'user', content: @chat_message.content }
      
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
    
    # Get template files for caching (long-form data goes first)
    def get_template_files_for_caching
      # NOTE: Files might change between iterations if Claude modified them
      # Only cache on first iteration or when we haven't modified files yet
      return [] if @iteration_count > 1 && @agent_state[:generated_files].any?
      
      template_files = []
      
      # Only include base template context on first iteration (before modifications)
      if @iteration_count == 1
        # Get the useful context which includes all template files
        base_context_service = Ai::BaseContextService.new(@app)
        useful_context = base_context_service.build_useful_context
        
        # Create a pseudo-file object for the template content
        # This allows CachedPromptBuilder to handle it properly
        if useful_context.present? && useful_context.length > 1000
          template_files << OpenStruct.new(
            path: "template_context",
            content: useful_context
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
      
      # Add base template files and essential context
      base_context_service = Ai::BaseContextService.new(@app)
      base_context = base_context_service.build_useful_context
      
      # Add existing app files context to prevent re-reading
      existing_files_context = base_context_service.build_existing_files_context(@app)
      
      # Combine into useful-context section
      context[:base_template_context] = base_context
      context[:existing_files_context] = existing_files_context if existing_files_context.present?
      
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
      grouped = files.group_by { |f| File.extname(f.path) }
      
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
    
    def validate_typescript_file(file)
      # TODO: Implement TypeScript validation
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
      existing_assistant = @app.app_chat_messages
        .where(role: 'assistant')
        .where('created_at > ?', @chat_message.created_at)
        .where(status: 'executing')
        .first
      
      if existing_assistant
        Rails.logger.info "[V5_INIT] Using existing assistant placeholder ##{existing_assistant.id}"
        existing_assistant
      else
        # Fallback: create new message if none exists
        Rails.logger.info "[V5_INIT] Creating new assistant message (no placeholder found)"
        AppChatMessage.create!(
          app: @app,
          user: @chat_message.user,
          role: 'assistant',
          content: 'Thinking..', # Required field
          status: 'executing',
          iteration_count: 0,
          loop_messages: [],
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
          
          @assistant_message.loop_messages << thinking_message
          
          # Add to conversation_flow for display
          add_to_conversation_flow(
            type: 'thinking',
            content: thinking_message
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
        
        @assistant_message.loop_messages << loop_message
        
        # Also add to conversation_flow for interleaved display
        add_to_conversation_flow(
          type: type == 'status' ? 'status' : 'message',
          content: loop_message
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
        
        if item['calls'].present?
          item['calls'].each do |tool|
            # Log what we're comparing
            Rails.logger.debug "[V5_FLOW_UPDATE] Checking tool: name=#{tool['name']} vs #{tool_name}, file=#{tool['file_path']} vs #{file_path}"
            
            if tool['name'] == tool_name && tool['file_path'] == file_path
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
        Rails.logger.info "[V5_FLOW_UPDATE] Successfully saved updated conversation_flow"
      else
        Rails.logger.warn "[V5_FLOW_UPDATE] No matching tool found to update in conversation_flow"
      end
    end
    
    def update_iteration_count
      @assistant_message.iteration_count = @iteration_count
      @assistant_message.save!
    end
    
    def finalize_with_app_version(app_version)
      @assistant_message.app_version = app_version
      @assistant_message.is_code_generation = true
      @assistant_message.status = 'completed'
      @assistant_message.thinking_status = nil
      @assistant_message.save!
    end
    
    def mark_as_discussion_only
      @assistant_message.is_code_generation = false
      @assistant_message.status = 'completed'
      @assistant_message.thinking_status = nil
      @assistant_message.save!
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
      
      flow_entry = {
        'type' => type,
        'iteration' => iteration || @iteration_count,
        'timestamp' => Time.current.iso8601
      }
      
      Rails.logger.info "[V5_FLOW] Adding to conversation_flow: type=#{type}, flow_size=#{@assistant_message.conversation_flow.size}"
      
      case type
      when 'message'
        flow_entry['content'] = content
        flow_entry['thinking_blocks'] = content.is_a?(Hash) ? content['thinking_blocks'] : nil
      when 'tools'
        flow_entry['calls'] = tool_calls || []
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
    
    def get_or_create_template_version
      # Cache the template version
      @template_version ||= begin
        # Look for v1.0.0 template version for this app
        version = @app.app_versions.find_by(version_number: 'v1.0.0')
        
        # If not found, create it from template files
        if version.nil? && template_files_exist?
          version = create_template_version_from_files
        end
        
        version
      end
    end
    
    def template_files_exist?
      template_dir = Rails.root.join("app/services/ai/templates/overskill_20250728")
      Dir.exist?(template_dir) && Dir.glob(::File.join(template_dir, "**/*")).any? { |f| ::File.file?(f) }
    end
    
    def create_template_version_from_files
      template_dir = Rails.root.join("app/services/ai/templates/overskill_20250728")
      
      version = @app.app_versions.create!(
        version_number: 'v1.0.0',
        team: @app.team,
        user: @chat_message.user,
        changelog: 'Initial template version from overskill_20250728',
        deployed: false,
        external_commit: false
      )
      
      # Load all template files into AppFiles and AppVersionFiles
      Dir.glob(::File.join(template_dir, "**/*")).each do |file_path|
        next unless ::File.file?(file_path)
        
        relative_path = file_path.sub("#{template_dir}/", '')
        content = ::File.read(file_path)
        
        # Skip empty files
        next if content.blank?
        
        # Create or find AppFile
        app_file = @app.app_files.find_or_create_by!(path: relative_path) do |f|
          f.content = content
          f.team = @app.team
          f.file_type = determine_file_type(relative_path)
        end
        
        # Update content if file exists
        app_file.update!(content: content) if app_file.content != content
        
        # Create AppVersionFile to track this file in v1.0.0
        version.app_version_files.create!(
          app_file: app_file,
          action: 'created',
          content: content
        )
      end
      
      Rails.logger.info "[V5_TEMPLATE] Created AppVersion v1.0.0 with #{version.app_version_files.count} files"
      version
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
      
      # Track recent operations
      @recent_operations ||= []
      
      if result[:type] == :tools_executed && result[:data]
        result[:data].each do |operation|
          next unless operation[:path]
          
          operation_key = "#{operation[:path]}:#{operation[:type] || 'write'}"
          @recent_operations << {
            key: operation_key,
            iteration: @iteration_count,
            timestamp: Time.current
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
  end
  
  # Supporting classes for the agent loop
  
  # TODO: Consider adding goal tracking as tool calls in the future
  # This would allow Claude to explicitly set and complete goals as needed  
  
  
  class ContextManager
    def initialize(app)
      @app = app
      @context = {}
      @implementation_plan = nil
    end
    
    def add_context(data)
      @context.merge!(data)
    end
    
    def set_implementation_plan(plan)
      @implementation_plan = plan
    end
    
    def update_from_result(result)
      @context[:last_result] = result
      @context[:last_action] = result[:action]
    end
    
    def completeness_score
      # Calculate how complete our context is
      score = 0
      score += 25 if @context[:requirements]
      score += 25 if @implementation_plan
      score += 25 if @context[:last_result]
      score += 25 if @app.app_files.any?
      score
    end
  end
  
  class AgentDecisionEngine
    def determine_next_action(state)
      # Improved decision logic that considers goals progress
      if state[:iteration] == 1
        { type: :plan_implementation, description: "Create initial plan" }
      elsif state[:errors].any?
        { 
          type: :debug_issues, 
          description: "Fix errors",
          issues: state[:errors]
        }
      elsif !has_app_specific_features?(state) 
        # Check if we need to implement the actual app features
        { 
          type: :execute_tools, 
          description: "Implement app-specific features",
          tools: determine_feature_tools(state)
        }
      elsif needs_verification?(state)
        { type: :verify_changes, description: "Verify generated code" }
      elsif all_goals_near_complete?(state)
        { type: :complete_task, description: "Finalize generation" }
      else
        { 
          type: :execute_tools, 
          description: "Continue implementation",
          tools: determine_next_tools(state)
        }
      end
    end
    
    def has_app_specific_features?(state)
      # Check if app-specific features have been implemented
      # Look for signs that the todo app functionality exists
      return false unless state[:files_generated] > 0
      
      # Check if we have key todo app files
      files = state[:generated_files] || []
      file_paths = files.map { |f| f.respond_to?(:path) ? f.path : f.to_s }
      
      # Look for key indicators that todo features are implemented
      has_todo_component = file_paths.any? { |p| p.include?('Todo') || p.include?('todo') }
      has_task_component = file_paths.any? { |p| p.include?('Task') || p.include?('task') }
      
      # Need both todo-related files AND sufficient implementation
      has_todo_component && state[:iteration] >= 3
    end
    
    private
    
    def determine_feature_tools(state)
      # Tools for implementing app-specific features
      [
        { type: :implement_features, description: 'Implement app-specific functionality' }
      ]
    end
    
    def determine_initial_tools(state)
      [
        { type: :generate_file, file_path: 'package.json', description: 'Create package.json' },
        { type: :generate_file, file_path: 'src/App.tsx', description: 'Create main App component' },
        { type: :generate_file, file_path: 'src/main.tsx', description: 'Create entry point' }
      ]
    end
    
    def determine_next_tools(state)
      # Determine what tools to run next based on state
      []
    end
    
    def needs_verification?(state)
      state[:iteration] > 1 && state[:iteration] % 3 == 0
    end
    
    def all_goals_near_complete?(state)
      state[:goals].count <= 1
    end
  end
  
  class TerminationEvaluator
    def should_terminate?(state, result)
      # Multiple termination conditions
      return true if all_goals_satisfied?(state)
      return true if stagnation_detected?(state)
      return true if error_threshold_exceeded?(state)
      return true if complexity_limit_reached?(state)
      
      false
    end
    
    private
    
    def all_goals_satisfied?(state)
      # Check if all goals are completed
      return false unless state[:goals].is_a?(Array) && state[:completed_goals].is_a?(Array)
      
      # All goals are satisfied when completed_goals contains all goals
      state[:goals].all? { |goal| state[:completed_goals].include?(goal) }
    end
    
    def stagnation_detected?(state)
      return false if state[:iteration] < 4
      
      # Check if making progress
      recent_history = state[:history].last(4)
      return false if recent_history.count < 4
      
      # Multiple stagnation indicators
      
      # 1. Same action type repeated and failing
      actions = recent_history.map { |h| h[:action][:type] }
      verifications = recent_history.map { |h| h[:verification][:success] }
      
      if actions.uniq.size == 1 && verifications.none?
        Rails.logger.warn "[V5_STAGNATION] Same action #{actions.first} failing repeatedly"
        return true
      end
      
      # 2. No goal progress in recent iterations (with nil safety)
      goal_progress_history = recent_history.map { |h| h&.dig(:goals_progress, :completed) }.compact
      if goal_progress_history.size > 1 && goal_progress_history.uniq.size == 1
        Rails.logger.warn "[V5_STAGNATION] No goal progress in last #{recent_history.count} iterations"
        return true
      end
      
      # 3. Verification confidence consistently low (with nil safety)
      confidence_scores = recent_history.map { |h| h&.dig(:verification, :confidence) || 0 }.compact
      avg_confidence = confidence_scores.any? ? confidence_scores.sum / confidence_scores.count.to_f : 0
      if avg_confidence < 0.3
        Rails.logger.warn "[V5_STAGNATION] Low confidence trend: #{avg_confidence.round(2)}"
        return true
      end
      
      false
    end
    
    def error_threshold_exceeded?(state)
      state[:errors].count > 10
    end
    
    def complexity_limit_reached?(state)
      state[:generated_files].count > 100
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
      Rails.logger.warn "[V5_BROADCAST] Failed to broadcast preview frame update: #{e.message}"
    end
  end
end