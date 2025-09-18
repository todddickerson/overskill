module Ai
  # Streaming orchestrator with real-time progress updates
  class AppUpdateOrchestratorStreaming
    attr_reader :chat_message, :app, :user

    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @client = OpenRouterClient.new
      @current_message = nil
      @buffer = ""
      @current_file_operation = nil
      @accumulated_content = ""  # Track full message content
      @files_processed = []  # Track files that have been processed
      @version_created = false  # Track if version was created
    end

    def execute!
      Rails.logger.info "[StreamingOrchestrator] Starting streaming update for message ##{chat_message.id}"

      # Create initial assistant message
      @current_message = create_assistant_message(
        "🤔 Understanding your request...",
        "executing"
      )

      # Get current app state
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
      prompt = build_streaming_prompt(current_files, ai_standards)

      # Use function calling instead of streaming for reliable output
      execute_with_function_calling(prompt)
    rescue => e
      Rails.logger.error "[StreamingOrchestrator] Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      create_error_response(e.message)
    end

    private

    def build_streaming_prompt(current_files, ai_standards)
      <<~PROMPT
        You are updating a web application. Implement the requested changes step by step.
        
        User Request: #{chat_message.content}
        
        App Details:
        - Name: #{app.name}
        - Type: #{app.app_type}
        - Framework: #{app.framework}
        
        Current Files:
        #{current_files.map { |f| "#{f[:path]} (#{f[:type]})" }.join("\n")}
        
        AI STANDARDS TO FOLLOW:
        #{ai_standards}
        
        IMPORTANT: As you work, output your actions in this format:
        
        [THINKING] Your analysis of what needs to be done
        [PLANNING] Your step-by-step plan
        [FILE_START:filename.ext] Starting work on a file
        [FILE_CONTENT]
        The complete file content goes here
        [FILE_END:filename.ext]
        [PROGRESS] What you just completed
        [COMPLETE] Final summary
        
        For each file you create or modify:
        1. Use [FILE_START:path] to indicate starting a file
        2. Output the COMPLETE file content
        3. Use [FILE_END:path] to indicate file completion
        4. Use [PROGRESS] to describe what was done
        
        Generate COMPLETE, production-ready code following all the standards.
        Include realistic sample data and all required features.
      PROMPT
    end

    def execute_with_function_calling(prompt)
      @current_message.content = "🔄 Processing your request..."
      @current_message.save!
      broadcast_message_content_update(@current_message)

      # Determine if this is a new app or an update
      current_files = app.app_files.to_a
      is_new_app = current_files.empty? || current_files.none? { |f| f.file_type == "html" }

      if is_new_app
        Rails.logger.info "[StreamingOrchestrator] 🆕 New app generation - using generate_app"
        result = @client.generate_app(
          chat_message.content,
          framework: app.framework,
          app_type: app.app_type
        )
      else
        Rails.logger.info "[StreamingOrchestrator] 🔄 App update - using update_app"
        result = @client.update_app(
          chat_message.content,
          current_files.map { |f| {path: f.path, content: f.content, type: f.file_type} },
          {name: app.name, type: app.app_type, framework: app.framework}
        )
      end

      if result[:success]
        # Process function call results
        process_function_result(result)
      else
        create_error_response(result[:error] || (is_new_app ? "Generation failed" : "Update failed"))
      end
    end

    def process_function_result(result)
      @current_message.content = "⚡ Applying changes..."
      @current_message.save!
      broadcast_message_content_update(@current_message)

      Rails.logger.debug "[AppUpdateOrchestratorStreaming] 🔍 Function result debug:"
      Rails.logger.debug "[AppUpdateOrchestratorStreaming] Result keys: #{result.keys}"
      Rails.logger.debug "[AppUpdateOrchestratorStreaming] Tool calls: #{result[:tool_calls].inspect.truncate(1000)}"

      # Extract function call result from tool_calls, not content
      tool_calls = result[:tool_calls]
      if tool_calls&.any?
        # Get the first function call result
        function_call = tool_calls.first
        function_result = JSON.parse(function_call.dig("function", "arguments"), symbolize_names: true)

        Rails.logger.debug "[AppUpdateOrchestratorStreaming] 🔧 Parsed function result: #{function_result.inspect.truncate(500)}"
      else
        Rails.logger.warn "[AppUpdateOrchestratorStreaming] ⚠️ No tool calls found in result"
        create_error_response("AI did not use function calls - likely a model issue")
        return
      end

      if function_result.is_a?(Hash) && (function_result[:files] || function_result[:changes])
        # Support both :files and :changes formats for different models
        files_data = function_result[:files] || function_result[:changes]

        # Apply file changes with progress updates
        files_data.each do |file_data|
          # Normalize field names for different model formats
          normalized_file_data = normalize_file_data(file_data)

          # Broadcast that we're starting to edit this file
          broadcast_file_progress(normalized_file_data[:path], "editing")

          update_progress("📝 Updating #{normalized_file_data[:path]}...")
          apply_file_change(normalized_file_data)

          # Broadcast that we've completed this file
          broadcast_file_progress(normalized_file_data[:path], "completed")
        end

        # Create version and final summary
        if @files_processed.any?
          version = create_version_for_changes
          final_summary = build_base44_style_summary(function_result)
          @current_message.content = final_summary
          @current_message.status = "completed"
          @current_message.save!
          broadcast_message_content_update(@current_message)

          # Broadcast version completion for live UI update
          if version
            broadcast_version_complete(version)
          end
        end

        # Update preview
        UpdatePreviewJob.perform_later(app.id)
      else
        create_error_response("Invalid function result format")
      end
    end

    def apply_file_change(file_data)
      # Debug logging for file data
      Rails.logger.debug "[StreamingOrchestrator] 🔧 Processing file: #{file_data[:path]}"
      Rails.logger.debug "[StreamingOrchestrator] 🔧 Content length: #{file_data[:content]&.length || "nil"}"

      # Validate content exists
      if file_data[:content].blank?
        Rails.logger.error "[StreamingOrchestrator] ❌ Empty content for #{file_data[:path]}, skipping"
        return
      end

      file_type = detect_file_type(file_data[:path])

      file = app.app_files.find_or_initialize_by(path: file_data[:path])
      was_new = file.new_record?
      file.team = app.team if was_new
      file.content = file_data[:content]
      file.file_type = file_type
      file.size_bytes = file_data[:content].bytesize
      file.is_entry_point = (file_data[:path] == "index.html")

      if file.save
        Rails.logger.info "[StreamingOrchestrator] ✅ Saved #{file_data[:path]} (#{file_type})"
        @files_processed << {
          path: file_data[:path],
          action: was_new ? "created" : "updated",
          file_type: file_type
        }
      else
        Rails.logger.error "[StreamingOrchestrator] ❌ Failed to save #{file_data[:path]}: #{file.errors.full_messages.join(", ")}"
      end
    end

    def update_progress(message)
      @current_message.content = message
      @current_message.save!
      broadcast_message_content_update(@current_message)

      # Also broadcast version progress update
      broadcast_version_progress(message)
    end

    def build_base44_style_summary(function_result)
      # Build a Base44-style response with specific task completion
      summary = "**#{chat_message.content}**\n\n"

      if @files_processed.any?
        @files_processed.each do |file_info|
          case file_info[:file_type]
          when "html" then "🏠"
          when "css" then "🎨"
          when "js" then "⚡"
          else "📄"
          end

          action_text = case file_info[:action]
          when "created" then "Creating"
          when "updated" then "Editing"
          else "Modifying"
          end

          summary += "✅ #{action_text} #{File.basename(file_info[:path])}\n"
          summary += "   #{file_info[:path]}\n\n"
        end
      end

      # Add contextual description if available
      if function_result[:summary]
        summary += "#{function_result[:summary]}\n\n"
      end

      summary += "**Completed**"
      summary
    end

    def process_streaming_chunk(chunk)
      # Add chunk to buffer
      @buffer += chunk

      # Process markers in the buffer
      while process_next_marker
        # Keep processing markers until none are found
      end

      # Update the current message periodically with buffer content
      if @buffer.length > 100 && !@current_file_operation
        flush_buffer_to_message
      end
    end

    def process_next_marker
      # Check for [THINKING] marker
      if @buffer =~ /\[THINKING\]\s*(.*?)(?=\[|\z)/m
        content = $1.strip
        update_message("🔍 #{content}", "executing")
        @buffer = @buffer.sub(/\[THINKING\]\s*.*?(?=\[|\z)/m, "")
        return true
      end

      # Check for [PLANNING] marker
      if @buffer =~ /\[PLANNING\]\s*(.*?)(?=\[|\z)/m
        content = $1.strip
        update_message("📋 Planning: #{content}", "executing")
        @buffer = @buffer.sub(/\[PLANNING\]\s*.*?(?=\[|\z)/m, "")
        return true
      end

      # Check for [FILE_START:filename] marker
      if @buffer =~ /\[FILE_START:(.*?)\]/
        filename = $1.strip
        @current_file_operation = {path: filename, content: ""}
        update_message("📝 Creating #{filename}...", "executing")
        @buffer = @buffer.sub(/\[FILE_START:.*?\]/, "")
        return true
      end

      # Check for [FILE_END:filename] marker
      if @buffer =~ /\[FILE_END:(.*?)\]/
        filename = $1.strip

        if @current_file_operation
          # Extract file content
          if @buffer =~ /\[FILE_CONTENT\](.*?)\[FILE_END:#{Regexp.escape(filename)}\]/m
            file_content = $1.strip
            save_file(@current_file_operation[:path], file_content)
            update_message("✅ Saved #{@current_file_operation[:path]}", "executing")
            @buffer = @buffer.sub(/\[FILE_CONTENT\].*?\[FILE_END:#{Regexp.escape(filename)}\]/m, "")
          elsif @buffer =~ /(.*?)\[FILE_END:#{Regexp.escape(filename)}\]/m
            # Content without FILE_CONTENT marker
            file_content = $1.strip
            save_file(@current_file_operation[:path], file_content)
            update_message("✅ Saved #{@current_file_operation[:path]}", "executing")
            @buffer = @buffer.sub(/.*?\[FILE_END:#{Regexp.escape(filename)}\]/m, "")
          end

          @current_file_operation = nil
        else
          @buffer = @buffer.sub(/\[FILE_END:.*?\]/, "")
        end
        return true
      end

      # Check for [PROGRESS] marker
      if @buffer =~ /\[PROGRESS\]\s*(.*?)(?=\[|\z)/m
        content = $1.strip
        update_message("⚡ #{content}", "executing")
        @buffer = @buffer.sub(/\[PROGRESS\]\s*.*?(?=\[|\z)/m, "")
        return true
      end

      # Check for [COMPLETE] marker
      if @buffer =~ /\[COMPLETE\]\s*(.*?)(?=\[|\z)/m
        content = $1.strip
        update_message("✅ Complete! #{content}", "completed")
        @buffer = @buffer.sub(/\[COMPLETE\]\s*.*?(?=\[|\z)/m, "")

        # Update preview
        UpdatePreviewJob.perform_later(app.id)
        return true
      end

      # If we're collecting file content, append to current operation
      if @current_file_operation && @buffer.length > 0
        # Look for the end marker
        if @buffer.include?("[FILE_END:#{@current_file_operation[:path]}]")
          # We'll process this in the FILE_END handler above
          return true
        else
          # Still collecting content
          return false
        end
      end

      false
    end

    def flush_buffer_to_message
      # If buffer has content but no markers, show it as progress
      if @buffer.length > 0 && !@current_file_operation
        content = @buffer.strip
        if content.length > 0
          update_message(content, "executing")
          @buffer = ""
        end
      end
    end

    def finalize_streaming
      # Process any remaining buffer content
      flush_buffer_to_message

      # Create version if files were modified
      if @files_processed.any? && !@version_created
        create_version_for_changes
      end

      # Build final summary message
      if @current_message && @current_message.status == "executing"
        final_message = build_final_summary
        @accumulated_content = final_message
        update_message(final_message, "completed")
      end

      # Update preview
      UpdatePreviewJob.perform_later(app.id)

      # Re-enable chat form
      enable_chat_form
    end

    def build_final_summary
      summary = "✅ **Update complete!**\n\n"

      if @files_processed.is_a?(Array) && @files_processed.any?
        summary += "**Files updated:**\n"
        @files_processed.each do |file|
          summary += "• #{file[:path]} (#{file[:action]})\n"
        end
        summary += "\n"
      end

      summary += "Your app has been updated and the preview is refreshing.\n\n"

      # Add "What's next" suggestions
      summary += generate_whats_next_suggestions

      summary
    end

    def generate_whats_next_suggestions
      suggestions = []

      # Ensure @files_processed is an array
      return "**💡 What's next?** Try asking:\n- 🚀 \"Deploy to production\"\n- 🧪 \"Test different variations\"\n- 📊 \"Add analytics tracking\"\n" unless @files_processed.is_a?(Array)

      # Analyze what was changed to provide contextual suggestions
      file_types = @files_processed.map { |f| f[:file_type] }.uniq

      if file_types.include?("css")
        suggestions << "🎨 \"Improve the styling and colors\""
        suggestions << "📱 \"Make it mobile responsive\""
      end

      if file_types.include?("js")
        suggestions << "⚡ \"Add more interactive features\""
        suggestions << "🔧 \"Optimize the performance\""
      end

      if file_types.include?("html")
        suggestions << "🖼️ \"Add more content sections\""
        suggestions << "🔗 \"Create additional pages\""
      end

      # Always include these general suggestions
      suggestions << "🧪 \"Test different variations\""
      suggestions << "🚀 \"Deploy to production\""
      suggestions << "📊 \"Add analytics tracking\""

      # Shuffle and take 3 random suggestions to keep it fresh
      selected_suggestions = suggestions.sample(3)

      whats_next = "**💡 What's next?** Try asking:\n"
      selected_suggestions.each do |suggestion|
        whats_next += "- #{suggestion}\n"
      end

      whats_next
    end

    def create_version_for_changes
      version_number = next_version_number(app)
      changelog = "AI Update: #{chat_message.content[0..100]}#{(chat_message.content.length > 100) ? "..." : ""}"

      app_version = app.app_versions.create!(
        team: app.team,
        user: user,
        version_number: version_number,
        changelog: changelog,
        files_snapshot: app.app_files.map { |f|
          {path: f.path, content: f.content, file_type: f.file_type}
        }.to_json
      )

      # Create version file records for tracking changes
      if @files_processed.is_a?(Array) && @files_processed.any?
        @files_processed.each do |file_info|
          app_file = app.app_files.find_by(path: file_info[:path])
          if app_file
            app_version.app_version_files.create!(
              app_file: app_file,
              action: file_info[:action]
            )
          end
        end
      end

      # Generate the display name based on changes
      app_version.generate_display_name!

      @version_created = true

      # Link the version to the current chat message
      if @current_message
        @current_message.update!(app_version: app_version)
        Rails.logger.info "[StreamingOrchestrator] Linked message #{@current_message.id} to version #{version_number}"
      end

      Rails.logger.info "[StreamingOrchestrator] Created version #{version_number}"
      app_version
    end

    def next_version_number(app)
      last_version = app.app_versions.order(created_at: :desc).first
      if last_version
        parts = last_version.version_number.split(".")
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join(".")
      else
        "1.0.0"
      end
    end

    def save_file(path, content)
      # Detect file type from extension
      file_type = detect_file_type(path)

      # Find or create the file
      file = app.app_files.find_or_initialize_by(path: path)
      was_new = file.new_record?
      file.team = app.team if was_new
      file.content = content
      file.file_type = file_type
      file.size_bytes = content.bytesize
      file.is_entry_point = (path == "index.html")

      if file.save
        Rails.logger.info "[StreamingOrchestrator] Saved file: #{path}"

        # Track the file operation
        @files_processed << {
          path: path,
          action: was_new ? "created" : "updated",
          file_type: file_type
        }

        # Broadcast file update event
        broadcast_file_update(file)
      else
        Rails.logger.error "[StreamingOrchestrator] Failed to save #{path}: #{file.errors.full_messages.join(", ")}"
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

    def normalize_file_data(file_data)
      # Handle different field names from different models
      normalized = {
        path: file_data[:path] || file_data[:file_path],
        content: file_data[:content] || file_data[:new_content],
        description: file_data[:description] || file_data[:change_description]
      }

      Rails.logger.debug "[StreamingOrchestrator] 🔄 Normalized file data:"
      Rails.logger.debug "[StreamingOrchestrator] 🔄 Path: #{normalized[:path]}"
      Rails.logger.debug "[StreamingOrchestrator] 🔄 Content present: #{!normalized[:content].blank?}"
      Rails.logger.debug "[StreamingOrchestrator] 🔄 Content length: #{normalized[:content]&.length || "nil"}"

      normalized
    end

    def create_assistant_message(content, status)
      @current_message = app.app_chat_messages.create!(
        role: "assistant",
        content: content,
        status: status
      )
      broadcast_message_update(@current_message)
      @current_message
    end

    def update_message(content, status = nil)
      return unless @current_message

      # Accumulate content instead of replacing
      if content.start_with?("✅", "📝", "⚡")
        # Add as a new line to accumulated content
        @accumulated_content += "\n" unless @accumulated_content.empty?
        @accumulated_content += content
      else
        # Replace current status line
        lines = @accumulated_content.split("\n")
        if lines.any? && lines.last.start_with?("🔍", "📋", "🤔")
          lines[-1] = content
          @accumulated_content = lines.join("\n")
        else
          @accumulated_content += "\n" unless @accumulated_content.empty?
          @accumulated_content += content
        end
      end

      @current_message.content = @accumulated_content
      @current_message.status = status if status
      @current_message.save!

      # Use cable_ready for efficient updates
      broadcast_message_content_update(@current_message)
    end

    def broadcast_message_update(message)
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        partial: "account/app_editors/chat_message",
        locals: {message: message}
      )
    end

    def broadcast_message_content_update(message)
      # Use Turbo Stream to update just the content
      Turbo::StreamsChannel.broadcast_action_to(
        "app_#{app.id}_chat",
        action: :replace,
        target: "message_content_#{message.id}",
        html: render_message_content(message)
      )
    end

    def broadcast_file_update(file)
      # Broadcast file update for file tree refresh
      Turbo::StreamsChannel.broadcast_action_to(
        "app_#{app.id}_files",
        action: :replace,
        target: "file_#{file.id}",
        html: render_file_item(file)
      )
    end

    def render_message_content(message)
      ApplicationController.render(
        partial: "account/app_editors/chat_message_content",
        locals: {message: message}
      )
    end

    def render_file_item(file)
      ApplicationController.render(
        partial: "account/app_editors/file_tree_item",
        locals: {file: file, app: app}
      )
    end

    def create_error_response(error_message)
      create_assistant_message(
        "❌ An error occurred: #{error_message}\n\nPlease try again.",
        "failed"
      )

      enable_chat_form
    end

    def enable_chat_form
      # Broadcast event to re-enable the chat form
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: "<script>document.dispatchEvent(new CustomEvent('chat:complete'))</script>"
      )
    end

    def broadcast_version_progress(message)
      # Broadcast live progress update to the version progress card
      script = <<~JS
        <script>
          document.dispatchEvent(new CustomEvent('version:progress:#{@current_message.id}', {
            detail: { 
              status: '#{@current_message.status}',
              title: '#{message.gsub("'", "\\'")}' 
            }
          }));
        </script>
      JS

      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: script
      )
    end

    def broadcast_file_progress(file_path, status, lines_changed = nil)
      # Broadcast file-specific progress update
      script = <<~JS
        <script>
          document.dispatchEvent(new CustomEvent('version:file:#{@current_message.id}', {
            detail: {
              file_path: '#{file_path}',
              status: '#{status}',
              #{lines_changed ? "lines_changed: #{lines_changed}," : ""}
            }
          }));
        </script>
      JS

      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: script
      )
    end

    def broadcast_version_complete(version)
      # Generate display name for the version
      display_name = version.formatted_display_name

      # Broadcast version completion
      script = <<~JS
        <script>
          document.dispatchEvent(new CustomEvent('version:complete:#{@current_message.id}', {
            detail: {
              version_id: '#{version.id}',
              version_number: '#{version.version_number}',
              display_name: '#{display_name.gsub("'", "\\'")}'
            }
          }));
        </script>
      JS

      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: script
      )
    end
  end
end
