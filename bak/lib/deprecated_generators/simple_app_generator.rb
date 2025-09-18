module Ai
  # SimpleAppGenerator - Direct, working app generation without the complexity
  # This actually works, unlike UnifiedAiCoordinator which hangs
  class SimpleAppGenerator
    attr_reader :app, :message, :client

    def initialize(app, message)
      @app = app
      @message = message
      @client = OpenRouterClient.new
    end

    def generate!
      Rails.logger.info "[SimpleGenerator] Starting generation for app ##{app.id}"

      # Create assistant message for progress
      assistant_message = create_assistant_message

      begin
        # Step 1: Generate with AI
        update_progress(assistant_message, "🤖 Calling AI to generate your app...", 20)
        ai_result = call_ai_for_generation

        if ai_result[:success]
          # Step 2: Process files
          update_progress(assistant_message, "📁 Creating app files...", 50)
          files_created = process_ai_result(ai_result)

          # Step 3: Create version
          update_progress(assistant_message, "📦 Creating version...", 80)
          create_version

          # Step 4: Deploy preview
          update_progress(assistant_message, "🚀 Deploying preview...", 90)
          queue_deployment

          # Success!
          finalize_success(assistant_message, files_created)
        else
          finalize_error(assistant_message, ai_result[:error])
        end
      rescue => e
        Rails.logger.error "[SimpleGenerator] Error: #{e.message}"
        finalize_error(assistant_message, e.message)
        raise
      end
    end

    private

    def create_assistant_message
      app.app_chat_messages.create!(
        role: "assistant",
        content: "Starting app generation...",
        status: "generating"
      )
    end

    def update_progress(message, text, percentage)
      bar_length = 20
      filled = (bar_length * percentage / 100.0).round
      empty = bar_length - filled
      progress_bar = "█" * filled + "░" * empty

      content = <<~CONTENT
        #{text}
        
        `#{progress_bar}` #{percentage}%
      CONTENT

      message.update!(content: content)
      broadcast_update(message)
    end

    def call_ai_for_generation
      prompt = build_generation_prompt

      Rails.logger.info "[SimpleGenerator] Calling AI with enhanced prompt"

      # Use the working generate_app method with timeout
      Timeout.timeout(45) do
        @client.generate_app(prompt, framework: "react", app_type: "saas")
      end
    rescue Timeout::Error
      {success: false, error: "AI generation timed out"}
    end

    def build_generation_prompt
      # Include standards if file exists
      standards = begin
        File.read(Rails.root.join("AI_APP_STANDARDS.md"))
      rescue
        ""
      end

      <<~PROMPT
        #{message.content}
        
        Create a complete, production-ready SaaS application with:
        
        TECH STACK (REQUIRED):
        - React 18 with TypeScript
        - Tailwind CSS for styling
        - Vite for bundling
        - Cloudflare Workers compatible
        - Supabase for backend (database + auth)
        - Stripe for payments
        
        MUST INCLUDE:
        - Complete file structure
        - Error handling on all API calls
        - Loading states for async operations
        - Responsive mobile-first design
        - Dark mode support
        - Accessibility features
        - Security best practices
        
        #{standards}
        
        Generate all necessary files for a working application.
      PROMPT
    end

    def process_ai_result(result)
      return 0 unless result[:tool_calls]&.any?

      tool_call = result[:tool_calls].first
      return 0 unless tool_call

      args = tool_call.dig("function", "arguments")
      data = args.is_a?(String) ? JSON.parse(args) : args

      files_created = 0

      data["files"]&.each do |file_info|
        app.app_files.create!(
          team: app.team,
          path: file_info["path"],
          content: file_info["content"],
          file_type: detect_file_type(file_info["path"]),
          size_bytes: file_info["content"].bytesize
        )
        files_created += 1

        Rails.logger.info "[SimpleGenerator] Created file: #{file_info["path"]}"
      end

      # Update app metadata if provided
      if data["app"]
        app.update!(
          description: data["app"]["description"],
          status: "generated"
        )
      end

      files_created
    rescue => e
      Rails.logger.error "[SimpleGenerator] Error processing files: #{e.message}"
      0
    end

    def create_version
      app.app_versions.create!(
        team: app.team,
        user: message.user,
        version_number: next_version_number,
        changelog: "Initial generation from: #{message.content[0..100]}",
        deployed: false,
        files_snapshot: app.app_files.map { |f|
          {path: f.path, content: f.content, file_type: f.file_type}
        }.to_json
      )
    end

    def next_version_number
      last = app.app_versions.order(:created_at).last
      last ? increment_version(last.version_number) : "1.0.0"
    end

    def increment_version(version)
      parts = version.split(".")
      parts[2] = (parts[2].to_i + 1).to_s
      parts.join(".")
    end

    def queue_deployment
      UpdatePreviewJob.perform_later(app.id)
    end

    def finalize_success(message, file_count)
      app.update!(status: "generated")

      message.update!(
        content: "✅ Successfully generated your app!\n\n" \
                "📁 #{file_count} files created\n" \
                "🚀 Preview deploying...\n\n" \
                "You can now edit files or request changes.",
        status: "completed"
      )

      broadcast_update(message)

      Rails.logger.info "[SimpleGenerator] Successfully generated app ##{app.id}"
    end

    def finalize_error(message, error)
      app.update!(status: "failed")

      message.update!(
        content: "❌ Generation failed\n\n" \
                "Error: #{error}\n\n" \
                "Please try again or contact support.",
        status: "failed"
      )

      broadcast_update(message)
    end

    def broadcast_update(message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{app.id}_chat",
        target: "chat_message_#{message.id}",
        partial: "account/app_editors/chat_message",
        locals: {message: message}
      )
    end

    def detect_file_type(path)
      ext = File.extname(path).delete(".")
      case ext
      when "ts", "tsx" then "typescript"
      when "js", "jsx" then "javascript"
      when "html" then "html"
      when "css" then "css"
      when "json" then "json"
      when "md" then "markdown"
      else "text"
      end
    end
  end
end
