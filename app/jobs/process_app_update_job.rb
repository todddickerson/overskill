class ProcessAppUpdateJob < ApplicationJob
  include ActionView::RecordIdentifier
  queue_as :ai_generation

  def perform(chat_message)
    app = chat_message.app
    @user = chat_message.user  # Store user for version creation

    # Step 1: Planning phase
    chat_message.update!(status: "planning")
    broadcast_status_update(chat_message)

    # Get current files
    current_files = app.app_files.map do |file|
      {
        path: file.path,
        type: file.file_type,
        size_bytes: file.size_bytes
      }
    end

    # Build app context
    app_context = {
      name: app.name,
      type: app.app_type,
      framework: app.framework
    }

    # Step 2: Executing phase
    chat_message.update!(status: "executing")
    broadcast_status_update(chat_message)

    # Call AI to process the update
    client = Ai::OpenRouterClient.new
    response = client.update_app(chat_message.content, current_files, app_context)

    if response[:success]
      # Parse the response
      result = parse_update_response(response[:content])

      if result
        # Validate the generated code before applying
        validation = Ai::CodeValidatorService.validate_files(result[:files])
        
        if validation[:valid]
          # Apply the changes
          apply_changes(app, result)
        else
          # Log validation errors
          Rails.logger.error "[ProcessAppUpdate] Code validation failed:"
          validation[:errors].each do |error|
            Rails.logger.error "  #{error[:file]}: #{error[:message]}"
          end
          
          # Try to fix common issues and retry
          fixed_files = result[:files].map do |file|
            file[:content] = Ai::CodeValidatorService.fix_common_issues(file[:content], file[:type])
            file
          end
          
          # Validate again
          retry_validation = Ai::CodeValidatorService.validate_files(fixed_files)
          if retry_validation[:valid]
            result[:files] = fixed_files
            apply_changes(app, result)
          else
            # Create error response with fix option
            handle_validation_error(chat_message, validation[:errors], result)
            return
          end
        end

        # Create assistant response
        @assistant_message = app.app_chat_messages.create!(
          role: "assistant",
          content: format_assistant_response(result),
          status: "completed"
        )

        # Update original message status
        chat_message.update!(status: "completed", response: result[:changes][:summary])

        # Broadcast completion
        broadcast_completion(chat_message, @assistant_message)
      else
        handle_error(chat_message, "Failed to parse AI response")
      end
    else
      handle_error(chat_message, response[:error] || "AI request failed")
    end
  rescue => e
    handle_error(chat_message, e.message)
  end

  private

  def parse_update_response(content)
    JSON.parse(content, symbolize_names: true)
  rescue JSON::ParserError => e
    Rails.logger.error "[ProcessAppUpdate] Failed to parse response: #{e.message}"

    # Try to extract JSON from markdown
    json_match = content.match(/```json\n(.*?)\n```/m)
    if json_match
      content = json_match[1]
      retry
    end

    nil
  end

  def apply_changes(app, result)
    result[:files].each do |file_data|
      case file_data[:action]
      when "create"
        app.app_files.create!(
          team: app.team,
          path: file_data[:path],
          content: file_data[:content],
          file_type: file_data[:type] || determine_file_type(file_data[:path]),
          size_bytes: file_data[:content].bytesize
        )
      when "update"
        file = app.app_files.find_by(path: file_data[:path])
        if file
          file.update!(
            content: file_data[:content],
            size_bytes: file_data[:content].bytesize
          )
        else
          # Create if doesn't exist
          app.app_files.create!(
            team: app.team,
            path: file_data[:path],
            content: file_data[:content],
            file_type: file_data[:type] || determine_file_type(file_data[:path]),
            size_bytes: file_data[:content].bytesize
          )
        end
      when "delete"
        app.app_files.find_by(path: file_data[:path])&.destroy
      end
    end

    # Create a new version if files were modified
    app_version = nil
    if result[:files].any?
      app_version = app.app_versions.create!(
        team: app.team,
        user: @user,
        version_number: next_version_number(app),
        changelog: result[:changes][:summary],
        changed_files: result[:changes][:files_modified]&.join(", ")
      )
      
      # Create version file snapshots for all current files
      create_version_file_snapshots(app_version, result[:files])
      
      # Update preview worker with latest changes
      UpdatePreviewJob.perform_later(app.id)
    end
    
    # Link the AI response to this version
    if app_version && @assistant_message
      @assistant_message.update!(app_version: app_version)
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

  def format_assistant_response(result)
    response = "I've updated your app! Here's what changed:\n\n"
    response += "**#{result[:changes][:summary]}**\n\n"

    if result[:changes][:files_modified]&.any?
      response += "Files modified:\n"
      result[:changes][:files_modified].each do |file|
        response += "- #{file}\n"
      end
      response += "\n"
    end

    if result[:changes][:files_added]&.any?
      response += "Files added:\n"
      result[:changes][:files_added].each do |file|
        response += "- #{file}\n"
      end
      response += "\n"
    end

    if result[:testing_notes]
      response += "**Testing notes:** #{result[:testing_notes]}\n\n"
    end

    # Add bug detection and suggestions
    bugs_detected = detect_potential_bugs(result)
    suggestions = generate_suggestions(result, bugs_detected)
    
    if bugs_detected.any? || suggestions.any?
      response += "## What's next?\n\n"
      
      if bugs_detected.any?
        response += "⚠️ **Potential issues detected:**\n"
        bugs_detected.each do |bug|
          response += "- #{bug[:message]}\n"
        end
        response += "\n"
      end
      
      if suggestions.any?
        response += "**Quick actions:**\n"
        suggestions.each do |suggestion|
          response += "[#{suggestion[:label]}]: #{suggestion[:prompt]}\n"
        end
      end
    end

    response
  end

  def detect_potential_bugs(result)
    bugs = []
    
    # Check for common React issues
    result[:files].each do |file|
      if file[:type] == "javascript" && file[:content]
        content = file[:content]
        
        # Check for undefined state/props access
        if content.match(/props\.\w+\.length/) && !content.match(/props\.\w+\s*&&\s*props\.\w+\.length/)
          bugs << { 
            message: "Potential undefined error: Accessing .length without checking if prop exists",
            file: file[:path]
          }
        end
        
        # Check for missing key props in map
        if content.match(/\.map\s*\([^)]+\)\s*=>\s*React\.createElement/) && !content.match(/key\s*:/)
          bugs << {
            message: "Missing 'key' prop in list rendering",
            file: file[:path]
          }
        end
        
        # Check for useState without proper initialization
        if content.match(/useState\(\)/) 
          bugs << {
            message: "useState called without initial value",
            file: file[:path]
          }
        end
      end
      
      # Check for missing error handling
      if file[:content]&.match(/fetch\(|axios\.|\.then\(/) && !file[:content].match(/\.catch\(|try\s*{/)
        bugs << {
          message: "API calls without error handling",
          file: file[:path]
        }
      end
    end
    
    bugs
  end
  
  def generate_suggestions(result, bugs_detected)
    suggestions = []
    
    # Auto-fix suggestions for detected bugs
    if bugs_detected.any? { |bug| bug[:message].include?("undefined error") }
      suggestions << {
        label: "🔧 Fix undefined errors",
        prompt: "Add proper null checks and default values to prevent undefined errors"
      }
    end
    
    # General improvement suggestions based on files
    has_styles = result[:files].any? { |f| f[:type] == "css" }
    has_js = result[:files].any? { |f| f[:type] == "javascript" }
    
    if has_js && !has_styles
      suggestions << {
        label: "🎨 Add styling",
        prompt: "Create a beautiful UI with modern CSS styling and animations"
      }
    end
    
    if has_js
      suggestions << {
        label: "♻️ Refactor code",
        prompt: "Refactor the code to be more maintainable and follow best practices"
      }
      
      suggestions << {
        label: "🧪 Add error handling",
        prompt: "Add comprehensive error handling and user-friendly error messages"
      }
      
      suggestions << {
        label: "📱 Make responsive",
        prompt: "Make the app fully responsive for mobile and tablet devices"
      }
    end
    
    # Framework-specific suggestions
    if result[:files].any? { |f| f[:content]&.include?("React.createElement") }
      suggestions << {
        label: "🔄 Add loading states",
        prompt: "Add loading states and skeleton screens for better UX"
      }
      
      suggestions << {
        label: "⚡ Optimize performance",
        prompt: "Optimize React performance with memo, useCallback, and lazy loading"
      }
    end
    
    suggestions
  end

  def handle_error(chat_message, error_message)
    Rails.logger.error "[ProcessAppUpdate] Error: #{error_message}"

    chat_message.update!(
      status: "failed",
      response: error_message
    )

    # Create error message
    error_response = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: "I encountered an error: #{error_message}\n\nPlease try rephrasing your request or be more specific.",
      status: "failed"
    )

    broadcast_error(chat_message, error_response)
  end

  def broadcast_status_update(chat_message)
    # Find the AI response message that was created
    ai_message = chat_message.app.app_chat_messages
      .where(role: "assistant")
      .where("created_at > ?", chat_message.created_at)
      .order(created_at: :asc)
      .first
    
    if ai_message
      # Update the existing AI message
      ai_message.update!(
        content: get_status_message(chat_message.status),
        status: chat_message.status
      )
      
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{chat_message.app_id}_chat",
        target: dom_id(ai_message),
        partial: "account/app_editors/chat_message",
        locals: {message: ai_message}
      )
    end
  end

  def get_status_message(status)
    case status
    when "planning"
      "Analyzing your request and planning the changes..."
    when "executing"
      "Implementing the changes to your app..."
    when "completed"
      "Changes completed successfully!"
    when "failed"
      "An error occurred while processing your request."
    else
      "Processing your request..."
    end
  end



  def broadcast_completion(user_message, assistant_message)
    # Find and update the AI message that was created initially
    ai_message = user_message.app.app_chat_messages
      .where(role: "assistant")
      .where("created_at > ?", user_message.created_at)
      .order(created_at: :asc)
      .first
    
    if ai_message && ai_message.id != assistant_message.id
      # Delete the placeholder AI message
      ai_message.destroy
    end
    
    # Broadcast the final assistant message
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{user_message.app_id}_chat",
      target: "chat_messages",
      partial: "account/app_editors/chat_message",
      locals: {message: assistant_message}
    )

    # Refresh the preview
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{user_message.app_id}_chat",
      target: "preview_frame",
      partial: "account/app_editors/preview_frame",
      locals: {app: user_message.app}
    )
  end

  def broadcast_error(user_message, error_message)
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{user_message.app_id}_chat",
      target: "processing_#{user_message.id}",
      partial: "account/app_editors/chat_message",
      locals: {message: error_message}
    )
  end
  
  def create_version_file_snapshots(app_version, changed_files)
    app = app_version.app
    
    # Create snapshots for all current files in the app
    app.app_files.each do |app_file|
      # Determine the action based on whether this file was changed
      file_change = changed_files.find { |f| f[:path] == app_file.path }
      action = file_change ? file_change[:action] : 'unchanged'
      
      # Create version file snapshot
      app_version.app_version_files.create!(
        app_file: app_file,
        content: app_file.content,
        action: action == 'unchanged' ? 'update' : action
      )
    end
  end

  def handle_validation_error(chat_message, errors, result)
    # Create a detailed error message
    error_details = errors.map { |e| "• #{e[:file]}: #{e[:message]}" }.join("\n")
    
    error_message = <<~MESSAGE
      I encountered some issues with the generated code:
      
      #{error_details}
      
      These issues prevent the code from running properly in the browser. Would you like me to:
      
      1. **Fix automatically** - I'll update the code to be browser-compatible
      2. **Show the code anyway** - You can review and fix it manually
      
      What would you prefer?
    MESSAGE
    
    # Create assistant response with error details
    assistant_message = chat_message.app.app_chat_messages.create!(
      role: "assistant",
      content: error_message,
      status: "validation_error",
      metadata: {
        validation_errors: errors,
        original_result: result
      }
    )
    
    # Update original message status
    chat_message.update!(status: "validation_error", response: "Code validation failed")
    
    # Broadcast error response
    broadcast_error(chat_message, assistant_message)
  end
end
