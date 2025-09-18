module Ai
  # V3 variant using Claude Sonnet to bypass OpenRouter GPT-5 streaming issues
  class AppUpdateOrchestratorV3Claude < AppUpdateOrchestratorV3
    private

    def process_tool_call(tool_call)
      # Handle both symbol and string keys
      function_data = tool_call[:function] || tool_call["function"]
      return {success: false, error: "No function data in tool call"} unless function_data

      function_name = function_data[:name] || function_data["name"]
      arguments_str = function_data[:arguments] || function_data["arguments"]

      # Parse arguments if they're a JSON string
      arguments = if arguments_str.is_a?(String)
        begin
          JSON.parse(arguments_str)
        rescue
          {}
        end
      else
        arguments_str || {}
      end

      Rails.logger.info "[V3Claude] Processing tool: #{function_name} with args: #{arguments.inspect}"

      case function_name
      when "read_file"
        file = @app.app_files.find_by(path: arguments["path"])
        if file
          {success: true, content: file.content, file_path: arguments["path"]}
        else
          {success: false, error: "File not found: #{arguments["path"]}"}
        end

      when "write_file"
        file = @app.app_files.find_or_initialize_by(path: arguments["path"])
        file.team = @app.team  # Set the team association
        file.content = arguments["content"]
        file.size_bytes = arguments["content"].bytesize
        file.checksum = Digest::SHA256.hexdigest(arguments["content"])
        file.file_type = determine_file_type(arguments["path"])
        file.is_entry_point = (arguments["path"] == "src/index.jsx" || arguments["path"] == "src/main.jsx")

        if file.save
          broadcast_file_update(file, file.new_record? ? "created" : "updated")
          {success: true, message: "File written successfully", file_path: arguments["path"]}
        else
          {success: false, error: "Failed to save file: #{file.errors.full_messages.join(", ")}"}
        end

      when "update_file"
        file = @app.app_files.find_by(path: arguments["path"])
        if file
          updated_content = file.content.gsub(arguments["find"], arguments["replace"])
          file.content = updated_content
          file.size_bytes = updated_content.bytesize
          file.checksum = Digest::SHA256.hexdigest(updated_content)

          if file.save
            broadcast_file_update(file, "updated")
            {success: true, message: "File updated successfully", file_path: arguments["path"]}
          else
            {success: false, error: "Failed to update file: #{file.errors.full_messages.join(", ")}"}
          end
        else
          {success: false, error: "File not found: #{arguments["path"]}"}
        end

      when "delete_file"
        file = @app.app_files.find_by(path: arguments["path"])
        if file
          file.destroy
          broadcast_file_update(file, "deleted")
          {success: true, message: "File deleted successfully", file_path: arguments["path"]}
        else
          {success: false, error: "File not found: #{arguments["path"]}"}
        end

      when "broadcast_progress"
        # Just log for now
        Rails.logger.info "[V3Claude] Progress: #{arguments["message"]} (#{arguments["percentage"]}%)"
        {success: true, message: "Progress broadcast"}

      else
        {success: false, error: "Unknown tool: #{function_name}"}
      end
    end

    def determine_file_type(path)
      case File.extname(path).downcase
      when ".jsx", ".js" then "jsx"
      when ".css" then "css"
      when ".html" then "html"
      when ".json" then "json"
      when ".md" then "md"
      when ".yaml", ".yml" then "yaml"
      else "text"
      end
    end

    def broadcast_file_update(file, action)
      # Broadcast through ActionCable if needed
      Rails.logger.info "[V3Claude] File #{action}: #{file.path}"
    end

    def analyze_app_structure_gpt5
      Rails.logger.info "[AppUpdateOrchestratorV3Claude] Claude Analysis Phase"

      # Create progress message
      analysis_message = create_assistant_message(
        "🔍 Analyzing your app structure and understanding the request...",
        "executing"
      )

      # Get current app state
      current_files = get_cached_or_load_files || []
      get_cached_or_load_env_vars || []

      # Use simplified standards for efficiency
      analysis_prompt = <<~PROMPT
        You are an expert React developer. Analyze this app for the user request: "#{chat_message.content}"
        
        Current Files:
        #{current_files.map { |f| "#{f[:path]}: #{f[:content][0..100]}..." }.join("\n")}
        
        App Context: #{app.framework} #{app.app_type} app named "#{app.name}"
        
        Standards: Use React, Tailwind CSS, modern JavaScript. Create professional, working apps.
        
        Respond with JSON only:
        {
          "current_structure": "Brief description",
          "required_changes": ["List 3-5 key changes needed"],
          "complexity_level": "simple|moderate|complex",
          "estimated_files": 3,
          "technology_stack": ["react", "tailwind"]
        }
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert web developer analyzing app structure. Follow AI_APP_STANDARDS strictly. Always respond with valid JSON."
        },
        {
          role: "user",
          content: analysis_prompt
        }
      ]

      # Use Claude Sonnet instead of GPT-5
      response = @client.chat(messages, model: :claude_sonnet_4, temperature: 0.7)

      if response[:success]
        analysis = parse_json_response(response[:content])

        analysis_message.update!(
          content: "✅ Analysis complete: #{analysis&.dig("complexity_level") || "unknown"} complexity, #{analysis&.dig("estimated_files") || 0} files needed",
          status: "completed"
        )
        broadcast_message_update(analysis_message)

        {success: true, analysis: analysis}
      else
        error_msg = "Analysis failed: #{response[:error]}"
        analysis_message.update!(content: "❌ #{error_msg}", status: "failed")
        broadcast_message_update(analysis_message)
        {success: false, message: error_msg}
      end
    end

    def create_execution_plan_gpt5(analysis)
      Rails.logger.info "[AppUpdateOrchestratorV3Claude] Claude Planning Phase"

      planning_message = create_assistant_message(
        "📝 Creating execution plan...",
        "executing"
      )

      # Get existing files for planning context
      existing_file_paths = @app.app_files.pluck(:path)

      # Simplified planning for efficiency
      planning_prompt = <<~PROMPT
        Based on analysis: #{analysis.to_json}
        User request: "#{chat_message.content}"
        
        Existing files in app: #{existing_file_paths.join(", ")}
        
        Create a simple execution plan. IMPORTANT: If files already exist, they should go in files_to_update, not files_to_create.
        
        {
          "summary": "Brief plan summary",
          "files_to_create": [
            {"path": "path/to/new/file.jsx", "description": "Description of new file"}
          ],
          "files_to_update": [
            {"path": "path/to/existing/file.jsx", "description": "What changes to make"}
          ],
          "files_to_delete": [],
          "total_operations": 3
        }
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert developer creating an execution plan. Respond with valid JSON only."
        },
        {
          role: "user",
          content: planning_prompt
        }
      ]

      # Use Claude Sonnet
      response = @client.chat(messages, model: :claude_sonnet_4, temperature: 0.7)

      if response[:success]
        plan = parse_json_response(response[:content])

        Rails.logger.info "[V3Claude] Plan created: #{plan.inspect}"

        # Calculate actual operations from the plan
        total_ops = (plan&.dig("files_to_create")&.length || 0) +
          (plan&.dig("files_to_update")&.length || 0) +
          (plan&.dig("files_to_delete")&.length || 0)

        # Update total_operations if not set correctly
        plan["total_operations"] = total_ops if plan && total_ops > 0

        planning_message.update!(
          content: "✅ Plan ready: #{total_ops} operations",
          status: "completed"
        )
        broadcast_message_update(planning_message)

        {success: true, plan: plan}
      else
        error_msg = "Planning failed: #{response[:error]}"
        planning_message.update!(content: "❌ #{error_msg}", status: "failed")
        broadcast_message_update(planning_message)
        {success: false, message: error_msg}
      end
    end

    def execute_with_gpt5_tools(plan)
      Rails.logger.info "[AppUpdateOrchestratorV3Claude] Claude Tool Execution Phase"

      execution_message = create_assistant_message(
        "🔧 Executing plan with #{plan&.dig("total_operations") || 0} operations...",
        "executing"
      )

      # Define available tools (same as V3)
      tools = [
        {
          type: "function",
          function: {
            name: "read_file",
            description: "Read the complete content of a file",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "Path to the file to read"}
              },
              required: ["path"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "write_file",
            description: "Write content to a file (creates or overwrites)",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "Path to the file"},
                content: {type: "string", description: "Content to write"}
              },
              required: ["path", "content"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "update_file",
            description: "Update a file by finding and replacing content",
            parameters: {
              type: "object",
              properties: {
                path: {type: "string", description: "Path to the file"},
                find: {type: "string", description: "Text to find"},
                replace: {type: "string", description: "Text to replace with"}
              },
              required: ["path", "find", "replace"]
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
                path: {type: "string", description: "Path to the file to delete"}
              },
              required: ["path"]
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
                message: {type: "string", description: "Progress message"},
                percentage: {type: "integer", description: "Progress percentage (0-100)"}
              },
              required: ["message"]
            }
          }
        }
      ]

      # Load existing file contents for context
      existing_files = @app.app_files.map do |file|
        "#{file.path}:\n```\n#{file.content[0..500]}#{(file.content.length > 500) ? "..." : ""}\n```"
      end.join("\n\n")

      # Simplified execution prompt for efficiency
      execution_prompt = <<~PROMPT
        Execute this plan using the available tools:
        #{plan.to_json}
        
        User request: "#{chat_message.content}"
        
        IMPORTANT: You have existing files that need to be updated. Use read_file first to get the full content, then use update_file or write_file as needed.
        
        Existing files in the app:
        #{existing_files}
        
        Instructions:
        1. For existing files, use read_file to get full content first
        2. Then use update_file to modify specific parts OR write_file to completely replace
        3. For new files, use write_file directly
        4. Call broadcast_progress periodically to update the user
        
        Focus on fulfilling the user's request: "#{chat_message.content}"
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert developer. Use tools to implement the plan. Create working, professional code."
        },
        {
          role: "user",
          content: execution_prompt
        }
      ]

      total_operations = 0
      files_modified = []
      max_iterations = 10
      iteration = 0

      while iteration < max_iterations
        iteration += 1
        Rails.logger.info "[AppUpdateOrchestratorV3Claude] Claude iteration #{iteration}"

        # Use Claude Sonnet with tools
        response = @client.chat_with_tools(messages, tools, model: :claude_sonnet_4, temperature: 0.7)

        Rails.logger.info "[AppUpdateOrchestratorV3Claude] Tool response: success=#{response[:success]}, has_tool_calls=#{response[:tool_calls]&.any?}, content_length=#{response[:content]&.length}"

        unless response[:success]
          Rails.logger.error "[AppUpdateOrchestratorV3Claude] Claude failed: #{response[:error]}"
          execution_message.update!(content: "❌ Execution failed: #{response[:error]}", status: "failed")
          broadcast_message_update(execution_message)
          return {success: false, message: response[:error]}
        end

        # Process tool calls
        if response[:tool_calls]&.any?
          Rails.logger.info "[V3Claude] Processing #{response[:tool_calls].length} tool calls"
          tool_results = []

          response[:tool_calls].each do |tool_call|
            Rails.logger.info "[V3Claude] Tool call structure: #{tool_call.inspect}"
            result = process_tool_call(tool_call)
            tool_results << result
            Rails.logger.info "[V3Claude] Tool result: #{result.inspect}"

            if result[:success] && tool_call[:function][:name] != "broadcast_progress"
              total_operations += 1
              files_modified << result[:file_path] if result[:file_path]

              # Update progress
              progress = ((total_operations.to_f / (plan&.dig("total_operations") || 1)) * 100).round
              execution_message.update!(
                content: "🔧 Executing: #{total_operations} operations completed (#{progress}%)",
                status: "executing"
              )
              broadcast_message_update(execution_message)
            end
          end

          # Add tool results to messages for next iteration
          messages << {
            role: "assistant",
            content: response[:content] || "Tool calls executed",
            tool_calls: response[:tool_calls]
          }

          messages << {
            role: "tool",
            tool_call_results: tool_results
          }
        else
          # No more tool calls, execution complete
          break
        end
      end

      execution_message.update!(
        content: "✅ Execution complete: #{total_operations} operations, #{files_modified.uniq.count} files modified",
        status: "completed"
      )
      broadcast_message_update(execution_message)

      {
        success: true,
        result: {
          operations: total_operations,
          files: files_modified.uniq
        }
      }
    end
  end
end
