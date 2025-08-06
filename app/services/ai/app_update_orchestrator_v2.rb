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
      
      # Get current app files
      current_files = app.app_files.map do |file|
        { 
          path: file.path, 
          content: file.content[0..500], # Only send first 500 chars for analysis
          type: file.file_type,
          size: file.content.length
        }
      end
      
      # Load AI standards
      ai_standards = File.read(Rails.root.join('AI_APP_STANDARDS.md'))
      
      # Get available environment variables
      env_vars = app.env_vars_for_ai
      
      # Build analysis prompt
      analysis_prompt = <<~PROMPT
        You are analyzing a web application to understand its structure and plan updates.
        
        Current Request: #{chat_message.content}
        
        App Name: #{app.name}
        App Type: #{app.app_type}
        Framework: #{app.framework}
        
        Current Files:
        #{current_files.map { |f| "- #{f[:path]} (#{f[:type]}, #{f[:size]} bytes)" }.join("\n")}
        
        Available Environment Variables:
        #{env_vars.map { |v| "- #{v[:key]}: #{v[:description]}" }.join("\n")}
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
        
        { success: true, analysis: analysis }
      else
        analysis_message.update!(
          content: "❌ Failed to analyze app structure. Please try again.",
          status: "failed"
        )
        broadcast_message_update(analysis_message)
        
        { error: true, message: response[:error] }
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
      tools = [
        {
          type: "function",
          function: {
            name: "read_file",
            description: "Read the complete content of a file",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path to read" }
              },
              required: ["path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "write_file",
            description: "Write or create a file with new content",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path to write" },
                content: { type: "string", description: "Complete file content" },
                file_type: { type: "string", enum: ["html", "css", "js", "json"], description: "File type" }
              },
              required: ["path", "content", "file_type"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "update_file",
            description: "Update specific parts of an existing file",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path to update" },
                updates: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      find: { type: "string", description: "Text to find" },
                      replace: { type: "string", description: "Text to replace with" }
                    }
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
            description: "Delete a file",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path to delete" }
              },
              required: ["path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "broadcast_progress",
            description: "Send a progress update to the user",
            parameters: {
              type: "object",
              properties: {
                message: { type: "string", description: "Progress message to show user" },
                percentage: { type: "integer", description: "Progress percentage (0-100)" }
              },
              required: ["message"]
            }
          }
        }
      ]
      
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
        
        { success: true, plan: plan }
      else
        planning_message.update!(
          content: "❌ Failed to create execution plan.",
          status: "failed"
        )
        broadcast_message_update(planning_message)
        
        { error: true, message: response[:error] }
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
      ai_standards = File.read(Rails.root.join('AI_APP_STANDARDS.md'))
      
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
        #{plan['summary']}
        
        Current File Contents:
        #{file_contents.map { |path, content| "=== #{path} ===\n#{content[0..1000]}...\n" }.join("\n")}
        
        AI STANDARDS (MUST FOLLOW):
        #{ai_standards}
        
        CRITICAL REQUIREMENTS:
        1. Use function calling to execute the plan step by step
        2. Send progress updates frequently using broadcast_progress
        3. Read files before modifying them
        4. Create complete, professional implementations
        5. Include realistic sample data (5-10 items minimum)
        6. Use Tailwind CSS classes for all styling
        7. Implement proper error handling and loading states
        8. Ensure mobile responsiveness
        9. Follow modern JavaScript patterns (ES6+)
        10. Make the app fully functional, not a prototype
        
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
        
        { success: true, result: result }
      else
        execution_message.update!(
          content: "❌ Failed to complete implementation: #{result[:error]}",
          status: "failed"
        )
        broadcast_message_update(execution_message)
        
        { error: true, message: result[:error] }
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
        
        # Call AI with tools
        response = @client.chat_with_tools(
          conversation_messages,
          tools,
          temperature: 0.3,
          max_tokens: 8000
        )
        
        unless response[:success]
          Rails.logger.error "[AppUpdateOrchestratorV2] Tool calling failed: #{response[:error]}"
          return { success: false, error: response[:error] }
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
          
          # Only add result if we have a valid tool_call_id
          if tool_call && tool_call[:id]
            tool_results << {
              tool_call_id: tool_call[:id],
              role: "tool",
              content: result.to_json
            }
          end
          
          # Track modified files (with safe navigation)
          if tool_call && tool_call[:function] && 
             tool_call[:function][:name] == "write_file" && 
             tool_call[:function][:arguments] && 
             result[:success]
            files_modified << tool_call[:function][:arguments]["path"]
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
      
      { success: true, files_modified: files_modified }
    end
    
    def execute_single_tool(tool_call, status_message)
      # Add nil checking for tool_call structure
      unless tool_call && tool_call[:function]
        Rails.logger.error "[AppUpdateOrchestratorV2] Invalid tool_call structure: #{tool_call.inspect}"
        return { success: false, error: "Invalid tool call structure" }
      end
      
      function_name = tool_call[:function][:name]
      arguments = tool_call[:function][:arguments] || {}
      
      Rails.logger.info "[AppUpdateOrchestratorV2] Executing tool: #{function_name} with args: #{arguments.inspect}"
      
      case function_name
      when "read_file"
        read_file_tool(arguments["path"])
      when "write_file"
        write_file_tool(arguments["path"], arguments["content"], arguments["file_type"], status_message)
      when "update_file"
        update_file_tool(arguments["path"], arguments["updates"], status_message)
      when "delete_file"
        delete_file_tool(arguments["path"], status_message)
      when "broadcast_progress"
        broadcast_progress_tool(arguments["message"], arguments["percentage"], status_message)
      else
        { success: false, error: "Unknown tool: #{function_name}" }
      end
    end
    
    def read_file_tool(path)
      file = app.app_files.find_by(path: path)
      if file
        { success: true, content: file.content }
      else
        { success: false, error: "File not found: #{path}" }
      end
    end
    
    def write_file_tool(path, content, file_type, status_message)
      # Broadcast that we're working on this file
      broadcast_file_progress("✏️ Writing #{path}...", status_message)
      
      file = app.app_files.find_or_initialize_by(path: path)
      file.content = content
      file.file_type = file_type || detect_file_type(path)
      
      if file.save
        { success: true, message: "File #{path} saved successfully" }
      else
        { success: false, error: "Failed to save #{path}: #{file.errors.full_messages.join(', ')}" }
      end
    end
    
    def update_file_tool(path, updates, status_message)
      # Broadcast that we're updating this file
      broadcast_file_progress("📝 Updating #{path}...", status_message)
      
      file = app.app_files.find_by(path: path)
      unless file
        return { success: false, error: "File not found: #{path}" }
      end
      
      content = file.content
      updates.each do |update|
        content = content.gsub(update["find"], update["replace"])
      end
      
      file.content = content
      if file.save
        { success: true, message: "File #{path} updated successfully" }
      else
        { success: false, error: "Failed to update #{path}: #{file.errors.full_messages.join(', ')}" }
      end
    end
    
    def delete_file_tool(path, status_message)
      # Broadcast that we're deleting this file
      broadcast_file_progress("🗑️ Deleting #{path}...", status_message)
      
      file = app.app_files.find_by(path: path)
      if file
        file.destroy
        { success: true, message: "File #{path} deleted successfully" }
      else
        { success: false, error: "File not found: #{path}" }
      end
    end
    
    def broadcast_progress_tool(message, percentage, status_message)
      # Update the status message with progress
      progress_text = percentage ? "#{message} (#{percentage}%)" : message
      status_message.update!(content: progress_text)
      broadcast_message_update(status_message)
      
      { success: true, message: "Progress broadcasted" }
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
                path: { type: "string", description: "File path to read (e.g., 'index.html', 'app.js')" }
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
                path: { type: "string", description: "File path to write (e.g., 'index.html', 'app.js')" },
                content: { type: "string", description: "Complete file content to write" },
                file_type: { type: "string", enum: ["html", "css", "js", "json"], description: "Type of file" }
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
                path: { type: "string", description: "File path to update" },
                updates: {
                  type: "array",
                  description: "Array of find/replace operations",
                  items: {
                    type: "object",
                    properties: {
                      find: { type: "string", description: "Exact text to find in the file" },
                      replace: { type: "string", description: "Text to replace it with" }
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
                path: { type: "string", description: "File path to delete" }
              },
              required: ["path"]
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
                message: { type: "string", description: "Progress message to display to the user" },
                percentage: { type: "integer", minimum: 0, maximum: 100, description: "Optional progress percentage" }
              },
              required: ["message"]
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
        locals: { message: message }
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
          locals: { app: app }
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
        
        **Architecture:** #{analysis['architecture']}
        
        **Changes Needed:**
        #{analysis['changes_needed'].map { |c| "• #{c}" }.join("\n")}
        
        **Files to Modify:** #{analysis['files_to_modify'].join(', ')}
        #{analysis['files_to_create'].any? ? "**Files to Create:** #{analysis['files_to_create'].join(', ')}" : ''}
        
        **Approach:** #{analysis['approach']}
      MESSAGE
    end
    
    def format_plan_message(plan)
      <<~MESSAGE
        📋 **Execution Plan Ready**
        
        #{plan['summary']}
        
        **Estimated Operations:** #{plan['estimated_operations']}
        
        I'll now execute this plan step by step, keeping you updated on progress...
      MESSAGE
    end
    
    def detect_file_type(path)
      case File.extname(path).downcase
      when '.html', '.htm'
        'html'
      when '.css'
        'css'
      when '.js', '.mjs'
        'js'
      when '.json'
        'json'
      else
        'text'
      end
    end
  end
end