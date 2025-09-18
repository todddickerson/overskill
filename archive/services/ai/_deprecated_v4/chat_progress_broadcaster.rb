module Ai
  class ChatProgressBroadcaster
    def initialize(app, user, initial_message)
      @app = app
      @user = user
      @initial_message = initial_message
      @start_time = Time.current
      @current_step = 0
      @total_steps = 6 # Adjust based on generation phases
      @files_created = []
      @current_message = nil
    end

    def broadcast_start(plan_summary)
      @current_message = create_assistant_message(
        "🚀 I'll create #{plan_summary}! Here's my plan:\n\n" \
        "1. 📋 Set up project foundation (package.json, configs)\n" \
        "2. 🧩 Generate core components\n" \
        "3. ✨ Add requested features\n" \
        "4. 🎨 Integrate UI components\n" \
        "5. 🔨 Build with npm + Vite\n" \
        "6. 🚀 Deploy to preview\n\n" \
        "⏱️ Starting now..."
      )

      broadcast_to_frontend({
        type: "generation_started",
        message_id: @current_message.id,
        plan: plan_summary
      })
    end

    def broadcast_step_start(step_name, description)
      @current_step += 1

      append_to_message(
        "\n\n**Step #{@current_step}/#{@total_steps}: #{step_name}**\n" \
        "🔄 #{description}..."
      )

      broadcast_to_frontend({
        type: "step_started",
        step: @current_step,
        total: @total_steps,
        name: step_name,
        description: description
      })
    end

    def broadcast_step_complete(step_name, details = {})
      elapsed = (Time.current - @start_time).round(1)

      append_to_message(
        " ✅ Done (#{elapsed}s)\n" +
        format_step_details(details)
      )

      broadcast_to_frontend({
        type: "step_completed",
        step: @current_step,
        name: step_name,
        elapsed: elapsed,
        details: details
      })
    end

    def broadcast_file_created(file_path, file_size, content_preview = nil)
      @files_created << {path: file_path, size: file_size, created_at: Time.current}

      size_display = format_file_size(file_size)
      preview = content_preview ? "\n```#{get_file_extension(file_path)}\n#{content_preview.truncate(100)}\n```" : ""

      append_to_message("   📄 Created `#{file_path}` (#{size_display})#{preview}")

      broadcast_to_frontend({
        type: "file_created",
        path: file_path,
        size: file_size,
        preview: content_preview&.truncate(200),
        total_files: @files_created.count
      })
    end

    def broadcast_build_progress(stage, progress = nil)
      case stage
      when :npm_install
        append_to_message("\n   📦 Installing dependencies...")
      when :vite_build
        append_to_message("\n   ⚡ Building with Vite...")
      when :optimization
        append_to_message("\n   🎯 Optimizing for deployment...")
      when :complete
        append_to_message(" ✅")
      end

      if progress
        broadcast_to_frontend({
          type: "build_progress",
          stage: stage,
          progress: progress
        })
      end
    end

    def broadcast_error(error_message, recoverable = true)
      if recoverable
        append_to_message(
          "\n⚠️ Issue encountered: #{error_message}\n" \
          "🔄 Attempting to resolve..."
        )
      else
        append_to_message(
          "\n❌ Generation failed: #{error_message}\n" \
          "💡 You can try again or ask me to fix specific issues."
        )
      end

      broadcast_to_frontend({
        type: "error",
        message: error_message,
        recoverable: recoverable
      })
    end

    def broadcast_completion(preview_url = nil, build_stats = {})
      elapsed = (Time.current - @start_time).round(1)

      completion_message = [
        "\n\n🎉 **Your app is ready!**",
        "⏱️ Generated in #{elapsed}s",
        "📁 #{@files_created.count} files created",
        build_stats[:size] ? "📦 Built size: #{format_file_size(build_stats[:size])}" : nil,
        preview_url ? "🔗 **Preview**: #{preview_url}" : nil,
        "",
        "💬 **What's next?**",
        "• Ask me to modify your app: \"Add a delete button to each todo\"",
        "• Change styling: \"Make the buttons blue\"",
        "• Add features: \"Add user authentication\"",
        "• Deploy to production: \"Deploy this to my custom domain\""
      ].compact.join("\n")

      append_to_message(completion_message)

      # Update app with preview URL if provided
      if preview_url
        @app.update!(preview_url: preview_url, status: "generated")
      end

      broadcast_to_frontend({
        type: "generation_completed",
        elapsed: elapsed,
        files_count: @files_created.count,
        preview_url: preview_url,
        build_stats: build_stats
      })
    end

    def broadcast_chat_ready
      create_assistant_message(
        "✨ I'm ready to help you improve your app!\n\n" \
        "Try asking me things like:\n" \
        "• \"Add user authentication\"\n" \
        "• \"Change the todo styling to be more modern\"\n" \
        "• \"Add a search feature to filter todos\"\n" \
        "• \"Deploy this to production\"\n\n" \
        "What would you like to work on?"
      )

      broadcast_to_frontend({
        type: "chat_ready"
      })
    end

    private

    def create_assistant_message(content)
      AppChatMessage.create!(
        app: @app,
        user: @user,
        role: "assistant",
        content: content,
        metadata: {
          generation_session: true,
          created_at: Time.current.iso8601
        }.to_json
      )
    end

    def append_to_message(additional_content)
      @current_message&.update!(
        content: @current_message.content + additional_content,
        updated_at: Time.current
      )
    end

    def format_step_details(details)
      return "" if details.empty?

      result = []
      details.each do |key, value|
        case key
        when :files_count
          result << "   📁 #{value} files"
        when :components
          result << "   🧩 Components: #{Array(value).join(", ")}"
        when :build_time
          result << "   ⏱️ #{value}ms"
        when :size
          result << "   📦 #{format_file_size(value)}"
        end
      end
      result.any? ? "\n#{result.join("\n")}" : ""
    end

    def format_file_size(bytes)
      return "0B" if bytes.nil? || bytes <= 0
      return "#{bytes}B" if bytes < 1024
      return "#{(bytes / 1024.0).round(1)}KB" if bytes < 1024 * 1024
      "#{(bytes / (1024.0 * 1024)).round(1)}MB"
    end

    def get_file_extension(file_path)
      ext = ::File.extname(file_path).downcase
      case ext
      when ".tsx", ".ts" then "typescript"
      when ".js", ".jsx" then "javascript"
      when ".json" then "json"
      when ".css" then "css"
      when ".html" then "html"
      else "text"
      end
    end

    def broadcast_to_frontend(data)
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        data.merge({
          app_id: @app.id,
          timestamp: Time.current.iso8601
        })
      )
    end
  end
end
