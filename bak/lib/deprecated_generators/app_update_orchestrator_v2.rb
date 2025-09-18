module Ai
  # Enhanced orchestrator with tool calling and incremental file updates
  class AppUpdateOrchestratorV2
    MAX_IMPROVEMENT_ITERATIONS = 3

    attr_reader :chat_message, :app, :user

    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @iteration_count = 0
      @improvements_made = []
      @client = OpenRouterClient.new
      @context_cache = Ai::ContextCacheService.new
    end

    def execute!
      Rails.logger.info "[AppUpdateOrchestratorV2] Starting enhanced orchestrated update for message ##{chat_message.id}"

      # Step 1: Analyze app structure and context
      structure_response = analyze_app_structure
      return if structure_response[:error]

      # Step 2: Create execution plan with tool definitions
      plan_response = create_execution_plan(structure_response[:analysis])
      return if plan_response[:error]

      # Step 3: Execute with tool calling and incremental updates
      execution_response = execute_with_tools(plan_response[:plan])
      return if execution_response[:error]

      # Step 4: Validate and finalize
      finalize_update(execution_response[:result])
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV2] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      create_error_response(e.message)
    end

    private

    def analyze_app_structure
      Rails.logger.info "[AppUpdateOrchestratorV2] Step 1: Analyzing app structure"

      # Create analysis message
      analysis_message = create_assistant_message(
        "🔍 Analyzing your app structure and understanding the request...",
        "executing"
      )

      # Get current app files with caching
      current_files = get_cached_or_load_files || []

      # Load AI standards with caching
      ai_standards = @context_cache.cache_ai_standards || ""

      # Get available environment variables with caching
      env_vars = get_cached_or_load_env_vars || []

      # Build analysis prompt
      analysis_prompt = <<~PROMPT
        You are analyzing a web application to understand its structure and plan updates.
        
        Current Request: #{chat_message.content}
        
        App Name: #{app.name}
        App Type: #{app.app_type}
        Framework: #{app.framework}
        
        Current Files:
        #{(current_files || []).map { |f| "- #{f[:path]} (#{f[:type]}, #{f[:size]} bytes)" }.join("\n")}
        
        Available Environment Variables:
        #{(env_vars || []).map { |v| "- #{v[:key]}: #{v[:description]}" }.join("\n")}
        Note: Access these in code using window.getEnv('KEY_NAME')
        
        AI STANDARDS TO FOLLOW:
        #{ai_standards}
        
        Analyze the app structure and provide:
        1. Current app architecture understanding
        2. What needs to be changed based on the request
        3. Which files need to be modified, created, or deleted
        4. Any potential challenges or considerations
        5. Which environment variables might be needed
        
        Return a JSON object with:
        {
          "architecture": "Description of current app architecture",
          "changes_needed": ["List of changes needed"],
          "files_to_modify": ["file1.js", "file2.html"],
          "files_to_create": ["newfile.js"],
          "files_to_delete": [],
          "considerations": ["Any important considerations"],
          "approach": "High-level approach to implement changes",
          "env_vars_needed": ["List of any new env vars needed"]
        }
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert web developer analyzing application structure and planning updates. Always follow the AI_APP_STANDARDS provided."
        },
        {
          role: "user",
          content: analysis_prompt
        }
      ]

      response = @client.chat(messages, temperature: 0.3)

      if response[:success]
        analysis = parse_json_response(response[:content])

        # Update analysis message with results
        analysis_content = format_analysis_message(analysis)
        analysis_message.update!(
          content: analysis_content,
          status: "completed"
        )
        broadcast_message_update(analysis_message)

        {success: true, analysis: analysis}
      else
        analysis_message.update!(
          content: "❌ Failed to analyze app structure. Please try again.",
          status: "failed"
        )
        broadcast_message_update(analysis_message)

        {error: true, message: response[:error]}
      end
    end

    def create_execution_plan(analysis)
      Rails.logger.info "[AppUpdateOrchestratorV2] Step 2: Creating execution plan"

      # Create planning message
      planning_message = create_assistant_message(
        "📝 Creating a detailed execution plan...",
        "executing"
      )

      # Define available tools for the AI

      # Build execution planning prompt
      plan_prompt = <<~PROMPT
        Based on the analysis, create a detailed execution plan using the available tools.
        
        Analysis Summary:
        #{analysis.to_json}
        
        User Request: #{chat_message.content}
        
        Create a step-by-step plan that:
        1. Reads necessary files first to understand current implementation
        2. Makes changes incrementally with progress updates
        3. Creates new files as needed
        4. Tests/validates changes
        5. Provides clear progress feedback to the user
        
        Important:
        - Always broadcast progress updates between file operations
        - Read files before modifying them
        - Follow the AI_APP_STANDARDS strictly
        - Include realistic sample data
        - Ensure mobile responsiveness
        - Add proper error handling
        
        Return a JSON execution plan:
        {
          "steps": [
            {
              "description": "Step description",
              "tool_calls": [
                {
                  "tool": "broadcast_progress",
                  "params": {"message": "Starting implementation...", "percentage": 0}
                },
                {
                  "tool": "read_file",
                  "params": {"path": "index.html"}
                }
              ]
            }
          ],
          "estimated_operations": 10,
          "summary": "Brief summary of what will be done"
        }
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert web developer creating an execution plan. Break down the work into clear, incremental steps with progress updates."
        },
        {
          role: "user",
          content: plan_prompt
        }
      ]

      response = @client.chat(messages, temperature: 0.3)

      if response[:success]
        plan = parse_json_response(response[:content])

        # Update planning message
        plan_content = format_plan_message(plan)
        planning_message.update!(
          content: plan_content,
          status: "completed"
        )
        broadcast_message_update(planning_message)

        {success: true, plan: plan}
      else
        planning_message.update!(
          content: "❌ Failed to create execution plan.",
          status: "failed"
        )
        broadcast_message_update(planning_message)

        {error: true, message: response[:error]}
      end
    end

    def execute_with_tools(plan)
      Rails.logger.info "[AppUpdateOrchestratorV2] Step 3: Executing with tools"

      # Create execution message
      execution_message = create_assistant_message(
        "🚀 Implementing the changes to your app...",
        "executing"
      )

      # Load AI standards for context
      ai_standards = File.read(Rails.root.join("AI_APP_STANDARDS.md"))

      # Get complete file contents
      file_contents = {}
      app.app_files.each do |file|
        file_contents[file.path] = file.content
      end

      # Get environment variables for context
      env_vars = app.env_vars_for_ai

      # Build the main execution prompt with all context
      execution_prompt = <<~PROMPT
        Execute the following plan to update the web application.
        
        User Request: #{chat_message.content}
        
        Current App Context:
        - Name: #{app.name}
        - Type: #{app.app_type}
        - Framework: #{app.framework}
        
        Available Environment Variables:
        #{env_vars.map { |v| "#{v[:key]} - #{v[:description]}" }.join("\n")}
        Use window.getEnv('KEY_NAME') to access these in JavaScript code.
        
        Execution Plan:
        #{plan["summary"]}
        
        Current File Contents:
        #{file_contents.map { |path, content| "=== #{path} ===\n#{content[0..1000]}...\n" }.join("\n")}
        
        AI STANDARDS (MUST FOLLOW):
        #{ai_standards}
        
        CRITICAL REQUIREMENTS:
        1. Use function calling to execute the plan step by step
        2. Send progress updates frequently using broadcast_progress
        3. Read files before modifying them
        4. PREFER line_replace over write_file for small changes (Lovable best practice)
        5. Use line_replace with ellipsis (...) for large section replacements
        6. Create complete, professional implementations
        7. Include realistic sample data (5-10 items minimum)
        8. Use Tailwind CSS classes for all styling
        9. Implement proper error handling and loading states
        10. Ensure mobile responsiveness
        11. Follow modern JavaScript patterns (ES6+)
        12. Make the app fully functional, not a prototype
        
        Start by broadcasting that you're beginning implementation, then proceed with the file operations.
      PROMPT

      # Define the tools again for execution context
      tools = build_execution_tools

      messages = [
        {
          role: "system",
          content: "You are implementing changes to a web application. Use the provided tools to read, write, and update files while keeping the user informed of progress. Follow the AI_APP_STANDARDS strictly."
        },
        {
          role: "user",
          content: execution_prompt
        }
      ]

      # Execute with tool calling
      result = execute_tool_calls(messages, tools, execution_message)

      if result[:success]
        execution_message.update!(
          content: "✅ Successfully implemented all changes!",
          status: "completed"
        )
        broadcast_message_update(execution_message)

        {success: true, result: result}
      else
        execution_message.update!(
          content: "❌ Failed to complete implementation: #{result[:error]}",
          status: "failed"
        )
        broadcast_message_update(execution_message)

        {error: true, message: result[:error]}
      end
    end

    def execute_tool_calls(messages, tools, status_message)
      Rails.logger.info "[AppUpdateOrchestratorV2] Executing tool calls"

      max_iterations = 20  # Prevent infinite loops
      iteration = 0
      conversation_messages = messages.dup
      files_modified = []

      while iteration < max_iterations
        iteration += 1

        # For Anthropic compatibility, use a simpler conversation approach
        # to avoid tool ID mismatches across iterations
        if @client.instance_variable_get(:@anthropic_client)
          # Use only essential context for Anthropic to avoid tool ID issues
          simple_messages = [
            conversation_messages[0], # system message
            {
              role: "user",
              content: "#{conversation_messages[1][:content]}\n\nCurrent iteration: #{iteration}/#{max_iterations}. Continue implementing the plan using the provided tools."
            }
          ]
          request_messages = simple_messages
        else
          request_messages = conversation_messages
        end

        # Call AI with tools (use dynamic token allocation)
        response = @client.chat_with_tools(
          request_messages,
          tools,
          temperature: 0.3
          # max_tokens will be calculated dynamically based on prompt length
        )

        unless response[:success]
          Rails.logger.error "[AppUpdateOrchestratorV2] Tool calling failed: #{response[:error]}"
          return {success: false, error: response[:error]}
        end

        # Check if we have tool calls to execute
        tool_calls = response[:tool_calls]

        if tool_calls.nil? || tool_calls.empty?
          # No more tool calls, check if we have content to show
          if response[:content] && !response[:content].empty?
            Rails.logger.info "[AppUpdateOrchestratorV2] AI response without tools: #{response[:content][0..200]}"
            # The AI chose to respond without using tools - this is the final response
          else
            Rails.logger.info "[AppUpdateOrchestratorV2] No more tool calls, execution complete"
          end
          break
        end

        # Add assistant's response to conversation
        conversation_messages << {
          role: "assistant",
          content: response[:content],
          tool_calls: tool_calls
        }

        # Execute each tool call
        tool_results = []
        tool_calls.each do |tool_call|
          result = execute_single_tool(tool_call, status_message)

          # Only add result if we have a valid tool_call_id (handle both string and symbol keys)
          tool_call_id = tool_call&.dig(:id) || tool_call&.dig("id")
          if tool_call && tool_call_id
            tool_results << {
              tool_call_id: tool_call_id,
              role: "tool",
              content: result.to_json
            }
          else
            Rails.logger.warn "[AppUpdateOrchestratorV2] Tool call missing ID: #{tool_call.inspect}"
          end

          # Track modified files (with safe navigation and string/symbol key handling)
          function_data = tool_call&.dig(:function) || tool_call&.dig("function")
          if function_data &&
              (function_data[:name] == "write_file" || function_data["name"] == "write_file") &&
              result[:success]

            # Get path from arguments (could be string or hash)
            args = function_data[:arguments] || function_data["arguments"]
            if args.is_a?(Hash)
              path = args["path"] || args[:path]
            elsif args.is_a?(String)
              parsed_args = begin
                JSON.parse(args)
              rescue
                {}
              end
              path = parsed_args["path"]
            end

            files_modified << path if path
          end
        end

        # Add tool results to conversation
        tool_results.each do |result|
          conversation_messages << result
        end
      end

      # Update preview after all changes
      if files_modified.any?
        UpdatePreviewJob.perform_later(app.id)
      end

      {success: true, files_modified: files_modified}
    end

    def execute_single_tool(tool_call, status_message)
      # Add nil checking for tool_call structure (handle both string and symbol keys)
      function_data = tool_call&.dig(:function) || tool_call&.dig("function")
      unless tool_call && function_data
        Rails.logger.error "[AppUpdateOrchestratorV2] Invalid tool_call structure: #{tool_call.inspect}"
        return {success: false, error: "Invalid tool call structure"}
      end

      function_name = function_data[:name] || function_data["name"]
      arguments = function_data[:arguments] || function_data["arguments"] || {}

      # If arguments is a JSON string, parse it
      if arguments.is_a?(String)
        begin
          arguments = JSON.parse(arguments)
        rescue JSON::ParserError => e
          Rails.logger.error "[AppUpdateOrchestratorV2] Failed to parse arguments JSON: #{e.message}"
          return {success: false, error: "Invalid arguments format"}
        end
      end

      Rails.logger.info "[AppUpdateOrchestratorV2] Executing tool: #{function_name} with args: #{arguments.inspect}"

      case function_name
      when "read_file"
        read_file_tool(arguments["path"])
      when "write_file"
        write_file_tool(arguments["path"], arguments["content"], arguments["file_type"], status_message)
      when "update_file"
        update_file_tool(arguments["path"], arguments["updates"], status_message)
      when "line_replace"
        line_replace_tool(arguments["file_path"], arguments["search"], arguments["first_line"], arguments["last_line"], arguments["replace"], status_message)
      when "delete_file"
        delete_file_tool(arguments["path"], status_message)
      when "search_files"
        search_files_tool(arguments["query"], arguments["include_pattern"], arguments["exclude_pattern"], arguments["case_sensitive"], status_message)
      when "rename_file"
        rename_file_tool(arguments["old_path"], arguments["new_path"], status_message)
      when "read_console_logs"
        read_console_logs_tool(arguments["search"], arguments["limit"], status_message)
      when "read_network_requests"
        read_network_requests_tool(arguments["search"], arguments["limit"], status_message)
      when "add_dependency"
        add_dependency_tool(arguments["package"], arguments["is_dev"], status_message)
      when "remove_dependency"
        remove_dependency_tool(arguments["package"], status_message)
      when "web_search"
        web_search_tool(arguments["query"], arguments["num_results"], arguments["category"], status_message)
      when "download_to_repo"
        download_to_repo_tool(arguments["source_url"], arguments["target_path"], status_message)
      when "fetch_website"
        fetch_website_tool(arguments["url"], arguments["formats"], status_message)
      when "broadcast_progress"
        broadcast_progress_tool(arguments["message"], arguments["percentage"], status_message)
      when "generate_image"
        generate_image_tool(arguments["prompt"], arguments["target_path"], arguments["width"], arguments["height"], arguments["style_preset"], status_message)
      when "edit_image"
        edit_image_tool(arguments["image_paths"], arguments["prompt"], arguments["target_path"], arguments["strength"], status_message)
      when "read_analytics"
        read_analytics_tool(arguments["time_range"], arguments["metrics"], status_message)
      when "git_status"
        git_status_tool(status_message)
      when "git_commit"
        git_commit_tool(arguments["message"], status_message)
      when "git_branch"
        git_branch_tool(arguments["branch_name"], arguments["checkout"], status_message)
      when "git_diff"
        git_diff_tool(arguments["file_path"], arguments["from_commit"], arguments["to_commit"], status_message)
      when "git_log"
        git_log_tool(arguments["limit"], status_message)
      else
        {success: false, error: "Unknown tool: #{function_name}"}
      end
    end

    def read_file_tool(path)
      file = app.app_files.find_by(path: path)
      if file
        {success: true, content: file.content}
      else
        {success: false, error: "File not found: #{path}"}
      end
    end

    def write_file_tool(path, content, file_type, status_message)
      # Broadcast that we're working on this file
      broadcast_file_progress("✏️ Writing #{path}...", status_message)

      # Process "keep existing code" patterns (Lovable's optimization)
      processed_content = process_keep_existing_code_patterns(path, content)

      file = app.app_files.find_or_initialize_by(path: path)
      file.content = processed_content
      file.file_type = file_type || detect_file_type(path)
      file.team = app.team if file.new_record? # Ensure team is set for BulletTrain validation

      if file.save
        # Clear cache since file changed
        @context_cache.clear_app_cache(app.id)
        broadcast_file_progress("✅ Wrote #{path}", status_message)
        {success: true, message: "File #{path} saved successfully"}
      else
        {success: false, error: "Failed to save #{path}: #{file.errors.full_messages.join(", ")}"}
      end
    end

    # Process "... keep existing code" patterns to minimize changes (Lovable pattern)
    def process_keep_existing_code_patterns(file_path, new_content)
      # Pattern to match: // ... keep existing code (optional description)
      # Also supports: /* ... keep existing code */ for CSS/JS
      # And {/* ... keep existing code */} for JSX
      keep_pattern = /(?:\/\/|\/\*|\{\s*\/\*)\s*\.\.\.\s*keep\s+existing\s+code(?:\s*\([^)]*\))?\s*(?:\*\/|\*\/\s*\})?/i

      # If no keep patterns found, return content as-is
      return new_content unless new_content.match?(keep_pattern)

      # Get the existing file content
      existing_file = app.app_files.find_by(path: file_path)
      return new_content unless existing_file&.content.present?

      Rails.logger.info "[KeepExistingCode] Processing keep patterns for #{file_path}"

      # Split content into sections and process each keep pattern
      sections = new_content.split(keep_pattern)
      keep_matches = new_content.scan(keep_pattern)

      # If we have sections to preserve
      if sections.length > 1 && existing_file.content.present?
        result = sections[0] # Start with first section before any keep pattern

        # For each keep pattern found, try to preserve the corresponding section
        keep_matches.each_with_index do |keep_match, index|
          # Try to find what should be kept based on surrounding context
          before_section = sections[index]
          after_section = sections[index + 1]

          # Extract the preserved section from existing file
          preserved = extract_section_between(existing_file.content, before_section, after_section)

          if preserved
            result += preserved
            Rails.logger.info "[KeepExistingCode] Preserved section #{index + 1} in #{file_path}"
          else
            # If we can't find it, include the keep comment as documentation
            result += keep_match
            Rails.logger.warn "[KeepExistingCode] Could not locate section #{index + 1} in #{file_path}"
          end

          # Add the section after this keep pattern
          result += after_section if after_section
        end

        return result
      end

      new_content
    end

    # Extract section from existing content between two markers
    def extract_section_between(existing_content, before_marker, after_marker)
      return nil unless before_marker.present? || after_marker.present?

      # Clean up markers for matching
      before_clean = before_marker&.strip&.split("\n")&.last(3)&.join("\n") || ""
      after_clean = after_marker&.strip&.split("\n")&.first(3)&.join("\n") || ""

      # Find positions in existing content
      start_pos = before_clean.present? ? existing_content.index(before_clean) : 0
      end_pos = after_clean.present? ? existing_content.index(after_clean) : existing_content.length

      if start_pos && end_pos && end_pos > start_pos
        # Extract the section between the markers
        start_pos += before_clean.length if before_clean.present?
        existing_content[start_pos...end_pos]
      end
    end

    def update_file_tool(path, updates, status_message)
      # Broadcast that we're updating this file
      broadcast_file_progress("📝 Updating #{path}...", status_message)

      file = app.app_files.find_by(path: path)
      unless file
        return {success: false, error: "File not found: #{path}"}
      end

      content = file.content
      updates.each do |update|
        content = content.gsub(update["find"], update["replace"])
      end

      file.content = content
      if file.save
        {success: true, message: "File #{path} updated successfully"}
      else
        {success: false, error: "Failed to update #{path}: #{file.errors.full_messages.join(", ")}"}
      end
    end

    def line_replace_tool(file_path, search, first_line, last_line, replace, status_message)
      # Broadcast that we're doing line replacement
      broadcast_file_progress("🔄 Line replacing in #{file_path} (lines #{first_line}-#{last_line})...", status_message)

      file = app.app_files.find_by(path: file_path)
      unless file
        return {success: false, error: "File not found: #{file_path}"}
      end

      lines = file.content.split("\n")

      # Validate line numbers (convert to 0-indexed)
      first_idx = first_line - 1
      last_idx = last_line - 1

      if first_idx < 0 || last_idx >= lines.length || first_idx > last_idx
        return {success: false, error: "Invalid line range: #{first_line}-#{last_line} for file with #{lines.length} lines"}
      end

      # Extract the target section
      target_lines = lines[first_idx..last_idx]
      target_content = target_lines.join("\n")

      # Handle ellipsis in search pattern
      if search.include?("...")
        # Split search pattern by ellipsis
        search_parts = search.split("...")

        if search_parts.length == 2
          # Validate that the beginning and end match
          start_pattern = search_parts[0].strip
          end_pattern = search_parts[1].strip

          unless target_content.start_with?(start_pattern) && target_content.end_with?(end_pattern)
            return {
              success: false,
              error: "Search pattern with ellipsis doesn't match target content. Expected to start with '#{start_pattern}' and end with '#{end_pattern}'"
            }
          end
        else
          return {success: false, error: "Invalid ellipsis pattern. Use exactly one '...' to separate start and end patterns."}
        end
      else
        # Exact match validation
        unless target_content.include?(search)
          return {
            success: false,
            error: "Search pattern not found in target lines #{first_line}-#{last_line}. Expected: '#{search[0..100]}...'"
          }
        end
      end

      # Replace the target lines
      replacement_lines = replace.split("\n")
      new_lines = lines[0...first_idx] + replacement_lines + lines[(last_idx + 1)..]

      # Update file content
      file.content = new_lines.join("\n")

      # Clear cache since file changed
      @context_cache.clear_app_cache(app.id)

      if file.save
        Rails.logger.info "[AppUpdateOrchestratorV2] Line replace successful: #{file_path} lines #{first_line}-#{last_line}"
        {
          success: true,
          message: "Successfully replaced lines #{first_line}-#{last_line} in #{file_path}",
          lines_changed: replacement_lines.length,
          original_lines: last_line - first_line + 1
        }
      else
        {success: false, error: "Failed to save #{file_path}: #{file.errors.full_messages.join(", ")}"}
      end
    end

    def delete_file_tool(path, status_message)
      # Broadcast that we're deleting this file
      broadcast_file_progress("🗑️ Deleting #{path}...", status_message)

      file = app.app_files.find_by(path: path)
      if file
        file.destroy
        {success: true, message: "File #{path} deleted successfully"}
      else
        {success: false, error: "File not found: #{path}"}
      end
    end

    def broadcast_progress_tool(message, percentage, status_message)
      # Update the status message with progress
      progress_text = percentage ? "#{message} (#{percentage}%)" : message
      status_message.update!(content: progress_text)
      broadcast_message_update(status_message)

      {success: true, message: "Progress broadcasted"}
    end

    def search_files_tool(query, include_pattern, exclude_pattern, case_sensitive, status_message)
      broadcast_file_progress("🔍 Searching for '#{query}' across project files...", status_message)

      search_service = Ai::SmartSearchService.new(app)
      result = search_service.search_files(
        query: query,
        include_pattern: include_pattern,
        exclude_pattern: exclude_pattern,
        case_sensitive: case_sensitive || false
      )

      if result[:success]
        found_count = result[:results].length
        broadcast_file_progress("✅ Found #{found_count} matches for '#{query}'", status_message)

        # Format results for AI consumption
        formatted_results = result[:results].map do |match|
          "#{match[:file_path]}:#{match[:line_number]} - #{match[:line_content]}"
        end.join("\n")

        {success: true, results: formatted_results, count: found_count}
      else
        {success: false, error: result[:error]}
      end
    end

    def rename_file_tool(old_path, new_path, status_message)
      broadcast_file_progress("📝 Renaming #{old_path} to #{new_path}...", status_message)

      file = app.app_files.find_by(path: old_path)
      unless file
        return {success: false, error: "File not found: #{old_path}"}
      end

      # Check if new path already exists
      if app.app_files.find_by(path: new_path)
        return {success: false, error: "File already exists at: #{new_path}"}
      end

      # Update the file path
      file.update!(path: new_path)
      @context_cache.clear_app_cache(app.id)

      broadcast_file_progress("✅ Renamed #{old_path} to #{new_path}", status_message)
      {success: true, message: "File renamed successfully"}
    end

    def read_console_logs_tool(search, limit, status_message)
      broadcast_file_progress("📊 Reading console logs from deployed app...", status_message)

      bridge_service = Deployment::IframeBridgeService.new(app)
      result = bridge_service.read_console_logs(search, limit)

      if result[:success]
        log_count = result[:logs].length
        broadcast_file_progress("✅ Retrieved #{log_count} console log entries", status_message)

        # Format logs for AI analysis
        formatted_logs = result[:logs].map do |log|
          timestamp = Time.parse(log["timestamp"]).strftime("%H:%M:%S")
          "#{timestamp} [#{log["level"]}] #{log["message"]}"
        end.join("\n")

        {success: true, logs: formatted_logs, count: log_count}
      else
        {success: false, error: result[:error]}
      end
    end

    def read_network_requests_tool(search, limit, status_message)
      broadcast_file_progress("🌐 Reading network requests from deployed app...", status_message)

      bridge_service = Deployment::IframeBridgeService.new(app)
      result = bridge_service.read_network_requests(search, limit)

      if result[:success]
        request_count = result[:requests].length
        broadcast_file_progress("✅ Retrieved #{request_count} network requests", status_message)

        # Format requests for AI analysis
        formatted_requests = result[:requests].map do |req|
          timestamp = Time.parse(req["timestamp"]).strftime("%H:%M:%S")
          status_info = req["error"] ? "ERROR: #{req["error"]}" : req["status"].to_s
          "#{timestamp} #{req["method"]} #{req["url"]} - #{status_info}"
        end.join("\n")

        {success: true, requests: formatted_requests, count: request_count}
      else
        {success: false, error: result[:error]}
      end
    end

    def add_dependency_tool(package_name, is_dev, status_message)
      broadcast_file_progress("📦 Adding dependency #{package_name}...", status_message)

      package_manager = Deployment::PackageManagerService.new(app)
      result = package_manager.add_dependency(package_name, nil, is_dev || false)

      if result[:success]
        broadcast_file_progress("✅ Added #{result[:package]}@#{result[:version]} to #{result[:is_dev] ? "devDependencies" : "dependencies"}", status_message)
        {success: true, message: result[:message], package: result[:package], version: result[:version]}
      else
        {success: false, error: result[:error]}
      end
    end

    def remove_dependency_tool(package_name, status_message)
      broadcast_file_progress("📦 Removing dependency #{package_name}...", status_message)

      package_manager = Deployment::PackageManagerService.new(app)
      result = package_manager.remove_dependency(package_name)

      if result[:success]
        broadcast_file_progress("✅ Removed #{result[:package]} from #{result[:removed_from]}", status_message)
        {success: true, message: result[:message], package: result[:package]}
      else
        {success: false, error: result[:error]}
      end
    end

    def web_search_tool(query, num_results, category, status_message)
      broadcast_file_progress("🔎 Searching web for: #{query}...", status_message)

      content_fetcher = External::ContentFetcherService.new(app)
      result = content_fetcher.web_search(query, num_results: num_results || 5, category: category)

      if result[:success]
        broadcast_file_progress("✅ Found #{result[:results].length} results for '#{query}'", status_message)

        # Format results for AI consumption
        formatted_results = result[:results].map do |r|
          "#{r[:title]}\n#{r[:url]}\n#{r[:snippet]}"
        end.join("\n\n")

        {success: true, results: formatted_results, count: result[:results].length}
      else
        {success: false, error: result[:error]}
      end
    end

    def download_to_repo_tool(source_url, target_path, status_message)
      broadcast_file_progress("⬇️ Downloading #{source_url}...", status_message)

      content_fetcher = External::ContentFetcherService.new(app)
      result = content_fetcher.download_to_repo(source_url, target_path)

      if result[:success]
        broadcast_file_progress("✅ Downloaded to #{result[:target_path]} (#{result[:size]} bytes)", status_message)
        {success: true, path: result[:target_path], size: result[:size], message: result[:message]}
      else
        {success: false, error: result[:error]}
      end
    end

    def fetch_website_tool(url, formats, status_message)
      broadcast_file_progress("🌐 Fetching content from #{url}...", status_message)

      content_fetcher = External::ContentFetcherService.new(app)
      result = content_fetcher.fetch_website(url, formats: formats || ["markdown"])

      if result[:success]
        broadcast_file_progress("✅ Fetched website content in #{result[:formats].join(", ")} format(s)", status_message)

        # Return the content paths and previews
        content_summary = result[:results].map do |format, data|
          "#{format}: #{data[:path]} (#{data[:size]} bytes)"
        end.join("\n")

        {success: true, results: result[:results], summary: content_summary}
      else
        {success: false, error: result[:error]}
      end
    end

    def generate_image_tool(prompt, target_path, width, height, style_preset, status_message)
      broadcast_file_progress("🎨 Generating image: #{prompt[0..50]}...", status_message)

      # Initialize the image generation service (defaults to OpenAI)
      image_service = Ai::ImageGenerationService.new(app, provider: :openai)

      # Generate the image
      result = image_service.generate_image(
        prompt: prompt,
        target_path: target_path,
        width: width,
        height: height,
        style_preset: style_preset
      )

      if result[:success]
        broadcast_file_progress("✅ Generated and saved image to #{result[:target_path]}", status_message)

        {
          success: true,
          path: result[:target_path],
          size: result[:size],
          dimensions: result[:dimensions],
          message: result[:message]
        }
      else
        broadcast_file_progress("❌ Image generation failed: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def edit_image_tool(image_paths, prompt, target_path, strength, status_message)
      broadcast_file_progress("✏️ Editing image(s) with AI...", status_message)

      # Initialize the image generation service
      image_service = Ai::ImageGenerationService.new(app, provider: :openai)

      # Edit the image(s)
      result = image_service.edit_image(
        image_paths: image_paths,
        prompt: prompt,
        target_path: target_path,
        strength: strength || 0.75
      )

      if result[:success]
        broadcast_file_progress("✅ Edited and saved image to #{target_path}", status_message)
        {success: true, path: target_path, message: "Successfully edited image"}
      else
        broadcast_file_progress("❌ Image editing failed: #{result[:error]}", status_message)
        {success: false, error: result[:error], suggestion: result[:suggestion]}
      end
    end

    def read_analytics_tool(time_range, metrics, status_message)
      broadcast_file_progress("📊 Reading analytics data...", status_message)

      # Initialize analytics service
      analytics_service = Analytics::AppAnalyticsService.new(app)

      # Get analytics summary
      result = analytics_service.get_analytics_summary(
        time_range: time_range || "7d",
        metrics: metrics
      )

      if result[:success]
        data = result[:data]

        # Get performance insights
        insights_result = analytics_service.get_performance_insights
        insights = insights_result[:insights] if insights_result[:success]

        # Format analytics for AI consumption
        formatted_analytics = format_analytics_for_ai(data, insights)

        broadcast_file_progress("✅ Retrieved analytics for #{data[:time_range]}", status_message)

        {
          success: true,
          analytics: formatted_analytics,
          raw_data: data,
          insights: insights,
          performance_score: insights_result[:performance_score],
          recommendations: insights_result[:recommendations]
        }
      else
        broadcast_file_progress("❌ Failed to retrieve analytics: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def format_analytics_for_ai(data, insights)
      summary = []

      # Overview metrics
      if data[:overview]
        summary << "📈 Overview (#{data[:time_range]}):"
        summary << "• Page Views: #{data[:overview][:total_page_views]}"
        summary << "• Unique Visitors: #{data[:overview][:unique_visitors]}"
        summary << "• Sessions: #{data[:overview][:total_sessions]}"
        summary << "• Avg Session: #{data[:overview][:avg_session_duration]}"
        summary << "• Bounce Rate: #{data[:overview][:bounce_rate]}"
      end

      # Performance metrics
      if data[:performance]
        summary << "\n⚡ Performance:"
        summary << "• Avg Load Time: #{data[:performance][:avg_page_load_time]}ms"
        summary << "• API Response: #{data[:performance][:avg_api_response_time]}ms"
        summary << "• Error Rate: #{data[:performance][:error_rate]}%"
        summary << "• LCP: #{data[:performance][:largest_contentful_paint]}ms"
      end

      # Top pages
      if data[:top_pages]&.any?
        summary << "\n📱 Top Pages:"
        data[:top_pages].first(5).each do |page|
          summary << "• #{page[:url]}: #{page[:views]} views"
        end
      end

      # Errors
      if data[:errors]
        summary << "\n⚠️ Errors:"
        summary << "• Total: #{data[:errors][:total_errors]}"
        summary << "• JS Errors: #{data[:errors][:js_errors]}"
        summary << "• Network: #{data[:errors][:network_errors]}"
      end

      # Insights
      if insights&.any?
        summary << "\n💡 Key Insights:"
        insights.each do |insight|
          summary << "• [#{insight[:type].upcase}] #{insight[:metric]}: #{insight[:value]} (threshold: #{insight[:threshold]})"
        end
      end

      summary.join("\n")
    end

    def git_status_tool(status_message)
      broadcast_file_progress("📋 Checking Git status...", status_message)

      git_service = VersionControl::GitService.new(app)
      result = git_service.status

      if result[:success]
        status_info = result[:status]

        # Format status for AI
        status_text = []
        status_text << "Branch: #{status_info[:current_branch]}"
        status_text << "Status: #{status_info[:clean] ? "Clean" : "Changes detected"}"

        if status_info[:changed_files].any?
          status_text << "\nModified files:"
          status_info[:changed_files].each do |file|
            status_text << "  M #{file[:path]}"
          end
        end

        if status_info[:untracked_files].any?
          status_text << "\nUntracked files:"
          status_info[:untracked_files].each do |file|
            status_text << "  ? #{file}"
          end
        end

        if status_info[:staged_files].any?
          status_text << "\nStaged files:"
          status_info[:staged_files].each do |file|
            status_text << "  A #{file}"
          end
        end

        broadcast_file_progress("✅ Git status retrieved", status_message)

        {
          success: true,
          status: status_text.join("\n"),
          raw_status: status_info,
          clean: status_info[:clean]
        }
      else
        broadcast_file_progress("❌ Git status failed: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def git_commit_tool(message, status_message)
      broadcast_file_progress("💾 Creating Git commit...", status_message)

      git_service = VersionControl::GitService.new(app)
      result = git_service.commit(message)

      if result[:success]
        broadcast_file_progress("✅ Committed: #{result[:commit_sha][0..7]} - #{message}", status_message)

        {
          success: true,
          commit_sha: result[:commit_sha],
          message: result[:message],
          files_changed: result[:files_changed],
          stats: result[:stats]
        }
      else
        broadcast_file_progress("❌ Commit failed: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def git_branch_tool(branch_name, checkout, status_message)
      git_service = VersionControl::GitService.new(app)

      if branch_name
        broadcast_file_progress("🌿 Creating branch '#{branch_name}'...", status_message)
        result = git_service.create_branch(branch_name, checkout != false)

        if result[:success]
          broadcast_file_progress("✅ Created branch '#{branch_name}'", status_message)
        else
          broadcast_file_progress("❌ Branch creation failed: #{result[:error]}", status_message)
        end

        result
      else
        broadcast_file_progress("📋 Listing branches...", status_message)
        result = git_service.branches

        if result[:success]
          branches_text = result[:branches].map do |branch|
            prefix = branch[:current] ? "* " : "  "
            "#{prefix}#{branch[:name]}"
          end.join("\n")

          broadcast_file_progress("✅ Found #{result[:total]} branches", status_message)

          {
            success: true,
            branches: branches_text,
            current_branch: result[:current_branch],
            raw_branches: result[:branches]
          }
        else
          broadcast_file_progress("❌ Failed to list branches: #{result[:error]}", status_message)
          result
        end
      end
    end

    def git_diff_tool(file_path, from_commit, to_commit, status_message)
      broadcast_file_progress("🔍 Getting Git diff...", status_message)

      git_service = VersionControl::GitService.new(app)
      result = git_service.diff(file_path, from_commit, to_commit)

      if result[:success]
        diff_summary = "Files changed: #{result[:total_files]}\n"
        diff_summary += "+#{result[:total_insertions]} insertions, -#{result[:total_deletions]} deletions\n\n"

        result[:changes].each do |change|
          diff_summary += "#{change[:path]}:\n"
          diff_summary += change[:patch][0..500] # Limit patch size
          diff_summary += "\n...\n" if change[:patch].length > 500
          diff_summary += "\n"
        end

        broadcast_file_progress("✅ Diff generated", status_message)

        {
          success: true,
          diff: diff_summary,
          raw_changes: result[:changes],
          stats: {
            files: result[:total_files],
            insertions: result[:total_insertions],
            deletions: result[:total_deletions]
          }
        }
      else
        broadcast_file_progress("❌ Diff failed: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def git_log_tool(limit, status_message)
      broadcast_file_progress("📜 Getting Git history...", status_message)

      git_service = VersionControl::GitService.new(app)
      result = git_service.log(limit || 10)

      if result[:success]
        log_text = []
        result[:commits].each do |commit|
          log_text << "commit #{commit[:sha][0..7]}"
          log_text << "Author: #{commit[:author]}"
          log_text << "Date: #{commit[:date]}"
          log_text << "    #{commit[:message]}"
          log_text << ""
        end

        broadcast_file_progress("✅ Retrieved #{result[:total]} commits", status_message)

        {
          success: true,
          log: log_text.join("\n"),
          commits: result[:commits],
          total: result[:total]
        }
      else
        broadcast_file_progress("❌ Log failed: #{result[:error]}", status_message)
        {success: false, error: result[:error]}
      end
    end

    def broadcast_file_progress(message, status_message)
      status_message.update!(content: message)
      broadcast_message_update(status_message)
      sleep(0.1) # Small delay to ensure message is seen
    end

    def finalize_update(result)
      Rails.logger.info "[AppUpdateOrchestratorV2] Step 4: Finalizing update"

      # Create completion message
      files_list = result[:files_modified].map { |f| "• #{f}" }.join("\n")

      completion_message = create_assistant_message(
        "✅ **Update Complete!**\n\nI've successfully implemented your requested changes.\n\n**Files Modified:**\n#{files_list}\n\n**What's New:**\n• Your changes have been applied\n• The preview has been updated\n• All files are saved and ready\n\nYou can now:\n• Check the preview to see your changes\n• Continue making improvements\n• Deploy when you're satisfied",
        "completed"
      )

      broadcast_message_update(completion_message)

      # Ensure preview is updated
      UpdatePreviewJob.perform_later(app.id)
    end

    def build_execution_tools
      [
        {
          type: "function",
          function: {
            name: "read_file",
            description: "Read the complete content of a file",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "File path to read (e.g., 'index.html', 'app.js')"}
              },
              required: ["path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "write_file",
            description: "Write or create a file with new content. Use this for new files or complete rewrites.",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "File path to write (e.g., 'index.html', 'app.js')"},
                content: {type: "string", description: "Complete file content to write"},
                file_type: {type: "string", enum: ["html", "css", "js", "json"], description: "Type of file"}
              },
              required: ["path", "content", "file_type"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "update_file",
            description: "Update specific parts of an existing file using find and replace",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "File path to update"},
                updates: {
                  type: "array",
                  description: "Array of find/replace operations",
                  items: {
                    type: "object",
                    properties: {
                      find: {type: "string", description: "Exact text to find in the file"},
                      replace: {type: "string", description: "Text to replace it with"}
                    },
                    required: ["find", "replace"]
                  }
                }
              },
              required: ["path", "updates"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "delete_file",
            description: "Delete a file from the project",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "File path to delete"}
              },
              required: ["path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "line_replace",
            description: "Line-based search and replace for minimal file changes. Use this for small, precise edits instead of rewriting entire files.",
            parameters: {
              type: "object",
              properties: {
                file_path: {type: "string", description: "File path to modify (e.g., 'src/App.js')"},
                search: {type: "string", description: "Content to find (use ... for large sections). Example: 'const oldCode = ...' to match large blocks"},
                first_line: {type: "integer", description: "First line number to replace (1-indexed)"},
                last_line: {type: "integer", description: "Last line number to replace (1-indexed)"},
                replace: {type: "string", description: "New content to replace the matched lines"}
              },
              required: ["file_path", "search", "first_line", "last_line", "replace"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "search_files",
            description: "Search across files using regex patterns with filtering. Find existing components, functions, or code patterns.",
            parameters: {
              type: "object",
              properties: {
                query: {type: "string", description: "Regex pattern to search for (e.g., 'useState', 'function.*Component')"},
                include_pattern: {type: "string", description: "Files to include using glob syntax (e.g., 'src/**/*.{js,jsx,ts,tsx}')"},
                exclude_pattern: {type: "string", description: "Files to exclude using glob syntax (e.g., '**/*.test.*')"},
                case_sensitive: {type: "boolean", description: "Whether to match case (default: false)"}
              },
              required: ["query"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "rename_file",
            description: "Rename a file in the project. Use this instead of creating new files and deleting old ones.",
            parameters: {
              type: "object",
              properties: {
                old_path: {type: "string", description: "Current file path"},
                new_path: {type: "string", description: "New file path"}
              },
              required: ["old_path", "new_path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "read_console_logs",
            description: "Read console logs from the deployed app for debugging. Similar to browser dev tools.",
            parameters: {
              type: "object",
              properties: {
                search: {type: "string", description: "Filter logs by search term (optional)"},
                limit: {type: "integer", description: "Number of logs to retrieve (default: 100)"}
              }
            }
          }
        },
        {
          type: "function",
          function: {
            name: "read_network_requests",
            description: "Read network requests from the deployed app for debugging API issues.",
            parameters: {
              type: "object",
              properties: {
                search: {type: "string", description: "Filter requests by search term (optional)"},
                limit: {type: "integer", description: "Number of requests to retrieve (default: 50)"}
              }
            }
          }
        },
        {
          type: "function",
          function: {
            name: "add_dependency",
            description: "Add an npm package dependency to the project. Use this when you need external libraries.",
            parameters: {
              type: "object",
              properties: {
                package: {type: "string", description: "Package name (e.g., 'lodash' or 'lodash@4.17.21')"},
                is_dev: {type: "boolean", description: "Whether this is a dev dependency (default: false)"}
              },
              required: ["package"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "remove_dependency",
            description: "Remove an npm package from the project dependencies.",
            parameters: {
              type: "object",
              properties: {
                package: {type: "string", description: "Package name to remove"}
              },
              required: ["package"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "web_search",
            description: "Search the web for current information, documentation, or resources. Use when you need information beyond your training data.",
            parameters: {
              type: "object",
              properties: {
                query: {type: "string", description: "The search query"},
                num_results: {type: "integer", description: "Number of results to return (default: 5)"},
                category: {type: "string", description: "Category filter: 'news', 'github', 'docs', 'tutorial'"}
              },
              required: ["query"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "download_to_repo",
            description: "Download a file from a URL and save it to the project. Use for images, assets, or external resources.",
            parameters: {
              type: "object",
              properties: {
                source_url: {type: "string", description: "URL of the file to download"},
                target_path: {type: "string", description: "Where to save the file (e.g., 'src/assets/logo.png')"}
              },
              required: ["source_url", "target_path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "fetch_website",
            description: "Fetch website content as markdown or HTML for reference or integration.",
            parameters: {
              type: "object",
              properties: {
                url: {type: "string", description: "URL to fetch content from"},
                formats: {
                  type: "array",
                  items: {type: "string", enum: ["markdown", "html"]},
                  description: "Formats to return (default: ['markdown'])"
                }
              },
              required: ["url"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "broadcast_progress",
            description: "Send a progress update message to the user to keep them informed",
            parameters: {
              type: "object",
              properties: {
                message: {type: "string", description: "Progress message to display to the user"},
                percentage: {type: "integer", minimum: 0, maximum: 100, description: "Optional progress percentage"}
              },
              required: ["message"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "generate_image",
            description: "Generate an AI-powered image for the app. Creates logos, heroes, backgrounds, icons, and other visual assets.",
            parameters: {
              type: "object",
              properties: {
                prompt: {type: "string", description: "Description of the image to generate (e.g., 'modern dashboard icon with blue gradient')"},
                target_path: {type: "string", description: "Where to save the image (e.g., 'src/assets/logo.png', 'src/assets/hero.jpg')"},
                width: {type: "integer", description: "Image width in pixels (optional, defaults based on target path)"},
                height: {type: "integer", description: "Image height in pixels (optional, defaults based on target path)"},
                style_preset: {
                  type: "string",
                  enum: ["modern", "vintage", "futuristic", "realistic", "artistic", "corporate", "playful"],
                  description: "Style preset for the image (optional)"
                }
              },
              required: ["prompt", "target_path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "edit_image",
            description: "Edit existing images with AI. Transform, modify, or enhance images in the project.",
            parameters: {
              type: "object",
              properties: {
                image_paths: {
                  type: "array",
                  items: {type: "string"},
                  description: "Paths to existing images to edit"
                },
                prompt: {type: "string", description: "Description of how to edit the image(s)"},
                target_path: {type: "string", description: "Where to save the edited image"},
                strength: {
                  type: "number",
                  minimum: 0,
                  maximum: 1,
                  description: "Edit strength (0=minimal, 1=maximum, default: 0.75)"
                }
              },
              required: ["image_paths", "prompt", "target_path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "read_analytics",
            description: "Read analytics and performance data for the deployed app. Get insights about usage, errors, and performance.",
            parameters: {
              type: "object",
              properties: {
                time_range: {
                  type: "string",
                  description: "Time range for analytics: '1h', '24h', '7d', '30d' (default: '7d')"
                },
                metrics: {
                  type: "array",
                  items: {
                    type: "string",
                    enum: ["overview", "events", "performance", "user_activity", "errors", "top_pages", "conversions"]
                  },
                  description: "Specific metrics to retrieve (optional, returns all if not specified)"
                }
              }
            }
          }
        },
        {
          type: "function",
          function: {
            name: "git_status",
            description: "Get the current Git status of the project. Shows changed files, untracked files, and current branch.",
            parameters: {
              type: "object",
              properties: {}
            }
          }
        },
        {
          type: "function",
          function: {
            name: "git_commit",
            description: "Create a Git commit with all current changes. Automatically stages all files before committing.",
            parameters: {
              type: "object",
              properties: {
                message: {type: "string", description: "Commit message describing the changes"}
              },
              required: ["message"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "git_branch",
            description: "Create a new Git branch or list existing branches.",
            parameters: {
              type: "object",
              properties: {
                branch_name: {type: "string", description: "Name of the branch to create (optional, lists branches if not provided)"},
                checkout: {type: "boolean", description: "Whether to checkout the new branch immediately (default: true)"}
              }
            }
          }
        },
        {
          type: "function",
          function: {
            name: "git_diff",
            description: "Show differences between commits or working directory. Useful for reviewing changes.",
            parameters: {
              type: "object",
              properties: {
                file_path: {type: "string", description: "Specific file to diff (optional, shows all if not specified)"},
                from_commit: {type: "string", description: "Starting commit SHA (optional)"},
                to_commit: {type: "string", description: "Ending commit SHA (optional, defaults to HEAD)"}
              }
            }
          }
        },
        {
          type: "function",
          function: {
            name: "git_log",
            description: "View Git commit history. Shows recent commits with their messages, authors, and changed files.",
            parameters: {
              type: "object",
              properties: {
                limit: {type: "integer", description: "Number of commits to show (default: 10)"}
              }
            }
          }
        }
      ]
    end

    def create_assistant_message(content, status)
      app.app_chat_messages.create!(
        role: "assistant",
        content: content,
        status: status
      )
    end

    def broadcast_message_update(message)
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        partial: "account/app_editors/chat_message",
        locals: {message: message}
      )
    end

    def create_error_response(error_message)
      error_response = create_assistant_message(
        "❌ An error occurred: #{error_message}\n\nPlease try again or contact support if the issue persists.",
        "failed"
      )

      broadcast_message_update(error_response)

      # Re-enable the chat form by broadcasting a custom event
      # This ensures the form is re-enabled even if the partial replacement fails
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: "<script>document.dispatchEvent(new CustomEvent('chat:error', { detail: { message: '#{error_message.gsub("'", "\\'")}' } }))</script>"
      )

      # Also try to replace the form wrapper
      begin
        Turbo::StreamsChannel.broadcast_replace_to(
          "app_#{app.id}_chat",
          target: "chat_form",
          partial: "account/app_editors/chat_input_wrapper",
          locals: {app: app}
        )
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV2] Failed to replace chat form: #{e.message}"
      end
    end

    def parse_json_response(content)
      # Extract JSON from the response
      json_match = content.match(/\{.*\}/m)
      return {} unless json_match

      begin
        JSON.parse(json_match[0])
      rescue JSON::ParserError => e
        Rails.logger.error "[AppUpdateOrchestratorV2] Failed to parse JSON: #{e.message}"
        {}
      end
    end

    def format_analysis_message(analysis)
      <<~MESSAGE
        ✅ **Analysis Complete**
        
        **Architecture:** #{analysis["architecture"] || "Unknown architecture"}
        
        **Changes Needed:**
        #{(analysis["changes_needed"] || []).map { |c| "• #{c}" }.join("\n")}
        
        **Files to Modify:** #{(analysis["files_to_modify"] || []).join(", ")}
        #{(analysis["files_to_create"] || []).any? ? "**Files to Create:** #{analysis["files_to_create"].join(", ")}" : ""}
        
        **Approach:** #{analysis["approach"] || "Approach to be determined"}
      MESSAGE
    end

    def format_plan_message(plan)
      <<~MESSAGE
        📋 **Execution Plan Ready**
        
        #{plan["summary"]}
        
        **Estimated Operations:** #{plan["estimated_operations"]}
        
        I'll now execute this plan step by step, keeping you updated on progress...
      MESSAGE
    end

    def detect_file_type(path)
      case File.extname(path).downcase
      when ".html", ".htm"
        "html"
      when ".css"
        "css"
      when ".js", ".mjs"
        "js"
      when ".json"
        "json"
      else
        "text"
      end
    end

    # Get files with caching optimization
    def get_cached_or_load_files
      cached_files = @context_cache.get_cached_file_contents(app.id, app.app_files)

      if cached_files
        Rails.logger.info "[AppUpdateOrchestratorV2] Using cached file contents"
        return cached_files.map do |file|
          {
            path: file[:path],
            content: file[:content][0..500], # Only send first 500 chars for analysis
            type: file[:file_type],
            size: file[:size]
          }
        end
      end

      # Load fresh files and cache them
      Rails.logger.info "[AppUpdateOrchestratorV2] Loading fresh file contents"
      current_files = app.app_files.map do |file|
        {
          path: file.path,
          content: file.content || "", # Handle nil content
          file_type: file.file_type,
          size: (file.content || "").length,
          updated_at: file.updated_at
        }
      end

      # Cache for future use if we have files
      @context_cache.cache_file_contents(app.id, current_files) if current_files.any?

      # Return analysis version (truncated content)
      current_files.map do |file|
        {
          path: file[:path],
          content: file[:content][0..500], # Only send first 500 chars for analysis
          type: file[:file_type],
          size: file[:size]
        }
      end
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV2] Error loading files: #{e.message}"
      []
    end

    # Get environment variables with caching
    def get_cached_or_load_env_vars
      cached_env_vars = @context_cache.get_cached_env_vars(app.id)

      if cached_env_vars
        Rails.logger.info "[AppUpdateOrchestratorV2] Using cached environment variables"
        return cached_env_vars
      end

      # Load fresh env vars and cache them
      Rails.logger.info "[AppUpdateOrchestratorV2] Loading fresh environment variables"
      env_vars = app.env_vars_for_ai || []
      @context_cache.cache_env_vars(app.id, env_vars) if env_vars.any?

      env_vars
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV2] Error loading env vars: #{e.message}"
      []
    end
  end
end
