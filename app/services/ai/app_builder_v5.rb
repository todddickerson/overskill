# AppBuilderV5 - Agent Loop Implementation with Lovable-style architecture
module Ai
  class AppBuilderV5
    include Rails.application.routes.url_helpers
    
    MAX_ITERATIONS = 10
    COMPLETION_CONFIDENCE_THRESHOLD = 0.85
    
    attr_reader :chat_message, :app, :agent_state, :assistant_message
    
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
      @goal_tracker = GoalTracker.new(chat_message.content)
      
      # Debug: check if prompt service works
      Rails.logger.debug "[V5_DEBUG] Prompt service initialized"
      Rails.logger.debug "[V5_DEBUG] Agent variables: #{agent_variables.keys.join(', ')}"
      @context_manager = ContextManager.new(app)
      @decision_engine = AgentDecisionEngine.new
      @termination_evaluator = TerminationEvaluator.new
      
      # Initialize state
      @agent_state = {
        iteration: 0,
        goals: @goal_tracker.goals,
        context: {},
        history: [],
        errors: [],
        generated_files: [],
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
        
        # Extract goals from user request
        update_thinking_status("Analyzing your requirements...")
        @goal_tracker.extract_goals_from_request(@chat_message.content)
        
        # Log the goals
        log_claude_event("GOALS_EXTRACTED", {
          total_goals: @goal_tracker.goals.count,
          goals: @goal_tracker.goals.map(&:description).join(", ")
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
        Rails.logger.info "[V5_LOOP] Iteration result: #{result[:type]}"
        
        # Update goal progress based on result
        update_goal_progress(result)
        
        # Check for loop detection
        if loop_detected?(result)
          Rails.logger.warn "[V5_LOOP] Loop detected - stopping to prevent infinite iteration"
          add_loop_message("Loop detected in operations - stopping to prevent repetitive actions.", type: 'error')
          break
        end
        
        # Check termination conditions
        if should_terminate?(result)
          Rails.logger.info "[V5_LOOP] Termination condition met"
          add_loop_message("All goals completed successfully!", type: 'status')
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
      
      # Update progress
      progress = @goal_tracker.assess_progress
      update_thinking_status(
        "Iteration #{@iteration_count}: #{progress[:completed]}/#{progress[:total_goals]} goals completed"
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
        verification: verification,
        goals_progress: @goal_tracker.assess_progress
      }
    end
    
    def assess_current_state
      progress = @goal_tracker.assess_progress
      
      {
        app_id: app.id,
        iteration: @iteration_count,
        goals: @goal_tracker.goals,
        completed_goals: @goal_tracker.completed_goals,
        goal_progress: progress,
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
      
      # Capture Claude's conversational response
      if response[:content].present?
        add_loop_message(response[:content], type: 'content')
      end
      
      @context_manager.add_context(response)
      
      # Clear thinking status and add result
      update_thinking_status(nil)
      add_loop_message("Analyzed project requirements and context.", type: 'status')
      
      { type: :context_gathered, data: response }
    end
    
    def plan_app_implementation(action)
      update_thinking_status("Phase 2/6: Planning Architecture")
      update_thinking_status("Creating implementation plan...")
      
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
      
      # Capture Claude's conversational response about the plan
      if response[:content].present?
        add_loop_message(response[:content], type: 'content')
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
        
        # Always capture Claude's conversational response for the user
        if response[:content].present?
          add_loop_message(response[:content], type: 'content')
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
      
      # Update tool call status to complete
      @assistant_message.tool_calls.last['status'] = 'complete'
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
    
    def should_terminate?(result)
      # Use termination evaluator
      termination_by_evaluator = @termination_evaluator.should_terminate?(@agent_state, result)
      status_complete = @completion_status == :complete
      intervention_required = @completion_status == :user_intervention_required
      high_confidence = (result[:verification] && result[:verification][:confidence] && result[:verification][:confidence] >= COMPLETION_CONFIDENCE_THRESHOLD)
      goals_achieved = @goal_tracker.all_goals_achieved?
      await_input = result[:action] == :await_user_input
      
      if termination_by_evaluator
        Rails.logger.info "[V5_LOOP] Termination: evaluator said to stop"
      elsif status_complete
        Rails.logger.info "[V5_LOOP] Termination: status is complete"
      elsif intervention_required
        Rails.logger.info "[V5_LOOP] Termination: user intervention required"
      elsif high_confidence
        Rails.logger.info "[V5_LOOP] Termination: high confidence #{result[:verification][:confidence]}"
      elsif goals_achieved
        Rails.logger.info "[V5_LOOP] Termination: all goals achieved"
      elsif await_input
        Rails.logger.info "[V5_LOOP] Termination: awaiting user input"
      end
      
      termination_by_evaluator || status_complete || intervention_required || high_confidence || goals_achieved || await_input
    end
    
    def finalize_app_generation
      if @completion_status == :complete
        # Deploy the app
        update_thinking_status("Phase 6/6: Deploying")
        deploy_result = deploy_app
        
        if deploy_result[:success]
          app.update!(
            status: 'ready',
            preview_url: deploy_result[:preview_url],
            deployed_at: Time.current
          )
          
          @assistant_message.update!(
            thinking_status: nil,
            status: 'completed',
            content: "App successfully generated and deployed! Preview: #{app.preview_url}"
          )
        else
          app.update!(status: 'failed')
          @assistant_message.update!(
            thinking_status: nil,
            status: 'failed',
            content: "Deployment failed: #{deploy_result[:error]}"
          )
        end
      else
        app.update!(status: 'failed')
        @assistant_message.update!(
          thinking_status: nil,
          status: 'failed',
          content: "Generation incomplete after #{@iteration_count} iterations"
        )
      end
    end
    
    def deploy_app
      deployer = Deployment::CloudflareDeployerService.new(app)
      deployer.deploy
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
      
      # Use chat_with_tools for tool support with caching
      begin
        response = client.chat_with_tools(
          messages,
          tools,
          model: :claude_sonnet_4,  # Use symbol for model
          use_cache: true,         # Enable prompt caching for 83% cost savings
          temperature: 0.7,
          max_tokens: 4000
        )
      rescue => e
        log_claude_event("API_CALL_ERROR", {
          error: e.message,
          class: e.class.name
        })
        raise e
      end
      
      log_claude_event("API_CALL_RESPONSE", {
        has_content: response[:content].present?,
        tool_calls: response[:tool_calls]&.size || 0,
        response_preview: response[:content].to_s[0..200]
      })
      
      # Process tool calls if present
      if response[:tool_calls].present?
        log_claude_event("PROCESSING_TOOLS", { count: response[:tool_calls].size })
        process_tool_calls(response[:tool_calls])
      end
      
      response
    end
    
    def process_tool_calls(tool_calls)
      results = []
      
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
        
        result = case tool_name
        when 'os-write'
          write_file(tool_args['file_path'], tool_args['content'])
        when 'os-view', 'os-read'
          read_file(tool_args['file_path'])
        when 'os-line-replace'
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
          tool_call_to_update['status'] = result[:error] ? 'error' : 'complete'
          @assistant_message.save!
        else
          Rails.logger.warn "[V5_TOOL] Could not find running tool call to update: #{tool_name} #{tool_args['file_path']}"
        end
        
        results << result
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
      file.content = content
      file.file_type = determine_file_type(path)
      file.team = @app.team  # Ensure team is set
      
      begin
        file.save!
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.error "[V5_ERROR] Failed to save file #{path}: #{e.message}"
        return { error: "Failed to save file #{path}: #{e.message}" }
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
        { success: true, content: ::File.read(template_path), source: 'template_directory' }
      # Finally check generated files
      elsif file = @app.app_files.find_by(path: path)
        { success: true, content: file.content, source: 'generated' }
      else
        { error: "File not found: #{path}" }
      end
    end
    
    def replace_file_content(args)
      file = @app.app_files.find_by(path: args['file_path'])
      return { error: "File not found: #{args['file_path']}" } unless file
      
      # Implement line replacement logic
      lines = file.content.split("\n")
      start_line = args['first_replaced_line'].to_i - 1
      end_line = args['last_replaced_line'].to_i - 1
      
      # Replace the specified lines
      replacement_lines = args['replace'].split("\n")
      lines[start_line..end_line] = replacement_lines
      
      file.content = lines.join("\n")
      file.save!
      
      { success: true, path: args['file_path'] }
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
      base_messages = [
        { role: 'system', content: @prompt_service.generate_prompt },
        { role: 'user', content: @chat_message.content }
      ]
      
      # Add template files context on first iteration
      if @iteration_count == 1 && @agent_state[:generated_files].any?
        template_context = {
          role: 'system', 
          content: <<~TEMPLATE
            EXISTING TEMPLATE FILES:
            The following files already exist from the overskill_20250728 template:
            #{@agent_state[:generated_files].map(&:path).sort.join("\n")}
            
            You can read and modify these existing files using os-view and os-line-replace tools.
            Use os-view to check file contents before modifying them.
          TEMPLATE
        }
        base_messages << template_context
      end
      
      # Add iteration context
      if @iteration_count > 1
        context_message = {
          role: 'system',
          content: build_iteration_context
        }
        base_messages << context_message
      end
      
      # Add specific prompt
      base_messages << { role: 'user', content: prompt } if prompt.is_a?(String)
      
      base_messages
    end
    
    def build_iteration_context
      progress = @goal_tracker.assess_progress
      recent_ops = format_recent_operations
      stagnation_warnings = check_stagnation_warnings
      
      context = <<~CONTEXT
        AGENT LOOP ITERATION #{@iteration_count} OF #{MAX_ITERATIONS}
        
        CURRENT GOALS STATUS:
        #{format_goals_status(progress)}
        #{progress[:completion_percentage] >= 80 ? "🎯 NEARLY COMPLETE - Focus on finishing remaining tasks" : ""}
        
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
        #{generate_iteration_guidance(progress)}
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
      
      @assistant_message.update!(
        thinking_status: nil,
        status: 'failed',
        content: "An error occurred: #{error.message}. Please try again."
      )
      
      # Track error in analytics (disabled for now - class not implemented)
      # Analytics::EventTracker.new.track_event(
      #   'app_generation_failed',
      #   app_id: app.id,
      #   error: error.message,
      #   iteration: @iteration_count
      # )
    end
    
    def format_goals_status(progress)
      <<~STATUS
        Total Goals: #{progress[:total_goals]}
        Completed: #{progress[:completed]} (#{progress[:completion_percentage]}%)
        Remaining: #{progress[:remaining]}
        Next Priority: #{progress[:next_priority_goal]&.description || 'None'}
      STATUS
    end
    
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
      
      # Check for low progress
      progress = @goal_tracker.assess_progress
      if @iteration_count >= 5 && progress[:completion_percentage] < 30
        warnings << "⚠️  LOW PROGRESS WARNING: #{progress[:completion_percentage]}% complete after #{@iteration_count} iterations"
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
    
    def generate_iteration_guidance(progress)
      guidance = []
      
      # Goal-specific guidance
      if progress[:next_priority_goal]
        guidance << "🎯 PRIORITY: #{progress[:next_priority_goal].description}"
      end
      
      # Stage-specific guidance
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
      
      # Completion guidance
      if progress[:completion_percentage] >= 80
        guidance << "✨ NEARLY DONE: Focus on completion rather than adding new features"
      elsif progress[:remaining] <= 1
        guidance << "🏁 FINAL GOAL: Complete remaining task to finish generation"
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
    
    def add_loop_message(content, type: 'content')
      @assistant_message.loop_messages << {
        'content' => content,
        'type' => type,
        'iteration' => @iteration_count,
        'timestamp' => Time.current.iso8601
      }
      @assistant_message.save!
    end
    
    def add_tool_call(tool_name, file_path: nil, status: 'complete')
      @assistant_message.tool_calls << {
        'name' => tool_name,
        'file_path' => file_path,
        'status' => status,
        'timestamp' => Time.current.iso8601
      }
      @assistant_message.save!
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
    
    def update_goal_progress(result)
      return unless result && result[:type]
      
      # Track successful operations for goal completion
      case result[:type]
      when :tools_executed
        # Check if foundation files were created
        if result[:data]&.any? { |r| foundation_file_created?(r) }
          mark_goal_complete_by_type(:foundation)
        end
        
        # Check if features were implemented
        if result[:data]&.any? { |r| feature_file_created?(r) }
          mark_goal_complete_by_type(:features)
        end
        
      when :verification_complete
        # Mark deployment goal as complete if build successful
        if result[:data]&.dig(:build_successful)
          mark_goal_complete_by_type(:deployment)
        end
        
      when :generation_complete
        # Mark all remaining goals complete
        @goal_tracker.mark_all_complete
      end
      
      # Log progress for debugging
      progress = @goal_tracker.assess_progress
      Rails.logger.info "[V5_GOAL] Progress: #{progress[:completed]}/#{progress[:total_goals]} goals complete (#{progress[:completion_percentage]}%)"
    end
    
    def mark_goal_complete_by_type(goal_type)
      goal = @goal_tracker.goals.find { |g| g.type == goal_type }
      if goal
        @goal_tracker.mark_goal_complete(goal)
        Rails.logger.info "[V5_GOAL] Completed goal: #{goal.description}"
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
  
  class GoalTracker
    attr_reader :goals, :completed_goals
    
    def initialize(user_prompt)
      @user_prompt = user_prompt
      @goals = []
      @completed_goals = []
    end
    
    def extract_goals_from_request(request)
      # Use AI to extract goals
      # For now, create basic goals based on keywords
      @goals = [
        Goal.new(
          description: "Create the basic app structure",
          type: :foundation,
          priority: 1
        ),
        Goal.new(
          description: "Implement requested features",
          type: :features,
          priority: 2
        ),
        Goal.new(
          description: "Ensure app builds and deploys successfully",
          type: :deployment,
          priority: 3
        )
      ]
    end
    
    def assess_progress
      total_goals = @goals.count + @completed_goals.count
      total_goals = 1 if total_goals == 0  # Prevent division by zero
      
      {
        total_goals: total_goals,
        completed: @completed_goals.count,
        remaining: @goals.count,
        completion_percentage: (@completed_goals.count.to_f / total_goals * 100).to_i,
        next_priority_goal: @goals.min_by(&:priority)
      }
    end
    
    def mark_goal_complete(goal)
      @goals.delete(goal)
      @completed_goals << goal
    end
    
    def all_goals_achieved?
      # Goals are achieved when we have completed goals and no remaining goals
      @goals.empty? && @completed_goals.any?
    end
    
    def mark_all_complete
      # Move all remaining goals to completed
      @completed_goals.concat(@goals)
      @goals.clear
    end
  end
  
  class Goal
    attr_reader :description, :type, :priority
    
    def initialize(description:, type:, priority:)
      @description = description
      @type = type
      @priority = priority
    end
  end
  
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
      
      # 2. No goal progress in recent iterations
      goal_progress_history = recent_history.map { |h| h[:goals_progress][:completed] }
      if goal_progress_history.uniq.size == 1 && goal_progress_history.first == goal_progress_history.last
        Rails.logger.warn "[V5_STAGNATION] No goal progress in last #{recent_history.count} iterations"
        return true
      end
      
      # 3. Verification confidence consistently low
      confidence_scores = recent_history.map { |h| h[:verification][:confidence] || 0 }
      avg_confidence = confidence_scores.sum / confidence_scores.count.to_f
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
  end
end