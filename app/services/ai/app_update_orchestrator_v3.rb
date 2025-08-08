module Ai
  # GPT-5 Enhanced orchestrator - Unified handler for both CREATE and UPDATE operations
  # Streams real-time progress via app_versions and chat messages
  class AppUpdateOrchestratorV3
    include Rails.application.routes.url_helpers
    
    MAX_IMPROVEMENT_ITERATIONS = 3
    
    attr_reader :chat_message, :app, :user, :app_version, :broadcaster
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @iteration_count = 0
      @improvements_made = []
      
      # Use OpenAI directly for GPT-5 - ALWAYS prefer OpenAI over OpenRouter
      openai_key = ENV['OPENAI_API_KEY']
      if openai_key.present? && openai_key.length > 20 && !openai_key.include?('dummy')
        @client = OpenaiGpt5Client.instance
        @use_openai_direct = true
        Rails.logger.info "[AppUpdateOrchestratorV3] Using OpenAI direct API with GPT-5"
      else
        Rails.logger.warn "[AppUpdateOrchestratorV3] WARNING: OpenAI key invalid or missing, falling back to OpenRouter"
        Rails.logger.warn "[AppUpdateOrchestratorV3] Set OPENAI_API_KEY in .env.development.local for better performance"
        @client = OpenRouterClient.new
        @use_openai_direct = false
      end
      
      @is_new_app = determine_if_new_app
      @app_version = nil
      @broadcaster = Services::ProgressBroadcaster.new(@app, @chat_message)
      @streaming_buffer = nil
      @files_modified = []
      @start_time = Time.current
    end
    
    def execute!
      Rails.logger.info "[AppUpdateOrchestratorV3] Starting GPT-5 enhanced execution for message ##{chat_message.id}"
      Rails.logger.info "[AppUpdateOrchestratorV3] Operation type: #{@is_new_app ? 'CREATE' : 'UPDATE'}"
      
      begin
        # Initialize app version for tracking
        create_app_version!
        
        # Define stages for progress tracking
        define_execution_stages
        
        # Step 1: Analysis phase
        @broadcaster.enter_stage(:analyzing)
        structure_response = analyze_app_structure_gpt5
        return handle_failure(structure_response[:message]) if structure_response[:error]
        
        # Step 2: Planning phase
        @broadcaster.enter_stage(:planning)
        plan_response = create_execution_plan_gpt5(structure_response[:analysis])
        return handle_failure(plan_response[:message]) if plan_response[:error]
        
        # Step 3: Implementation phase
        @broadcaster.enter_stage(:coding)
        execution_response = execute_with_gpt5_tools(plan_response[:plan])
        return handle_failure(execution_response[:message]) if execution_response[:error]
        
        # Step 4: Review and optimize
        @broadcaster.enter_stage(:reviewing)
        review_and_optimize(execution_response[:result])
        
        # Step 5: Deploy if new app
        if @is_new_app
          @broadcaster.enter_stage(:deploying)
          setup_post_generation_features
        end
        
        # Step 6: Finalize
        finalize_update_gpt5(execution_response[:result])
        
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] Error: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        handle_failure(e.message)
      end
    end
    
    private
    
    def determine_if_new_app
      # App is new if it has no files or versions yet
      @app.app_files.empty? && @app.app_versions.empty?
    end
    
    def create_app_version!
      @app_version = @app.app_versions.create!(
        team: @app.team,
        user: @user,
        version_number: next_version_number,
        changelog: @chat_message.content,
        status: 'in_progress',
        started_at: Time.current
      )
      
      # Broadcast initial version card
      broadcast_version_update
    end
    
    def next_version_number
      last_version = @app.app_versions.where.not(id: @app_version&.id).order(created_at: :desc).first
      if last_version
        parts = last_version.version_number.split(".")
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join(".")
      else
        "1.0.0"
      end
    end
    
    def define_execution_stages
      stages = if @is_new_app
        [
          { name: :analyzing, description: "Understanding your requirements" },
          { name: :planning, description: "Creating app architecture" },
          { name: :coding, description: "Building your application" },
          { name: :reviewing, description: "Optimizing and polishing" },
          { name: :deploying, description: "Setting up deployment" }
        ]
      else
        [
          { name: :analyzing, description: "Analyzing current app structure" },
          { name: :planning, description: "Planning changes" },
          { name: :coding, description: "Implementing updates" },
          { name: :reviewing, description: "Reviewing changes" }
        ]
      end
      
      @broadcaster.define_stages(stages)
    end
    
    def analyze_app_structure_gpt5
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Analysis Phase"
      
      # Update progress
      @broadcaster.update("Analyzing app requirements...", 0.3)
      
      # Get current app state
      current_files = get_cached_or_load_files || []
      env_vars = get_cached_or_load_env_vars || []
      
      # Load AI app standards
      standards_content = load_ai_standards
      
      # Build comprehensive analysis prompt
      analysis_prompt = if @is_new_app
        build_new_app_analysis_prompt(standards_content)
      else
        build_update_analysis_prompt(current_files, standards_content)
      end
      
      messages = [
        {
          role: "system",
          content: "You are an expert web developer analyzing app requirements. Follow AI_APP_STANDARDS strictly. Always respond with valid JSON."
        },
        {
          role: "user",
          content: analysis_prompt
        }
      ]
      
      # Use OpenAI or fallback to OpenRouter
      @broadcaster.update("Calling AI for analysis...", 0.5)
      
      if @use_openai_direct
        response = stream_gpt5_response(messages)
      else
        response = @client.chat(messages, model: :gpt5, temperature: 1.0)
      end
      
      if response[:success]
        analysis = parse_json_response(response[:content])
        
        # Update version with analysis info
        @app_version.update!(
          metadata: (@app_version.metadata || {}).merge(
            analysis_complexity: analysis&.dig('complexity_level'),
            estimated_files: analysis&.dig('estimated_files')
          )
        )
        
        @broadcaster.update("Analysis complete: #{analysis&.dig('complexity_level') || 'moderate'} complexity", 0.8)
        
        { success: true, analysis: analysis }
      else
        { error: true, message: response[:error] }
      end
    end
    
    def create_execution_plan_gpt5(analysis)
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Planning Phase"
      
      @broadcaster.update("Creating execution plan...", 0.2)
      
      # Load standards for planning
      standards_content = load_ai_standards
      
      # Build planning prompt with standards
      plan_prompt = <<~PROMPT
        #{@is_new_app ? 'CREATE NEW APP' : 'UPDATE EXISTING APP'}
        User Request: "#{chat_message.content}"
        
        App: #{app.name} (#{app.app_type} - #{app.framework})
        Analysis: #{analysis.to_json}
        
        Create a detailed execution plan following these standards:
        #{standards_content[0..2000]}  # Include key standards
        
        Available Tools:
        - create_file: Create new files
        - update_file: Modify existing files
        - broadcast_progress: Send status updates
        - create_version_snapshot: Save version state
        - finish_app: Complete the operation
        
        Return JSON plan:
        {
          "summary": "Clear description of what will be built/changed",
          "approach": "Technical approach and architecture",
          "steps": [
            {
              "phase": "setup|core|features|polish",
              "description": "Step description",
              "files_to_create": ["path/to/file.ext"],
              "files_to_update": ["path/to/existing.ext"],
              "key_features": ["feature1", "feature2"]
            }
          ],
          "estimated_files": 5,
          "includes_auth": #{@is_new_app ? 'true/false based on requirements' : 'false'},
          "database_tables": ["table_names_if_needed"],
          "complexity": "simple|moderate|complex"
        }
      PROMPT
      
      messages = [
        {
          role: "system",
          content: "You are an expert web developer creating execution plans. Create detailed, step-by-step plans that follow AI_APP_STANDARDS. Respond with valid JSON only."
        },
        {
          role: "user",
          content: plan_prompt
        }
      ]
      
      @broadcaster.update("Creating execution plan...", 0.5)
      
      if @use_openai_direct
        response = stream_gpt5_response(messages)
      else
        response = @client.chat(messages, model: :gpt5, temperature: 1.0)
      end
      
      if response[:success]
        plan = parse_json_response(response[:content])
        
        # Update version with plan details
        @app_version.update!(
          changelog: plan&.dig('summary'),
          metadata: (@app_version.metadata || {}).merge(
            plan_approach: plan&.dig('approach'),
            includes_auth: plan&.dig('includes_auth'),
            database_tables: plan&.dig('database_tables')
          )
        )
        
        @broadcaster.update("Plan ready: #{plan&.dig('summary') || 'Ready to implement'}", 1.0)
        broadcast_version_update
        
        { success: true, plan: plan }
      else
        { error: true, message: response[:error] }
      end
    end
    
    def execute_with_gpt5_tools(plan)
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Tool Execution Phase"
      
      @broadcaster.update("Starting implementation...", 0.1)
      
      # Track implementation progress
      total_steps = plan&.dig('steps')&.size || 1
      current_step = 0
      
      # Enhanced tools with version tracking
      tools = [
        {
          type: "function",
          function: {
            name: "create_file",
            description: "Create or overwrite a file with content",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path (e.g. 'src/App.jsx', 'index.html')" },
                content: { type: "string", description: "Complete file content" },
                file_type: { type: "string", description: "File type (html, css, js, jsx)" }
              },
              required: ["path", "content"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "update_file", 
            description: "Update existing file with find/replace",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path to update" },
                find: { type: "string", description: "Text to find" },
                replace: { type: "string", description: "Text to replace with" }
              },
              required: ["path", "find", "replace"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "broadcast_progress",
            description: "Send progress update to user",
            parameters: {
              type: "object",
              properties: {
                message: { type: "string", description: "Progress message" },
                percentage: { type: "integer", description: "Progress percentage 0-100" },
                file_count: { type: "integer", description: "Number of files created/modified so far" }
              },
              required: ["message"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "create_version_snapshot",
            description: "Save current state as version snapshot",
            parameters: {
              type: "object",
              properties: {
                description: { type: "string", description: "What was accomplished in this snapshot" },
                files_modified: { type: "array", items: { type: "string" }, description: "List of files modified" }
              },
              required: ["description"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "finish_app",
            description: "Mark app implementation as complete",
            parameters: {
              type: "object",
              properties: {
                summary: { type: "string", description: "Summary of changes made" }
              },
              required: ["summary"]
            }
          }
        }
      ]
      
      # Load current app state and standards
      file_contents = {}
      app.app_files.each { |file| file_contents[file.path] = file.content }
      standards_content = load_ai_standards
      
      # Comprehensive execution prompt with standards
      execution_prompt = <<~PROMPT
        #{@is_new_app ? 'BUILD NEW APP' : 'UPDATE APP'}: "#{chat_message.content}"
        
        App: #{app.name} (#{app.app_type})
        Plan: #{plan.to_json}
        
        #{@is_new_app ? '' : "Current Files:\n#{file_contents.map { |path, content| "#{path}:\n#{content[0..500]}..." }.join("\n\n")}"}
        
        CRITICAL STANDARDS TO FOLLOW:
        #{standards_content}
        
        IMPLEMENTATION REQUIREMENTS:
        1. Follow AI_APP_STANDARDS exactly - React SPA with CDN, Tailwind CSS, modern patterns
        2. Create COMPLETE, WORKING functionality - not prototypes
        3. Include authentication if app has user data (todo, notes, personal items)
        4. Use broadcast_progress frequently with descriptive messages
        5. Create professional UI with proper colors, spacing, interactions
        6. Include realistic sample data (5-10 items minimum)
        7. Add loading states, error handling, success feedback
        8. Make it mobile-responsive with proper breakpoints
        9. Use create_version_snapshot after major milestones
        10. End with finish_app providing comprehensive summary
        
        #{@is_new_app ? 'Start by creating index.html with React CDN setup, then src/App.jsx as the main component.' : 'Modify existing files to add the requested functionality.'}
      PROMPT
      
      messages = [
        {
          role: "system",
          content: "You are an expert web developer implementing professional apps. Use the provided tools to create high-quality, working applications that follow AI_APP_STANDARDS exactly."
        },
        {
          role: "user",
          content: execution_prompt
        }
      ]
      
      files_created = []
      max_iterations = 25  # Increased for complex apps
      iteration = 0
      last_progress_update = Time.current
      
      while iteration < max_iterations
        iteration += 1
        Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 iteration #{iteration}"
        
        # Update progress periodically
        if Time.current - last_progress_update > 2.seconds
          progress_pct = (iteration.to_f / max_iterations * 100).round
          @broadcaster.update("Building your app... (#{files_created.size} files created)", progress_pct / 100.0)
          last_progress_update = Time.current
        end
        
        if @use_openai_direct
          # Use OpenAI direct API with streaming tool calls
          response = stream_gpt5_with_tools(messages, tools)
        else
          response = @client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
        end
        
        unless response[:success]
          Rails.logger.error "[AppUpdateOrchestratorV3] GPT-5 failed: #{response[:error]}"
          execution_message.update!(
            content: "❌ Implementation failed: #{response[:error]}",
            status: "failed"
          )
          return { error: true, message: response[:error] }
        end
        
        # Add assistant response to conversation
        messages << {
          role: "assistant",
          content: response[:content],
          tool_calls: response[:tool_calls]
        }
        
        # Process tool calls
        if response[:tool_calls]
          tool_results = []
          
          response[:tool_calls].each do |tool_call|
            function_name = tool_call["function"]["name"]
            args = JSON.parse(tool_call["function"]["arguments"])
            
            case function_name
            when "create_file"
              result = handle_create_file(args)
              files_created << args if result[:success]
              tool_results << create_tool_result(tool_call["id"], result)
              
            when "update_file"
              result = handle_update_file(args)
              tool_results << create_tool_result(tool_call["id"], result)
              
            when "broadcast_progress"
              handle_broadcast_progress(args)
              tool_results << create_tool_result(tool_call["id"], { success: true, message: "Progress updated" })
              
            when "create_version_snapshot"
              handle_version_snapshot(args)
              tool_results << create_tool_result(tool_call["id"], { success: true, message: "Snapshot saved" })
              
            when "finish_app"
              summary = args["summary"]
              @broadcaster.update("Finalizing implementation...", 0.95)
              
              # Update version with completion info
              @app_version.update!(
                files_snapshot: app.app_files.map { |f| 
                  { path: f.path, content: f.content, file_type: f.file_type }
                }.to_json,
                changed_files: @files_modified.uniq.join(", "),
                completed_at: Time.current,
                status: 'completed'
              )
              
              return { success: true, result: { summary: summary, files: files_created } }
            end
          end
          
          # Add tool results to conversation
          messages += tool_results
        else
          # No tool calls, AI is done
          break
        end
      end
      
      # If we get here, max iterations reached
      @broadcaster.update("Implementation complete", 1.0)
      
      # Save final state
      @app_version.update!(
        files_snapshot: app.app_files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json,
        changed_files: @files_modified.uniq.join(", "),
        completed_at: Time.current,
        status: 'completed'
      )
      
      { success: true, result: { files: files_created } }
    end
    
    def handle_create_file(args)
      path = args["path"]
      content = args["content"]
      file_type = args["file_type"] || determine_file_type(path)
      
      begin
        # Validate content against standards if JavaScript/JSX
        if file_type.in?(['js', 'jsx']) && @is_new_app
          validation = validate_javascript_content(content)
          unless validation[:valid]
            Rails.logger.warn "[AppUpdateOrchestratorV3] Invalid JS in #{path}: #{validation[:error]}"
            content = fix_common_javascript_issues(content)
          end
        end
        
        # Create or update file in database
        file = app.app_files.find_by(path: path) || app.app_files.build(path: path, team: app.team)
        file.update!(
          content: content,
          file_type: file_type,
          size_bytes: content.bytesize
        )
        
        # Track for version
        @files_modified << path
        
        # Create version file record
        if @app_version
          @app_version.app_version_files.create!(
            app_file: file,
            content: content,
            action: file.id_previously_changed? ? 'created' : 'updated'
          )
        end
        
        Rails.logger.info "[AppUpdateOrchestratorV3] Created/updated file: #{path} (#{content.bytesize} bytes)"
        
        # Broadcast file creation to UI
        broadcast_file_update(path, 'created')
        
        { success: true, message: "File #{path} created successfully" }
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] File creation failed: #{e.message}"
        { success: false, message: "Failed to create #{path}: #{e.message}" }
      end
    end
    
    def handle_update_file(args)
      path = args["path"]
      find_text = args["find"]
      replace_text = args["replace"]
      
      begin
        file = app.app_files.find_by(path: path)
        unless file
          return { success: false, message: "File #{path} not found" }
        end
        
        updated_content = file.content.gsub(find_text, replace_text)
        
        # Validate if JavaScript
        if file.file_type.in?(['js', 'jsx'])
          validation = validate_javascript_content(updated_content)
          unless validation[:valid]
            Rails.logger.warn "[AppUpdateOrchestratorV3] Invalid JS after update in #{path}: #{validation[:error]}"
            updated_content = fix_common_javascript_issues(updated_content)
          end
        end
        
        file.update!(
          content: updated_content,
          size_bytes: updated_content.bytesize
        )
        
        # Track for version
        @files_modified << path
        
        # Create version file record
        if @app_version
          @app_version.app_version_files.create!(
            app_file: file,
            content: updated_content,
            action: 'updated'
          )
        end
        
        Rails.logger.info "[AppUpdateOrchestratorV3] Updated file: #{path}"
        
        # Broadcast file update to UI
        broadcast_file_update(path, 'updated')
        
        { success: true, message: "File #{path} updated successfully" }
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] File update failed: #{e.message}"
        { success: false, message: "Failed to update #{path}: #{e.message}" }
      end
    end
    
    def handle_broadcast_progress(args)
      message = args["message"]
      percentage = args["percentage"]
      file_count = args["file_count"]
      
      progress_text = message
      progress_text += " (#{percentage}%)" if percentage
      progress_text += " - #{file_count} files" if file_count
      
      # Use broadcaster for consistent progress updates
      @broadcaster.update(progress_text, (percentage || 50) / 100.0)
      
      # Update version status
      if @app_version
        @app_version.update!(
          metadata: (@app_version.metadata || {}).merge(
            last_progress_message: progress_text,
            last_progress_at: Time.current
          )
        )
        broadcast_version_update
      end
    end
    
    def handle_version_snapshot(args)
      description = args["description"]
      files_modified = args["files_modified"] || @files_modified
      
      if @app_version
        @app_version.update!(
          changelog: [@app_version.changelog, description].compact.join("\n\n"),
          changed_files: files_modified.uniq.join(", "),
          files_snapshot: app.app_files.map { |f| 
            { path: f.path, content: f.content, file_type: f.file_type }
          }.to_json
        )
        
        broadcast_version_update
      end
    end
    
    def create_tool_result(tool_call_id, result)
      {
        tool_call_id: tool_call_id,
        role: "tool",
        content: JSON.generate(result)
      }
    end
    
    def finalize_update_gpt5(result)
      Rails.logger.info "[AppUpdateOrchestratorV3] Finalizing GPT-5 update"
      
      # Calculate duration
      duration = Time.current - @start_time
      
      # Build comprehensive summary
      summary = build_completion_summary(result, duration)
      
      # Complete broadcasting
      @broadcaster.complete(summary)
      
      # Update app status
      @app.update!(
        status: @is_new_app ? 'generated' : 'ready',
        last_updated_at: Time.current
      )
      
      # Update version final state
      @app_version.update!(
        status: 'completed',
        completed_at: Time.current,
        display_name: generate_version_display_name(result)
      )
      
      # Create final assistant message
      final_message = create_assistant_message(
        summary,
        "completed"
      )
      
      # Link message to version
      final_message.update!(app_version: @app_version)
      
      # Broadcast final updates
      broadcast_message_update(final_message)
      broadcast_version_update
      broadcast_app_update
      
      # Trigger preview update
      UpdatePreviewJob.perform_later(@app.id) if @app.app_files.any?
    end
    
    # Enhanced helper methods
    def create_assistant_message(content, status)
      app.app_chat_messages.create!(
        role: "assistant",
        content: content,
        status: status,
        app_version: @app_version
      )
    end
    
    def broadcast_message_update(message)
      # Use the message ID directly for targeting
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "app_chat_message_#{message.id}",
        partial: "account/app_editors/chat_message",
        locals: { message: message }
      )
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV3] Broadcast failed: #{e.message}"
      Rails.logger.error "Ensure ActionCable is configured and Redis is running"
      # Re-raise to identify configuration issues
      raise
    end
    
    def broadcast_version_update
      return unless @app_version
      
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_versions",
        target: "app_version_#{@app_version.id}",
        partial: "account/app_versions/app_version",
        locals: { app_version: @app_version }
      )
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV3] Version broadcast failed: #{e.message}"
      Rails.logger.error "Check: 1) Redis is running, 2) ActionCable configured, 3) Partial exists"
      # Continue without crashing but log the issue
    end
    
    def broadcast_file_update(path, action)
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{@app.id}_file_updates",
        target: "file_updates_list",
        html: "<div class='text-sm text-gray-600'>#{action.capitalize} #{path}</div>"
      )
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV3] File broadcast failed: #{e.message}"
      # Continue - file updates are nice to have but not critical
    end
    
    def broadcast_app_update
      # Update app status badge
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_generation",
        target: "app_#{@app.id}_status",
        partial: "account/apps/status_badge",
        locals: { app: @app }
      )
      
      # Update preview if exists
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "preview_frame",
        partial: "account/app_editors/preview_frame",
        locals: { app: @app }
      )
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV3] App broadcast failed: #{e.message}"
      Rails.logger.error "This likely means the view partials are missing or ActionCable is not configured"
      # Continue - app can still function without live updates
    end
    
    def handle_failure(error_message)
      Rails.logger.error "[AppUpdateOrchestratorV3] Failure: #{error_message}"
      
      # Update broadcaster
      @broadcaster.fail(error_message)
      
      # Update app version
      if @app_version
        @app_version.update!(
          status: 'failed',
          error_message: error_message,
          completed_at: Time.current
        )
        broadcast_version_update
      end
      
      # Create error message
      error_msg = create_assistant_message(
        "❌ An error occurred: #{error_message}\n\nPlease try again or rephrase your request.",
        "failed"
      )
      
      broadcast_message_update(error_msg)
      broadcast_app_update
    end
    
    def parse_json_response(content)
      cleaned_content = content.strip
      
      # Try direct parse
      begin
        return JSON.parse(cleaned_content, symbolize_names: true)
      rescue JSON::ParserError
        # Extract from markdown
        json_match = cleaned_content.match(/```json\s*\n?(.+?)\n?```/mi) ||
                     cleaned_content.match(/```\s*\n?(.+?)\n?```/mi)
        
        if json_match
          begin
            return JSON.parse(json_match[1].strip, symbolize_names: true)
          rescue JSON::ParserError
            # Fall through
          end
        end
      end
      
      Rails.logger.warn "[AppUpdateOrchestratorV3] Failed to parse JSON response"
      nil
    end
    
    def determine_file_type(path)
      ext = File.extname(path).downcase.delete(".")
      case ext
      when "html", "htm" then "html"
      when "js", "jsx" then "js"
      when "css", "scss" then "css"
      when "json" then "json"
      else "text"
      end
    end
    
    def get_cached_or_load_files
      return [] unless app
      app.app_files.map do |file|
        {
          path: file.path,
          content: file.content,
          file_type: file.file_type,
          size: file.size_bytes
        }
      end
    end
    
    def get_cached_or_load_env_vars
      @app.env_vars_for_ai
    end
    
    def load_ai_standards
      # Load and cache AI standards
      @ai_standards ||= begin
        standards_path = Rails.root.join('AI_APP_STANDARDS.md')
        if File.exist?(standards_path)
          File.read(standards_path)
        else
          Rails.logger.warn "[AppUpdateOrchestratorV3] AI_APP_STANDARDS.md not found"
          "Follow best practices for React apps with Tailwind CSS."
        end
      end
    end
    
    def build_new_app_analysis_prompt(standards)
      <<~PROMPT
        Analyze requirements for NEW APP: "#{chat_message.content}"
        
        App Details:
        - Name: #{app.name}
        - Type: #{app.app_type}
        - Framework: React (CDN-based, no bundler)
        
        Key Standards:
        #{standards[0..3000]}
        
        Analyze and respond with JSON:
        {
          "current_structure": "Empty app - needs full implementation",
          "required_changes": [
            "Create React app structure with CDN setup",
            "Implement core functionality: [specific features]",
            "Add authentication if user data involved",
            "Create professional UI with Tailwind",
            "Add sample data and interactions"
          ],
          "complexity_level": "simple|moderate|complex",
          "estimated_files": 5,
          "technology_stack": ["react", "tailwind", "supabase"],
          "needs_auth": true/false,
          "database_tables": ["table_names"],
          "key_features": ["feature1", "feature2"]
        }
      PROMPT
    end
    
    def build_update_analysis_prompt(files, standards)
      <<~PROMPT
        Analyze requirements for APP UPDATE: "#{chat_message.content}"
        
        Current App:
        - Name: #{app.name}
        - Type: #{app.app_type}
        - Files: #{files.size} existing files
        
        Current Structure:
        #{files.map { |f| "- #{f[:path]} (#{f[:file_type]})" }.join("\n")}
        
        Key Standards:
        #{standards[0..2000]}
        
        Analyze what needs to change:
        {
          "current_structure": "Description of existing app",
          "required_changes": [
            "Specific changes needed for: #{chat_message.content}"
          ],
          "complexity_level": "simple|moderate|complex",
          "estimated_files": [number of files to modify/create],
          "files_to_update": ["existing/file/paths"],
          "files_to_create": ["new/file/paths"],
          "key_improvements": ["improvement1", "improvement2"]
        }
      PROMPT
    end
    
    def validate_javascript_content(content)
      # Basic validation for common issues
      issues = []
      
      # Check for TypeScript syntax
      if content.match(/:\s*(string|number|boolean|any|void)\s*[;,\)\}]/) ||
         content.match(/interface\s+\w+\s*\{/) ||
         content.match(/<\w+>/) # Generic syntax
        issues << "TypeScript syntax detected - should be plain JavaScript/JSX"
      end
      
      # Check for invalid JSX
      if content.match(/className=\{[^}]*\}/) && content.match(/className=\{\s*\}/)  
        issues << "Empty className binding detected"
      end
      
      { valid: issues.empty?, errors: issues }
    end
    
    def fix_common_javascript_issues(content)
      # Remove TypeScript type annotations
      fixed = content.gsub(/:\s*(string|number|boolean|any|void|\w+\[\])\s*(?=[;,\)\}=])/, '')
      
      # Remove interface declarations
      fixed = fixed.gsub(/interface\s+\w+\s*\{[^}]*\}/m, '')
      
      # Remove generic syntax
      fixed = fixed.gsub(/<[\w\s,]+>/, '')
      
      # Fix empty className
      fixed = fixed.gsub(/className=\{\s*\}/, 'className=""')
      
      fixed
    end
    
    def build_completion_summary(result, duration)
      files = result[:files] || []
      
      summary = if @is_new_app
        <<~SUMMARY
          ✅ **Your app "#{app.name}" has been created!**
          
          **What was built:**
          #{result[:summary] || 'Complete React application with all requested features'}
          
          **Files created:** #{files.size}
          #{files.take(5).map { |f| "• #{f['path']}" }.join("\n")}
          #{files.size > 5 ? "• ... and #{files.size - 5} more files" : ''}
          
          **Key features:**
          • Professional UI with Tailwind CSS
          • Responsive design for all devices  
          • Sample data included
          #{@app_version.metadata&.dig('includes_auth') ? '• User authentication integrated' : ''}
          
          **Time taken:** #{format_duration(duration)}
          
          Your app is ready to use! Try it out in the preview panel →
        SUMMARY
      else
        <<~SUMMARY
          ✅ **App updated successfully!**
          
          **Changes made:**
          #{result[:summary] || 'Updated app with requested features'}
          
          **Files modified:** #{@files_modified.size}
          #{@files_modified.take(5).map { |f| "• #{f}" }.join("\n")}
          #{@files_modified.size > 5 ? "• ... and #{@files_modified.size - 5} more files" : ''}
          
          **Time taken:** #{format_duration(duration)}
          
          Your changes are live in the preview! →
        SUMMARY
      end
      
      summary
    end
    
    def generate_version_display_name(result)
      if @is_new_app
        "Initial app creation"
      else
        # Generate descriptive name from changes
        summary = result[:summary] || @app_version.changelog
        summary&.split('.')&.first&.truncate(50) || "Update #{@app_version.version_number}"
      end
    end
    
    def review_and_optimize(result)
      @broadcaster.update("Reviewing and optimizing code...", 0.5)
      
      # Quick validation pass on all files
      app.app_files.each do |file|
        if file.file_type.in?(['js', 'jsx'])
          validation = validate_javascript_content(file.content)
          unless validation[:valid]
            Rails.logger.info "[AppUpdateOrchestratorV3] Fixing issues in #{file.path}"
            fixed_content = fix_common_javascript_issues(file.content)
            file.update!(content: fixed_content)
          end
        end
      end
      
      @broadcaster.update("Code review complete", 1.0)
    end
    
    def setup_post_generation_features
      @broadcaster.update("Setting up app features...", 0.3)
      
      # Create auth settings if needed
      if @app_version.metadata&.dig('includes_auth') || app_needs_authentication?
        create_auth_settings
      end
      
      # Setup database tables if specified
      tables = @app_version.metadata&.dig('database_tables')
      if tables.present?
        setup_database_tables(tables)
      end
      
      # Queue logo generation
      GenerateAppLogoJob.perform_later(@app.id)
      
      # Queue deployment if enabled
      if ENV["AUTO_DEPLOY_AFTER_GENERATION"] == "true"
        AppDeploymentJob.perform_later(@app)
      end
      
      @broadcaster.update("App setup complete", 1.0)
    end
    
    def app_needs_authentication?
      keywords = ['user', 'login', 'auth', 'account', 'personal', 'private', 'todo', 'note']
      prompt_text = "#{@chat_message.content} #{@app.name} #{@app.prompt}".downcase
      keywords.any? { |keyword| prompt_text.include?(keyword) }
    end
    
    def create_auth_settings
      return if @app.app_auth_setting.present?
      
      @app.create_app_auth_setting!(
        visibility: 'public_login_required',
        allowed_providers: ['email', 'google', 'github'],
        allowed_email_domains: [],
        require_email_verification: false,
        allow_signups: true,
        allow_anonymous: false
      )
      
      Rails.logger.info "[AppUpdateOrchestratorV3] Created auth settings for app ##{@app.id}"
    end
    
    def setup_database_tables(table_names)
      Rails.logger.info "[AppUpdateOrchestratorV3] Setting up tables: #{table_names.join(', ')}"
      
      begin
        # Check if Supabase service exists
        if defined?(Supabase::AutoTableService)
          table_service = Supabase::AutoTableService.new(@app)
          result = table_service.ensure_tables_exist!
          
          if result[:success]
            Rails.logger.info "[AppUpdateOrchestratorV3] Created tables: #{result[:tables].join(', ')}"
          end
        else
          # Create app_tables records for tracking
          table_names.each do |table_name|
            @app.app_tables.find_or_create_by!(name: table_name) do |table|
              table.team = @app.team
              table.schema_definition = { 
                columns: [
                  { name: 'id', type: 'uuid', primary: true },
                  { name: 'user_id', type: 'uuid', required: true },
                  { name: 'created_at', type: 'timestamp' },
                  { name: 'updated_at', type: 'timestamp' }
                ]
              }
            end
          end
          Rails.logger.info "[AppUpdateOrchestratorV3] Tracked tables in app_tables: #{table_names.join(', ')}"
        end
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] Table creation error: #{e.message}"
        # Don't fail the whole generation for database issues
      end
    end
    
    def format_duration(seconds)
      if seconds < 60
        "#{seconds.round} seconds"
      elsif seconds < 3600
        "#{(seconds / 60).round} minutes"
      else
        "#{(seconds / 3600).round(1)} hours"
      end
    end
    
    # Streaming support for OpenAI direct API
    def stream_gpt5_response(messages)
      # ALWAYS use GPT-5
      unless @use_openai_direct
        # OpenRouter uses :gpt5 symbol which maps to "openai/gpt-5"
        return @client.chat(messages, model: :gpt5, temperature: 1.0)
      end
      
      Rails.logger.info "[AppUpdateOrchestratorV3] Using OpenAI direct with model: gpt-5"
      
      begin
        # Use the OpenAI client directly with GPT-5
        response = @client.chat(messages, model: 'gpt-5', temperature: 1.0)
        
        if response[:success]
          { success: true, content: response[:content] }
        else
          { success: false, error: response[:error] }
        end
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] OpenAI call failed: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def stream_gpt5_with_tools(messages, tools)
      # ALWAYS use GPT-5 for tool calling
      unless @use_openai_direct
        # OpenRouter uses :gpt5 symbol which maps to "openai/gpt-5"
        return @client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
      end
      
      Rails.logger.info "[AppUpdateOrchestratorV3] Using OpenAI direct with tools, model: gpt-5"
      
      begin
        # OpenAI direct API with tool calling - GPT-5
        response = @client.chat_with_tools(
          messages, 
          tools,
          model: 'gpt-5',
          temperature: 1.0  # GPT-5 uses default temperature
        )
        
        # Handle tool calls
        if response[:tool_calls]
          Rails.logger.info "[AppUpdateOrchestratorV3] Received #{response[:tool_calls].size} tool calls"
        end
        
        response
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] Tool calling failed: #{e.message}"
        { success: false, error: e.message }
      end
    end
  end
end