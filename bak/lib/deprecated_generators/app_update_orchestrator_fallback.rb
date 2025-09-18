module Ai
  # Fallback orchestrator when tool calling is not available
  # Uses traditional prompt-based approach with structured responses
  class AppUpdateOrchestratorFallback
    attr_reader :chat_message, :app, :user

    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @client = OpenRouterClient.new
    end

    def execute!
      Rails.logger.info "[AppUpdateOrchestratorFallback] Using fallback orchestration (no tool calling)"

      # Step 1: Analyze and plan
      plan_response = analyze_and_plan
      return if plan_response[:error]

      # Step 2: Execute changes in one comprehensive prompt
      execution_response = execute_comprehensive_update(plan_response[:plan])
      return if execution_response[:error]

      # Step 3: Apply the changes
      apply_changes(execution_response[:changes])

      # Step 4: Create completion message
      create_completion_message(execution_response[:summary])
    rescue => e
      Rails.logger.error "[AppUpdateOrchestratorFallback] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      create_error_response(e.message)
    end

    private

    def analyze_and_plan
      Rails.logger.info "[AppUpdateOrchestratorFallback] Step 1: Analyzing and planning"

      # Create planning message
      planning_message = create_assistant_message(
        "🔍 Analyzing your request and creating a plan...",
        "executing"
      )

      # Get current files
      current_files = app.app_files.map do |file|
        {path: file.path, content: file.content, type: file.file_type}
      end

      # Load AI standards
      ai_standards = begin
        File.read(Rails.root.join("AI_APP_STANDARDS.md"))
      rescue
        ""
      end

      # Build comprehensive prompt
      prompt = <<~PROMPT
        You are updating a web application. Analyze the request and create a plan.
        
        User Request: #{chat_message.content}
        
        App Name: #{app.name}
        App Type: #{app.app_type}
        
        Current Files:
        #{current_files.map { |f| "=== #{f[:path]} ===\n#{f[:content]}\n" }.join("\n")}
        
        #{ai_standards.present? ? "AI STANDARDS:\n#{ai_standards}" : ""}
        
        Create a detailed plan in JSON format:
        {
          "analysis": "Brief analysis of what needs to be done",
          "approach": "High-level approach",
          "files_to_modify": ["list of files to modify"],
          "files_to_create": ["list of new files"],
          "estimated_complexity": "simple|moderate|complex"
        }
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert web developer. Analyze the request and create a clear plan."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      response = @client.chat(messages, temperature: 0.3, max_tokens: 2000)

      if response[:success]
        plan = parse_json_response(response[:content])

        # Update planning message
        planning_message.update!(
          content: "✅ **Plan Created**\n\n#{plan["analysis"]}\n\n**Approach:** #{plan["approach"]}\n\n**Files to modify:** #{(plan["files_to_modify"] || []).join(", ")}\n**Files to create:** #{(plan["files_to_create"] || []).join(", ")}",
          status: "completed"
        )
        broadcast_message_update(planning_message)

        {success: true, plan: plan}
      else
        planning_message.update!(
          content: "❌ Failed to create plan. Please try again.",
          status: "failed"
        )
        broadcast_message_update(planning_message)

        {error: true, message: response[:error]}
      end
    end

    def execute_comprehensive_update(plan)
      Rails.logger.info "[AppUpdateOrchestratorFallback] Step 2: Executing comprehensive update"

      # Create execution message
      execution_message = create_assistant_message(
        "🚀 Implementing the changes to your app...",
        "executing"
      )

      # Get current files
      current_files = app.app_files.map do |file|
        {path: file.path, content: file.content, type: file.file_type}
      end

      # Load AI standards
      ai_standards = begin
        File.read(Rails.root.join("AI_APP_STANDARDS.md"))
      rescue
        ""
      end

      # Build execution prompt
      prompt = <<~PROMPT
        Based on the plan, implement all the necessary changes to the web application.
        
        User Request: #{chat_message.content}
        
        Plan Summary: #{plan["analysis"]}
        Approach: #{plan["approach"]}
        
        Current Files:
        #{current_files.map { |f| "=== #{f[:path]} ===\n#{f[:content]}\n" }.join("\n")}
        
        #{ai_standards.present? ? "AI STANDARDS (MUST FOLLOW):\n#{ai_standards}" : ""}
        
        CRITICAL REQUIREMENTS:
        1. Generate COMPLETE file contents, not snippets
        2. Include all necessary HTML, CSS, and JavaScript
        3. Use Tailwind CSS for all styling
        4. Include realistic sample data (5-10 items minimum)
        5. Implement proper error handling and loading states
        6. Ensure mobile responsiveness
        7. Follow modern JavaScript patterns (ES6+)
        
        Return a JSON response with ALL file changes:
        {
          "changes": [
            {
              "action": "create|update|delete",
              "path": "filename.ext",
              "content": "COMPLETE file content here",
              "file_type": "html|css|js|json"
            }
          ],
          "summary": "Brief summary of what was implemented",
          "features_added": ["list of features added"]
        }
        
        IMPORTANT: Include the COMPLETE content for each file, not just the changes.
      PROMPT

      messages = [
        {
          role: "system",
          content: "You are an expert web developer. Generate complete, production-ready code following all the standards provided."
        },
        {
          role: "user",
          content: prompt
        }
      ]

      # Use higher token limit for comprehensive response
      response = @client.chat(messages, temperature: 0.3, max_tokens: 16000)

      if response[:success]
        result = parse_json_response(response[:content])

        # Update execution message with progress
        execution_message.update!(
          content: "✅ Code generation complete. Applying changes...",
          status: "executing"
        )
        broadcast_message_update(execution_message)

        {success: true, changes: result["changes"] || [], summary: result["summary"]}
      else
        execution_message.update!(
          content: "❌ Failed to generate code: #{response[:error]}",
          status: "failed"
        )
        broadcast_message_update(execution_message)

        {error: true, message: response[:error]}
      end
    end

    def apply_changes(changes)
      Rails.logger.info "[AppUpdateOrchestratorFallback] Step 3: Applying #{changes.length} changes"

      # Create progress message
      progress_message = create_assistant_message(
        "📝 Applying changes to files...",
        "executing"
      )

      files_modified = []

      changes.each_with_index do |change, index|
        # Update progress
        progress_message.update!(
          content: "📝 Processing file #{index + 1}/#{changes.length}: #{change["path"]}..."
        )
        broadcast_message_update(progress_message)

        case change["action"]
        when "create", "update"
          file = app.app_files.find_or_initialize_by(path: change["path"])
          file.content = change["content"]
          file.file_type = change["file_type"] || detect_file_type(change["path"])

          if file.save
            files_modified << change["path"]
            Rails.logger.info "[AppUpdateOrchestratorFallback] Saved file: #{change["path"]}"
          else
            Rails.logger.error "[AppUpdateOrchestratorFallback] Failed to save #{change["path"]}: #{file.errors.full_messages.join(", ")}"
          end

        when "delete"
          file = app.app_files.find_by(path: change["path"])
          if file
            file.destroy
            Rails.logger.info "[AppUpdateOrchestratorFallback] Deleted file: #{change["path"]}"
          end
        end

        # Small delay to show progress
        sleep(0.1)
      end

      # Update preview
      if files_modified.any?
        UpdatePreviewJob.perform_later(app.id)
      end

      # Update progress message
      progress_message.update!(
        content: "✅ Successfully applied changes to #{files_modified.length} files",
        status: "completed"
      )
      broadcast_message_update(progress_message)

      files_modified
    end

    def create_completion_message(summary)
      completion_message = create_assistant_message(
        "✅ **Update Complete!**\n\n#{summary}\n\nYour app has been updated successfully. Check the preview to see your changes in action!",
        "completed"
      )

      broadcast_message_update(completion_message)

      # Re-enable the chat form
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{app.id}_chat",
        target: "chat_form",
        partial: "account/app_editors/chat_input_wrapper",
        locals: {app: app}
      )
    end

    def create_error_response(error_message)
      error_response = create_assistant_message(
        "❌ An error occurred: #{error_message}\n\nPlease try again with a simpler request.",
        "failed"
      )

      broadcast_message_update(error_response)

      # Re-enable the chat form by broadcasting a custom event
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
        Rails.logger.error "[AppUpdateOrchestratorFallback] Failed to replace chat form: #{e.message}"
      end
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

    def parse_json_response(content)
      # Try multiple extraction patterns
      # First try to find JSON between ```json and ```
      json_match = content.match(/```json\s*(.*?)\s*```/m)

      # If not found, try to find any JSON object
      json_match ||= content.match(/\{.*\}/m)

      return {} unless json_match

      json_str = json_match[1] || json_match[0]

      begin
        JSON.parse(json_str)
      rescue JSON::ParserError => e
        Rails.logger.error "[AppUpdateOrchestratorFallback] Failed to parse JSON: #{e.message}"
        Rails.logger.error "[AppUpdateOrchestratorFallback] Content was: #{json_str[0..500]}"
        {}
      end
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
  end
end
