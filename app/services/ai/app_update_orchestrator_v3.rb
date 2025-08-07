module Ai
  # GPT-5 Enhanced orchestrator with V2's sophisticated planning + working tool calling
  class AppUpdateOrchestratorV3
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
      Rails.logger.info "[AppUpdateOrchestratorV3] Starting GPT-5 enhanced execution for message ##{chat_message.id}"
      
      # Step 1: Quick analysis (simplified from V2's approach)
      structure_response = analyze_app_structure_gpt5
      return if structure_response[:error]
      
      # Step 2: Create plan with GPT-5 (using V2's sophisticated planning)
      plan_response = create_execution_plan_gpt5(structure_response[:analysis])
      return if plan_response[:error]
      
      # Step 3: Execute with working tool calling (based on autonomous success)
      execution_response = execute_with_gpt5_tools(plan_response[:plan])
      return if execution_response[:error]
      
      # Step 4: Finalize
      finalize_update_gpt5(execution_response[:result])
      
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorV3] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      create_error_response(e.message)
    end
    
    private
    
    def analyze_app_structure_gpt5
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Analysis Phase"
      
      # Create progress message
      analysis_message = create_assistant_message(
        "🔍 Analyzing your app structure and understanding the request...",
        "executing"
      )
      
      # Get current app state
      current_files = get_cached_or_load_files || []
      env_vars = get_cached_or_load_env_vars || []
      
      # Use simplified standards for GPT-5 to avoid timeout
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
      
      # Use GPT-5 with proper temperature
      response = @client.chat(messages, model: :gpt5, temperature: 1.0)
      
      if response[:success]
        analysis = parse_json_response(response[:content])
        
        analysis_message.update!(
          content: "✅ Analysis complete: #{analysis&.dig('complexity_level') || 'unknown'} complexity, #{analysis&.dig('estimated_files') || 0} files needed",
          status: "completed"
        )
        broadcast_message_update(analysis_message)
        
        { success: true, analysis: analysis }
      else
        analysis_message.update!(
          content: "❌ Failed to analyze app structure: #{response[:error]}",
          status: "failed"
        )
        broadcast_message_update(analysis_message)
        
        { error: true, message: response[:error] }
      end
    end
    
    def create_execution_plan_gpt5(analysis)
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Planning Phase"
      
      # Create planning message
      planning_message = create_assistant_message(
        "📝 Creating detailed execution plan...",
        "executing"
      )
      
      # Simplified planning for GPT-5 efficiency
      plan_prompt = <<~PROMPT
        Create execution plan for: "#{chat_message.content}"
        
        Analysis: #{analysis.to_json}
        
        Tools: create_file, update_file, broadcast_progress, finish_app
        
        Return JSON plan:
        {
          "summary": "What will be built",
          "steps": [
            {
              "description": "Step description",
              "operations": ["create index.html", "add functionality"]
            }
          ],
          "estimated_files": 3,
          "complexity": "simple"
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
      
      response = @client.chat(messages, model: :gpt5, temperature: 1.0)
      
      if response[:success]
        plan = parse_json_response(response[:content])
        
        planning_message.update!(
          content: "✅ Execution plan ready: #{plan&.dig('summary') || 'App update plan created'}",
          status: "completed"
        )
        broadcast_message_update(planning_message)
        
        { success: true, plan: plan }
      else
        planning_message.update!(
          content: "❌ Failed to create execution plan: #{response[:error]}",
          status: "failed"
        )
        broadcast_message_update(planning_message)
        
        { error: true, message: response[:error] }
      end
    end
    
    def execute_with_gpt5_tools(plan)
      Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 Tool Execution Phase"
      
      # Create execution message
      execution_message = create_assistant_message(
        "🚀 Implementing changes to your app...",
        "executing"
      )
      
      # Use proven working tool approach from autonomous tests
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
                percentage: { type: "integer", description: "Progress percentage 0-100" }
              },
              required: ["message"]
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
      
      # Load current app state
      file_contents = {}
      app.app_files.each { |file| file_contents[file.path] = file.content }
      
      # Simplified execution prompt for GPT-5 efficiency
      execution_prompt = <<~PROMPT
        IMPLEMENT: "#{chat_message.content}"
        
        Plan: #{plan.to_json}
        
        Current Files:
        #{file_contents.map { |path, content| "#{path}:\n#{content[0..200]}..." }.join("\n")}
        
        Requirements:
        1. Use React, Tailwind CSS, modern JavaScript
        2. Create clean, professional code
        3. Use broadcast_progress for status updates
        4. Use create_file for new files, update_file for changes
        5. End with finish_app when complete
        
        Build a working, professional app step by step.
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
      max_iterations = 15
      iteration = 0
      
      while iteration < max_iterations
        iteration += 1
        Rails.logger.info "[AppUpdateOrchestratorV3] GPT-5 iteration #{iteration}"
        
        response = @client.chat_with_tools(messages, tools, model: :gpt5, temperature: 1.0)
        
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
              handle_broadcast_progress(args, execution_message)
              tool_results << create_tool_result(tool_call["id"], { success: true, message: "Progress updated" })
              
            when "finish_app"
              summary = args["summary"]
              execution_message.update!(
                content: "✅ Implementation complete: #{summary}",
                status: "completed"
              )
              broadcast_message_update(execution_message)
              
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
      execution_message.update!(
        content: "✅ Implementation complete (reached iteration limit)",
        status: "completed"
      )
      
      { success: true, result: { files: files_created } }
    end
    
    def handle_create_file(args)
      path = args["path"]
      content = args["content"]
      file_type = args["file_type"] || determine_file_type(path)
      
      begin
        # Create or update file in database
        file = app.app_files.find_by(path: path) || app.app_files.build(path: path, team: app.team)
        file.update!(
          content: content,
          file_type: file_type,
          size_bytes: content.bytesize
        )
        
        Rails.logger.info "[AppUpdateOrchestratorV3] Created/updated file: #{path} (#{content.bytesize} bytes)"
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
        file.update!(
          content: updated_content,
          size_bytes: updated_content.bytesize
        )
        
        Rails.logger.info "[AppUpdateOrchestratorV3] Updated file: #{path}"
        { success: true, message: "File #{path} updated successfully" }
      rescue => e
        Rails.logger.error "[AppUpdateOrchestratorV3] File update failed: #{e.message}"
        { success: false, message: "Failed to update #{path}: #{e.message}" }
      end
    end
    
    def handle_broadcast_progress(args, execution_message)
      message = args["message"]
      percentage = args["percentage"]
      
      progress_text = percentage ? "#{message} (#{percentage}%)" : message
      
      execution_message.update!(content: "🚀 #{progress_text}")
      broadcast_message_update(execution_message)
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
      
      # Create final assistant response
      summary = result[:summary] || "App updated successfully"
      
      final_message = create_assistant_message(
        "✅ #{summary}\n\nYour app has been updated and is ready to use!",
        "completed"
      )
      
      broadcast_message_update(final_message)
    end
    
    # Helper methods from V2
    def create_assistant_message(content, status)
      app.app_chat_messages.create!(
        role: "assistant",
        content: content,
        status: status
      )
    end
    
    def broadcast_message_update(message)
      # Implement broadcast logic if needed
      Rails.logger.info "[AppUpdateOrchestratorV3] Broadcasting: #{message.content[0..100]}"
    end
    
    def create_error_response(error_message)
      error_message = create_assistant_message(
        "❌ An error occurred: #{error_message}\n\nPlease try again or rephrase your request.",
        "failed"
      )
      broadcast_message_update(error_message)
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
      []  # Implement if needed
    end
  end
end