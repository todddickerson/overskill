module Ai
  # Orchestrates the multi-step AI update process with better user feedback
  class AppUpdateOrchestrator
    MAX_IMPROVEMENT_ITERATIONS = 3

    attr_reader :chat_message, :app, :user

    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @iteration_count = 0
      @improvements_made = []
    end

    def execute!
      Rails.logger.info "[AppUpdateOrchestrator] Starting orchestrated update for message ##{chat_message.id}"

      # Step 1: Analyze request and create plan
      plan_response = analyze_and_plan
      return if plan_response[:error]

      # Step 2: Show chain of thought insights
      share_thought_process(plan_response[:plan])

      # Step 3: Execute the changes
      execution_response = execute_changes(plan_response[:plan])
      return if execution_response[:error]

      # Step 4: Validate and potentially improve recursively
      final_response = validate_and_improve_recursively(execution_response[:result])

      # Step 5: Create final success message
      create_final_response(final_response)
    rescue => e
      Rails.logger.error "[AppUpdateOrchestrator] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      create_error_response(e.message)
    end

    private

    def analyze_and_plan
      Rails.logger.info "[AppUpdateOrchestrator] Step 1: Analyzing request and creating plan"

      # Create planning message
      planning_message = create_assistant_message(
        "Let me analyze your request and create a plan...",
        "planning"
      )

      # Get current app state
      current_files = app.app_files.map do |file|
        {path: file.path, content: file.content, type: file.file_type}
      end

      # Call AI to analyze and plan
      client = OpenRouterClient.new
      response = client.analyze_app_update_request(
        request: chat_message.content,
        current_files: current_files,
        app_context: {
          name: app.name,
          type: app.app_type,
          framework: app.framework
        }
      )

      if response[:success]
        # Update planning message with the plan
        plan_content = format_plan_message(response[:plan])
        planning_message.update!(
          content: plan_content,
          status: "completed"
        )
        broadcast_message_update(planning_message)

        {success: true, plan: response[:plan]}
      else
        planning_message.update!(
          content: "I couldn't understand your request. Could you please be more specific?",
          status: "failed"
        )
        broadcast_message_update(planning_message)

        {error: true, message: response[:error]}
      end
    end

    def share_thought_process(plan)
      Rails.logger.info "[AppUpdateOrchestrator] Step 2: Sharing thought process"

      # Create insight message showing our thinking
      insights = extract_insights_from_plan(plan)

      if insights.any?
        thought_message = create_assistant_message(
          format_thought_process(insights),
          "completed"
        )
        broadcast_message_update(thought_message)
      end

      {success: true}
    end

    def execute_changes(plan)
      Rails.logger.info "[AppUpdateOrchestrator] Step 3: Executing changes"

      # Create execution status message
      execution_message = create_assistant_message(
        "Implementing the changes to your app...",
        "executing"
      )

      # Call AI to generate the changes
      client = OpenRouterClient.new
      response = client.execute_app_update(plan)

      if response[:success]
        # Apply the changes
        result = apply_changes_to_app(response[:changes])

        execution_message.update!(
          content: format_execution_summary(result),
          status: "completed"
        )
        broadcast_message_update(execution_message)

        {success: true, result: result}
      else
        execution_message.update!(
          content: "Failed to implement changes: #{response[:error]}",
          status: "failed"
        )
        broadcast_message_update(execution_message)

        {error: true, message: response[:error]}
      end
    end

    def validate_and_improve_recursively(initial_result)
      Rails.logger.info "[AppUpdateOrchestrator] Step 4: Validating and improving"

      current_result = initial_result

      while @iteration_count < MAX_IMPROVEMENT_ITERATIONS
        @iteration_count += 1

        # Create validation message
        validation_message = create_assistant_message(
          "Validating the changes (iteration #{@iteration_count}/#{MAX_IMPROVEMENT_ITERATIONS})...",
          "executing"
        )

        # Validate current state
        validation = validate_app_state(current_result)

        if validation[:issues].empty?
          validation_message.update!(
            content: "✅ Validation passed! The app looks good.",
            status: "completed"
          )
          broadcast_message_update(validation_message)
          break
        else
          # Show issues found
          validation_message.update!(
            content: format_validation_issues(validation[:issues]),
            status: "completed"
          )
          broadcast_message_update(validation_message)

          # Attempt to fix issues
          improvement_message = create_assistant_message(
            "I found some issues. Let me fix them...",
            "executing"
          )

          improvement_result = improve_app(validation[:issues])

          if improvement_result[:success]
            improvement_message.update!(
              content: format_improvement_summary(improvement_result[:changes]),
              status: "completed"
            )
            broadcast_message_update(improvement_message)

            current_result = improvement_result
            @improvements_made << improvement_result[:changes]
          else
            improvement_message.update!(
              content: "Couldn't automatically fix all issues. Manual review recommended.",
              status: "completed"
            )
            broadcast_message_update(improvement_message)
            break
          end
        end
      end

      current_result
    end

    def create_final_response(result)
      Rails.logger.info "[AppUpdateOrchestrator] Step 5: Creating final response"

      # Create comprehensive final message
      final_content = build_final_response_content(result)

      final_message = create_assistant_message(
        final_content,
        "completed"
      )

      # Create app version if changes were made
      if result[:files_changed]&.any?
        create_app_version(result, final_message)
      end

      broadcast_message_update(final_message)
      broadcast_preview_update
      broadcast_chat_form_update
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

    def broadcast_preview_update
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{app.id}_chat",
        target: "preview_frame",
        partial: "account/app_editors/preview_frame",
        locals: {app: app}
      )
    end

    def broadcast_chat_form_update
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{app.id}_chat",
        target: "chat_form",
        partial: "account/app_editors/chat_input_wrapper",
        locals: {app: app}
      )
    end

    def format_plan_message(plan)
      message = "## 📋 Here's my plan:\n\n"

      plan[:steps].each_with_index do |step, index|
        message += "#{index + 1}. #{step[:description]}\n"
      end

      if plan[:considerations]&.any?
        message += "\n### 💭 Considerations:\n"
        plan[:considerations].each do |consideration|
          message += "- #{consideration}\n"
        end
      end

      message
    end

    def format_thought_process(insights)
      message = "## 🧠 My thought process:\n\n"

      insights.each do |insight|
        case insight[:type]
        when :analysis
          message += "**Analysis:** #{insight[:content]}\n\n"
        when :approach
          message += "**Approach:** #{insight[:content]}\n\n"
        when :consideration
          message += "**Considering:** #{insight[:content]}\n\n"
        end
      end

      message
    end

    def format_execution_summary(result)
      message = "## ✨ Changes implemented:\n\n"

      if result[:files_modified]&.any?
        message += "**Files modified:**\n"
        result[:files_modified].each do |file|
          message += "- `#{file[:path]}` - #{file[:summary]}\n"
        end
      end

      if result[:files_added]&.any?
        message += "\n**Files added:**\n"
        result[:files_added].each do |file|
          message += "- `#{file[:path]}` - #{file[:summary]}\n"
        end
      end

      message
    end

    def format_validation_issues(issues)
      message = "## 🔍 Validation found these issues:\n\n"

      issues.each_with_index do |issue, index|
        emoji = case issue[:severity]
        when :error then "🔴"
        when :warning then "🟡"
        else "🟢"
        end

        message += "#{index + 1}. #{emoji} **#{issue[:title]}**\n"
        message += "   - #{issue[:description]}\n"
        message += "   - File: `#{issue[:file]}`\n" if issue[:file]
        message += "\n"
      end

      message
    end

    def format_improvement_summary(changes)
      message = "## 🔧 Fixed the following issues:\n\n"

      changes[:fixes].each do |fix|
        message += "- ✅ #{fix[:issue]} - #{fix[:solution]}\n"
      end

      message
    end

    def build_final_response_content(result)
      message = "## 🎉 Update complete!\n\n"

      message += "### Summary:\n"
      message += result[:summary] + "\n\n"

      if @improvements_made.any?
        message += "### 🔄 Improvements made:\n"
        @improvements_made.each do |improvement|
          improvement[:fixes].each do |fix|
            message += "- #{fix[:solution]}\n"
          end
        end
        message += "\n"
      end

      if result[:whats_next]&.any?
        message += "### 💡 What's next?\n"
        result[:whats_next].each do |suggestion|
          message += "- **#{suggestion[:title]}**: #{suggestion[:description]}\n"
        end
      end

      message
    end

    def extract_insights_from_plan(plan)
      # Extract insights from the plan for chain-of-thought display
      insights = []

      if plan[:analysis]
        insights << {type: :analysis, content: plan[:analysis]}
      end

      if plan[:approach]
        insights << {type: :approach, content: plan[:approach]}
      end

      plan[:trade_offs]&.each do |trade_off|
        insights << {type: :consideration, content: trade_off}
      end

      insights
    end

    def apply_changes_to_app(changes)
      # Apply file changes to the app
      result = {
        files_modified: [],
        files_added: [],
        files_changed: []
      }

      changes[:files].each do |file_change|
        file = app.app_files.find_or_initialize_by(path: file_change[:path])

        if file.persisted?
          file.content = file_change[:content]
          file.save!
          result[:files_modified] << {
            path: file_change[:path],
            summary: file_change[:summary] || "Updated"
          }
        else
          file.content = file_change[:content]
          file.file_type = determine_file_type(file_change[:path])
          file.size_bytes = file_change[:content].bytesize
          file.team = app.team
          file.save!
          result[:files_added] << {
            path: file_change[:path],
            summary: file_change[:summary] || "Created"
          }
        end

        result[:files_changed] << file
      end

      result[:summary] = changes[:summary] || "Updated app based on your request"
      result[:whats_next] = changes[:whats_next] || []

      result
    end

    def validate_app_state(result)
      # Run validation on current app state
      issues = []

      # Prepare files array for validation
      files_to_validate = app.app_files.map do |file|
        {
          path: file.path,
          content: file.content
        }
      end

      validation_result = Ai::CodeValidatorService.validate_files(files_to_validate)

      validation_result[:errors].each do |error|
        issues << {
          severity: :error,
          title: error[:message],
          description: "Pattern '#{error[:pattern]}' found",
          file: error[:file],
          line: nil
        }
      end

      validation_result[:warnings].each do |warning|
        issues << {
          severity: :warning,
          title: warning[:message],
          description: "Potential issue detected",
          file: warning[:file] || "unknown"
        }
      end

      # Add AI-detected issues if any
      result[:validation_issues]&.each do |issue|
        issues << issue
      end

      {issues: issues}
    end

    def improve_app(issues)
      # Call AI to fix the identified issues
      client = OpenRouterClient.new

      current_files = app.app_files.map do |file|
        {path: file.path, content: file.content, type: file.file_type}
      end

      response = client.fix_app_issues(
        issues: issues,
        current_files: current_files
      )

      if response[:success]
        result = apply_changes_to_app(response[:changes])
        result[:changes] = response[:changes]
        {success: true, **result}
      else
        {success: false, error: response[:error]}
      end
    end

    def create_app_version(result, message)
      version = app.app_versions.create!(
        team: app.team,
        user: user,
        version_number: next_version_number,
        changelog: message.content,
        files_snapshot: app.app_files.map { |f| {path: f.path, content: f.content} }.to_json,
        changed_files: result[:files_changed].map(&:path)
      )

      message.update!(app_version: version)
    end

    def create_error_response(error_message)
      error_response = create_assistant_message(
        "❌ I encountered an error: #{error_message}\n\nPlease try rephrasing your request or contact support if the issue persists.",
        "failed"
      )

      broadcast_message_update(error_response)
      broadcast_chat_form_update
    end

    def next_version_number
      last_version = app.app_versions.order(created_at: :desc).first
      if last_version
        parts = last_version.version_number.split(".")
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join(".")
      else
        "1.0.0"
      end
    end

    def determine_file_type(path)
      ext = File.extname(path).downcase.delete(".")
      case ext
      when "html", "htm" then "html"
      when "js", "jsx" then "javascript"
      when "css", "scss" then "css"
      when "json" then "json"
      else "text"
      end
    end
  end
end
