class ProcessAppUpdateJob < ApplicationJob
  queue_as :ai_generation

  def perform(chat_message)
    app = chat_message.app
    @user = chat_message.user  # Store user for version creation

    # Mark as processing
    chat_message.update!(status: "processing")

    # Broadcast processing state
    broadcast_processing(chat_message)

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

    # Call AI to process the update
    client = Ai::OpenRouterClient.new
    response = client.update_app(chat_message.content, current_files, app_context)

    if response[:success]
      # Parse the response
      result = parse_update_response(response[:content])

      if result
        # Apply the changes
        apply_changes(app, result)

        # Create assistant response
        assistant_message = app.app_chat_messages.create!(
          role: "assistant",
          content: format_assistant_response(result),
          status: "completed"
        )

        # Update original message status
        chat_message.update!(status: "completed", response: result[:changes][:summary])

        # Broadcast completion
        broadcast_completion(chat_message, assistant_message)
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
    if result[:files].any?
      app.app_versions.create!(
        team: app.team,
        user: @user,
        version_number: next_version_number(app),
        changelog: result[:changes][:summary],
        changed_files: result[:changes][:files_modified]&.join(", ")
      )
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
      response += "**Testing notes:** #{result[:testing_notes]}"
    end

    response
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

  def broadcast_processing(chat_message)
    Turbo::StreamsChannel.broadcast_append_to(
      "app_#{chat_message.app_id}_chat",
      target: "chat_messages",
      html: <<~HTML
        <div id="processing_#{chat_message.id}" class="ml-8">
          <div class="flex items-start space-x-2">
            <div class="w-8 h-8 bg-primary-600 rounded-lg flex items-center justify-center flex-shrink-0">
              <i class="fas fa-robot text-white text-sm"></i>
            </div>
            <div class="flex-1 bg-gray-750 rounded-lg px-4 py-2">
              <div class="flex items-center text-sm text-gray-400">
                <div class="animate-spin rounded-full h-3 w-3 border-b-2 border-primary-500 mr-2"></div>
                Processing your request...
              </div>
            </div>
          </div>
        </div>
      HTML
    )
  end

  def broadcast_completion(user_message, assistant_message)
    # Broadcast to chat
    Turbo::StreamsChannel.broadcast_replace_to(
      "app_#{user_message.app_id}_chat",
      target: "processing_#{user_message.id}",
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
end
