# AppBuilderV5 - Agent Loop Implementation with Lovable-style architecture
module Ai
  class AppBuilderV5
    include Rails.application.routes.url_helpers
    
    MAX_ITERATIONS = 10
    COMPLETION_CONFIDENCE_THRESHOLD = 0.85
    
    attr_reader :chat_message, :app, :broadcaster, :agent_state
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app || create_app
      @broadcaster = ChatProgressBroadcasterV2.new(chat_message)
      @start_time = Time.current
      @iteration_count = 0
      @completion_status = :active
      
      # Create assistant reply message for V5 UI
      @assistant_message = create_assistant_message
      
      # Initialize agent components
      @prompt_service = Prompts::AgentPromptService.new(agent_variables)
      @goal_tracker = GoalTracker.new(chat_message.content)
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
    end
    
    def execute!
      Rails.logger.info "[AppBuilderV5] Starting agent loop for app ##{app.id}"
      
      begin
        # Mark app as generating
        app.update!(status: 'generating')
        broadcaster.broadcast_phase(1, "Starting AI Agent", 6)
        
        # Extract goals from user request
        broadcaster.broadcast_status("Analyzing your requirements...")
        @goal_tracker.extract_goals_from_request(@chat_message.content)
        
        # Execute agent loop
        execute_until_complete
        
        # Finalize
        finalize_app_generation
        
      rescue => e
        handle_error(e)
      end
    end
    
    private
    
    def execute_until_complete
      loop do
        @iteration_count += 1
        @agent_state[:iteration] = @iteration_count
        
        # Update V5 UI with iteration count
        update_iteration_count
        
        Rails.logger.info "[AppBuilderV5] Starting iteration #{@iteration_count}"
        
        # Safety check for infinite loops
        if @iteration_count > MAX_ITERATIONS
          Rails.logger.warn "[AppBuilderV5] Max iterations reached"
          add_loop_message("Maximum iterations reached. Finalizing generation.", type: 'status')
          break
        end
        
        # Execute one iteration of the agent loop
        result = execute_iteration
        
        # Check termination conditions
        if should_terminate?(result)
          Rails.logger.info "[AppBuilderV5] Termination condition met"
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
      
      # Broadcast progress
      progress = @goal_tracker.assess_progress
      broadcaster.broadcast_status(
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
      {
        app_id: app.id,
        iteration: @iteration_count,
        goals: @goal_tracker.goals,
        completed_goals: @goal_tracker.completed_goals,
        context_completeness: @context_manager.completeness_score,
        files_generated: @agent_state[:generated_files].count,
        errors: @agent_state[:errors],
        last_action: @agent_state[:history].last&.dig(:action, :type),
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
      
      @context_manager.add_context(response)
      
      # Clear thinking status and add result
      update_thinking_status(nil)
      add_loop_message("Analyzed project requirements and context.", type: 'status')
      
      { type: :context_gathered, data: response }
    end
    
    def plan_app_implementation(action)
      broadcaster.broadcast_phase(2, "Planning Architecture", 6)
      broadcaster.broadcast_status("Creating implementation plan...")
      
      # Generate comprehensive plan using template structure
      plan_prompt = build_planning_prompt
      
      response = call_ai_with_context(plan_prompt)
      
      # Extract and structure the plan
      implementation_plan = extract_implementation_plan(response)
      @context_manager.set_implementation_plan(implementation_plan)
      
      { type: :plan_created, data: implementation_plan }
    end
    
    def execute_tool_operations(action)
      broadcaster.broadcast_phase(4, "Generating Features", 6)
      
      results = []
      action[:tools].each_with_index do |tool, index|
        broadcaster.broadcast_status("Executing: #{tool[:description]}")
        
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
        broadcaster.broadcast_progress(progress_percent, "#{index + 1}/#{action[:tools].count} operations completed")
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
      broadcaster.broadcast_phase(5, "Validating & Building", 6)
      broadcaster.broadcast_status("Verifying generated code...")
      
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
      broadcaster.broadcast_status("Debugging and fixing issues...")
      
      fixes_applied = []
      
      action[:issues].each do |issue|
        fix_prompt = build_fix_prompt(issue)
        fix_response = call_ai_with_context(fix_prompt)
        
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
      broadcaster.broadcast_phase(6, "Finalizing", 6)
      broadcaster.broadcast_status("Completing app generation...")
      
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
        { 
          success: success_rate > 0.8, 
          confidence: success_rate,
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
      else
        { success: true, confidence: 0.5 }
      end
    end
    
    def should_terminate?(result)
      # Use termination evaluator
      @termination_evaluator.should_terminate?(@agent_state, result) ||
        @completion_status == :complete ||
        @completion_status == :user_intervention_required ||
        result[:verification][:confidence] >= COMPLETION_CONFIDENCE_THRESHOLD ||
        @goal_tracker.all_goals_achieved? ||
        result[:action] == :await_user_input
    end
    
    def finalize_app_generation
      if @completion_status == :complete
        # Deploy the app
        broadcaster.broadcast_phase(6, "Deploying", 6)
        deploy_result = deploy_app
        
        if deploy_result[:success]
          app.update!(
            status: 'ready',
            preview_url: deploy_result[:preview_url],
            deployed_at: Time.current
          )
          
          broadcaster.broadcast_complete(
            "App successfully generated and deployed!",
            app.preview_url
          )
        else
          app.update!(status: 'failed')
          broadcaster.broadcast_error("Deployment failed: #{deploy_result[:error]}")
        end
      else
        app.update!(status: 'failed')
        broadcaster.broadcast_error("Generation incomplete after #{@iteration_count} iterations")
      end
    end
    
    def deploy_app
      deployer = Deployment::CloudflareDeployerService.new(app)
      deployer.deploy
    end
    
    def call_ai_with_context(prompt)
      # Use Anthropic client singleton with caching
      client = Ai::AnthropicClient.instance
      
      messages = build_messages_with_context(prompt)
      tools = @prompt_service.generate_tools
      
      # Use chat_with_tools for tool support with caching
      response = client.chat_with_tools(
        messages,
        tools,
        model: :claude_opus_4,  # Use symbol for model
        use_cache: true,         # Enable prompt caching for 83% cost savings
        temperature: 0.7,
        max_tokens: 4000
      )
      
      # Process tool calls if present
      if response[:tool_calls].present?
        process_tool_calls(response[:tool_calls])
      end
      
      response
    end
    
    def process_tool_calls(tool_calls)
      results = []
      
      tool_calls.each do |tool_call|
        tool_name = tool_call['function']['name']
        tool_args = JSON.parse(tool_call['function']['arguments'])
        
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
        else
          { error: "Unknown tool: #{tool_name}" }
        end
        
        # Update tool status
        @assistant_message.tool_calls.last['status'] = result[:error] ? 'error' : 'complete'
        @assistant_message.save!
        
        results << result
      end
      
      results
    end
    
    def write_file(path, content)
      file = @app.app_generated_files.find_or_initialize_by(path: path)
      file.content = content
      file.language = determine_language(path)
      file.save!
      
      @agent_state[:generated_files] << file unless @agent_state[:generated_files].include?(file)
      
      { success: true, path: path, file_id: file.id }
    end
    
    def read_file(path)
      # First check template directory
      template_file = Rails.root.join("app/services/ai/templates/overskill_20250728", path)
      
      if File.exist?(template_file)
        { success: true, content: File.read(template_file), source: 'template' }
      elsif file = @app.app_generated_files.find_by(path: path)
        { success: true, content: file.content, source: 'generated' }
      else
        { error: "File not found: #{path}" }
      end
    end
    
    def replace_file_content(args)
      file = @app.app_generated_files.find_by(path: args['file_path'])
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
      if file = @app.app_generated_files.find_by(path: path)
        file.destroy
        @agent_state[:generated_files].delete(file)
        { success: true, path: path }
      else
        { error: "File not found: #{path}" }
      end
    end
    
    def build_messages_with_context(prompt)
      base_messages = [
        { role: 'system', content: @prompt_service.generate_prompt },
        { role: 'user', content: @chat_message.content }
      ]
      
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
      <<~CONTEXT
        AGENT LOOP ITERATION #{@iteration_count} OF #{MAX_ITERATIONS}
        
        CURRENT GOALS STATUS:
        #{format_goals_status(@goal_tracker.assess_progress)}
        
        PREVIOUS ACTIONS TAKEN:
        #{format_previous_actions(@agent_state[:history])}
        
        GENERATED FILES SO FAR:
        #{@agent_state[:generated_files].map(&:path).join("\n")}
        
        CURRENT CONTEXT COMPLETENESS: #{@context_manager.completeness_score}%
        
        LAST VERIFICATION RESULTS:
        #{@agent_state[:verification_results].last}
        
        Continue working towards completing all goals. Focus on what still needs to be done.
      CONTEXT
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
      
      app.update!(status: 'failed')
      
      broadcaster.broadcast_error(
        "An error occurred: #{error.message}. Please try again."
      )
      
      # Track error in analytics
      Analytics::EventTracker.new.track_event(
        'app_generation_failed',
        app_id: app.id,
        error: error.message,
        iteration: @iteration_count
      )
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
      history.last(3).map do |h|
        "- Iteration #{h[:iteration]}: #{h[:action][:type]} (#{h[:verification][:success] ? 'Success' : 'Failed'})"
      end.join("\n")
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
      
      # Check if template file exists
      template_file = File.join(template_path, file_path)
      
      if File.exist?(template_file)
        # Use template as base
        base_content = File.read(template_file)
        
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
      
      static_files.include?(File.basename(path))
    end
    
    def build_file_enhancement_prompt(path, base_content, description)
      <<~PROMPT
        Enhance the following #{File.extname(path)} file based on the requirements.
        
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
        Generate a #{File.extname(path)} file for path: #{path}
        
        Requirements: #{description}
        User's original request: #{@chat_message.content}
        
        Technology stack: React, TypeScript, Vite, Tailwind CSS, Supabase
        
        Return ONLY the complete file content, no explanations.
        Follow best practices and modern patterns.
      PROMPT
    end
    
    def default_file_content(path)
      # Fallback content for common files
      case File.basename(path)
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
      app.app_generated_files.create!(
        path: path,
        content: content,
        language: determine_language(path)
      )
    end
    
    def determine_language(path)
      case path
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
      AppChatMessage.create!(
        app: @app,
        role: 'assistant',
        content: '', # Will use loop_messages instead
        status: 'executing',
        iteration_count: 0,
        loop_messages: [],
        tool_calls: [],
        thinking_status: nil,
        is_code_generation: false
      )
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
      {
        total_goals: @goals.count,
        completed: @completed_goals.count,
        remaining: @goals.count,
        completion_percentage: (@completed_goals.count.to_f / (@goals.count + @completed_goals.count) * 100).to_i,
        next_priority_goal: @goals.min_by(&:priority)
      }
    end
    
    def mark_goal_complete(goal)
      @goals.delete(goal)
      @completed_goals << goal
    end
    
    def all_goals_achieved?
      @goals.empty?
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
      score += 25 if @app.app_generated_files.any?
      score
    end
  end
  
  class AgentDecisionEngine
    def determine_next_action(state)
      # Simplified decision logic
      if state[:iteration] == 1
        { type: :plan_implementation, description: "Create initial plan" }
      elsif state[:files_generated] == 0
        { 
          type: :execute_tools, 
          description: "Generate initial files",
          tools: determine_initial_tools(state)
        }
      elsif state[:errors].any?
        { 
          type: :debug_issues, 
          description: "Fix errors",
          issues: state[:errors]
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
    
    private
    
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
      state[:goals].empty?
    end
    
    def stagnation_detected?(state)
      return false if state[:iteration] < 3
      
      # Check if making progress
      last_three = state[:history].last(3)
      return false if last_three.count < 3
      
      # If all had same action type and failed, we're stuck
      actions = last_three.map { |h| h[:action][:type] }
      verifications = last_three.map { |h| h[:verification][:success] }
      
      actions.uniq.size == 1 && verifications.none?
    end
    
    def error_threshold_exceeded?(state)
      state[:errors].count > 10
    end
    
    def complexity_limit_reached?(state)
      state[:generated_files].count > 100
    end
  end
end