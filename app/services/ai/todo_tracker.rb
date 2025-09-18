module Ai
  # TodoTracker - Claude Code-style task management for AI operations
  # Allows AI to track its own progress through complex operations
  class TodoTracker
    attr_reader :todos, :app, :message

    def initialize(app, message = nil)
      @app = app
      @message = message
      @todos = []
      @completed_count = 0
      @start_time = Time.current
    end

    # Add a new todo item
    def add(description, metadata = {})
      todo = {
        id: SecureRandom.hex(4),
        description: description,
        status: "pending",
        metadata: metadata,
        created_at: Time.current
      }
      @todos << todo
      broadcast_todos
      todo
    end

    # Mark a todo as in progress
    def start(todo_id)
      todo = find_todo(todo_id)
      return unless todo && todo[:status] == "pending"

      todo[:status] = "in_progress"
      todo[:started_at] = Time.current
      broadcast_todos
      log_progress("Started: #{todo[:description]}")
    end

    # Mark a todo as completed
    def complete(todo_id, result = nil)
      todo = find_todo(todo_id)
      return unless todo && todo[:status] != "completed"

      todo[:status] = "completed"
      todo[:completed_at] = Time.current
      todo[:result] = result if result
      todo[:duration] = todo[:completed_at] - (todo[:started_at] || todo[:created_at])

      @completed_count += 1
      broadcast_todos
      log_progress("✓ Completed: #{todo[:description]} (#{todo[:duration].round(1)}s)")
    end

    # Mark a todo as failed
    def fail(todo_id, error)
      todo = find_todo(todo_id)
      return unless todo

      todo[:status] = "failed"
      todo[:failed_at] = Time.current
      todo[:error] = error
      broadcast_todos
      log_progress("✗ Failed: #{todo[:description]} - #{error}")
    end

    # Get current progress percentage
    def progress_percentage
      return 0 if @todos.empty?
      (@completed_count.to_f / @todos.size * 100).round
    end

    # Get a summary of the current state
    def summary
      {
        total: @todos.size,
        completed: @todos.count { |t| t[:status] == "completed" },
        in_progress: @todos.count { |t| t[:status] == "in_progress" },
        pending: @todos.count { |t| t[:status] == "pending" },
        failed: @todos.count { |t| t[:status] == "failed" },
        progress_percentage: progress_percentage,
        elapsed_time: Time.current - @start_time
      }
    end

    # Generate a markdown summary for display
    def to_markdown
      lines = ["### 📋 Task Progress\n"]

      @todos.each do |todo|
        icon = case todo[:status]
        when "completed" then "✅"
        when "in_progress" then "🔄"
        when "failed" then "❌"
        else "⏳"
        end

        lines << "#{icon} #{todo[:description]}"

        if todo[:status] == "failed" && todo[:error]
          lines << "   └─ Error: #{todo[:error]}"
        elsif todo[:status] == "completed" && todo[:duration]
          lines << "   └─ Completed in #{todo[:duration].round(1)}s"
        end
      end

      lines << "\n**Progress: #{progress_percentage}%**"
      lines.join("\n")
    end

    # Plan todos from AI analysis
    def plan_from_analysis(analysis)
      # AI can provide structured tasks
      analysis["tasks"]&.each do |task|
        add(task["description"], task["metadata"] || {})
      end

      # Or extract from other fields
      analysis["files_to_modify"]&.each do |file|
        add("Modify #{file}", {type: "file_modification", path: file})
      end

      analysis["files_to_create"]&.each do |file|
        add("Create #{file}", {type: "file_creation", path: file})
      end

      broadcast_todos
    end

    private

    def find_todo(todo_id)
      @todos.find { |t| t[:id] == todo_id }
    end

    def log_progress(message)
      Rails.logger.info "[TodoTracker] #{message}"
    end

    def broadcast_todos
      return unless @message

      # Don't modify user messages!
      return if @message.role == "user"

      # Find or create an assistant message for progress
      assistant_message = find_or_create_assistant_message

      # Update assistant message with todo list
      todo_content = to_markdown

      assistant_message.content = if assistant_message.content.include?("### 📋 Task Progress")
        # Update existing todo section
        assistant_message.content.gsub(
          /### 📋 Task Progress.*?(?=\n{2,}|\z)/m,
          todo_content
        )
      else
        # Append todo section
        assistant_message.content + "\n\n" + todo_content
      end

      assistant_message.save!
      broadcast_message_update_for(assistant_message)
    end

    def find_or_create_assistant_message
      # Find the latest assistant message or create one
      latest_assistant = @app.app_chat_messages
        .where(role: "assistant")
        .where("created_at > ?", @message.created_at)
        .order(created_at: :desc)
        .first

      latest_assistant || @app.app_chat_messages.create!(
        role: "assistant",
        content: "Processing your request...",
        status: "executing"
      )
    end

    def broadcast_message_update_for(message)
      return unless message

      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "message_content_#{message.id}",
        partial: "account/app_editors/chat_message_content",
        locals: {message: message}
      )
    end
  end
end
