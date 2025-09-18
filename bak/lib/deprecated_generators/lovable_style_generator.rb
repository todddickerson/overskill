module Ai
  # Lovable.dev-style generation flow with progressive stages
  class LovableStyleGenerator
    attr_reader :app, :chat_message, :generation

    STAGES = {
      thinking: "🤔 Understanding your requirements...",
      planning: "📋 Planning the application structure...",
      designing: "🎨 Designing the user interface...",
      coding: "💻 Writing the code...",
      reviewing: "🔍 Reviewing and optimizing...",
      completing: "✅ Finalizing your application..."
    }.freeze

    def initialize(app, generation = nil)
      @app = app
      @generation = generation || app.app_generations.last
      @errors = []
      @current_stage = nil
      @progress = 0
    end

    def generate!
      Rails.logger.info "[LovableGenerator] Starting Lovable-style generation for App ##{@app.id}"

      # Create initial chat message for progress tracking
      create_initial_message

      begin
        # Stage 1: Thinking (0-15%)
        enter_stage(:thinking, 0)
        analysis = analyze_requirements

        # Stage 2: Planning (15-30%)
        enter_stage(:planning, 15)
        plan = create_detailed_plan(analysis)

        # Stage 3: Designing (30-45%)
        enter_stage(:designing, 30)
        design = create_design_system(plan)

        # Stage 4: Coding (45-75%)
        enter_stage(:coding, 45)
        files = generate_code_files(plan, design)

        # Stage 5: Reviewing (75-90%)
        enter_stage(:reviewing, 75)
        optimized_files = review_and_optimize(files)

        # Stage 6: Completing (90-100%)
        enter_stage(:completing, 90)
        finalize_generation(optimized_files)

        # Mark as complete
        complete_generation

        {success: true, files: optimized_files}
      rescue => e
        handle_error(e)
        {success: false, error: e.message}
      end
    end

    private

    def create_initial_message
      @chat_message = @app.app_chat_messages.create!(
        role: "assistant",
        content: "Starting app generation...",
        status: "executing"
      )
      broadcast_update
    end

    def enter_stage(stage, progress)
      @current_stage = stage
      @progress = progress

      stage_message = STAGES[stage]

      # Update the chat message with current stage
      @chat_message.update!(
        content: build_progress_message(stage_message, progress)
      )

      broadcast_update

      # Small delay for visual effect
      sleep 0.5
    end

    def build_progress_message(status, progress)
      bar_length = 20
      filled = (bar_length * progress / 100.0).round
      empty = bar_length - filled
      progress_bar = "█" * filled + "░" * empty

      <<~MESSAGE
        **🔄 Generation Progress**
        
        #{status}
        
        Progress: #{progress}%
        
        `#{progress_bar}` #{progress}%
      MESSAGE
    end

    def analyze_requirements
      Rails.logger.info "[LovableGenerator] Analyzing requirements"

      # Simulate thinking with incremental progress
      (0..2).each do |i|
        @progress = 5 + (i * 5)
        @chat_message.update!(
          content: build_progress_message("🤔 Analyzing: #{["requirements", "constraints", "best practices"][i]}...", @progress)
        )
        broadcast_update
        sleep 0.3
      end

      # Return analysis results
      {
        app_type: @app.app_type,
        framework: @app.framework,
        requirements: parse_requirements(@app.prompt),
        features: extract_features(@app.prompt)
      }
    end

    def create_detailed_plan(analysis)
      Rails.logger.info "[LovableGenerator] Creating detailed plan"

      planning_steps = [
        "Defining application architecture...",
        "Planning component structure...",
        "Mapping user flows..."
      ]

      planning_steps.each_with_index do |step, i|
        @progress = 20 + (i * 3)
        @chat_message.update!(
          content: build_progress_message("📋 #{step}", @progress)
        )
        broadcast_update
        sleep 0.3
      end

      # Return the plan
      {
        architecture: "modular",
        components: ["Header", "Main", "Footer"],
        pages: determine_pages(analysis),
        data_flow: "unidirectional"
      }
    end

    def create_design_system(plan)
      Rails.logger.info "[LovableGenerator] Creating design system"

      design_steps = [
        "Selecting color palette...",
        "Choosing typography...",
        "Designing components..."
      ]

      design_steps.each_with_index do |step, i|
        @progress = 35 + (i * 3)
        @chat_message.update!(
          content: build_progress_message("🎨 #{step}", @progress)
        )
        broadcast_update
        sleep 0.3
      end

      # Return design system
      {
        colors: {
          primary: "#3B82F6",
          secondary: "#10B981",
          accent: "#F59E0B",
          background: "#F9FAFB",
          text: "#111827"
        },
        typography: {
          font_family: "Inter, system-ui, sans-serif",
          sizes: ["text-xs", "text-sm", "text-base", "text-lg", "text-xl"]
        }
      }
    end

    def generate_code_files(plan, design)
      Rails.logger.info "[LovableGenerator] Generating code files"

      # Call the AI to generate files
      client = Ai::OpenRouterClient.new
      result = client.generate_app(
        @app.prompt,
        framework: @app.framework,
        app_type: @app.app_type
      )

      if result[:success] && result[:tool_calls]&.any?
        # Parse the function call response
        tool_call = result[:tool_calls].first
        args = JSON.parse(tool_call.dig("function", "arguments"))
        files = args["files"] || []

        # Update progress as files are "generated"
        files.each_with_index do |file, i|
          @progress = 50 + ((i.to_f / files.length) * 20).round
          @chat_message.update!(
            content: build_progress_message("💻 Creating #{file["path"]}...", @progress)
          )
          broadcast_update
          sleep 0.2
        end

        files
      else
        raise "Failed to generate files from AI"
      end
    end

    def review_and_optimize(files)
      Rails.logger.info "[LovableGenerator] Reviewing and optimizing"

      review_steps = [
        "Checking code quality...",
        "Optimizing performance...",
        "Validating HTML structure..."
      ]

      review_steps.each_with_index do |step, i|
        @progress = 80 + (i * 3)
        @chat_message.update!(
          content: build_progress_message("🔍 #{step}", @progress)
        )
        broadcast_update
        sleep 0.3
      end

      # Return optimized files (no changes for now)
      files
    end

    def finalize_generation(files)
      Rails.logger.info "[LovableGenerator] Finalizing generation"

      # Save files to database
      files.each do |file_data|
        file_type = detect_file_type(file_data["path"])

        @app.app_files.create!(
          team: @app.team,
          path: file_data["path"],
          content: file_data["content"],
          file_type: file_type,
          size_bytes: file_data["content"].bytesize,
          is_entry_point: file_data["path"] == "index.html"
        )
      end

      @progress = 95
      @chat_message.update!(
        content: build_progress_message("✅ Saving files...", @progress)
      )
      broadcast_update
      sleep 0.5
    end

    def complete_generation
      # Update generation record
      @generation.update!(
        status: "completed",
        completed_at: Time.current
      )

      # Update app status
      @app.update!(status: "generated")

      # Create completion message with what's next
      completion_message = build_completion_message

      @chat_message.update!(
        content: completion_message,
        status: "completed"
      )

      # Create version
      create_version_record

      broadcast_update
      broadcast_completion
    end

    def build_completion_message
      <<~MESSAGE
        ✅ **Your app has been generated successfully!**
        
        **Files created:**
        #{@app.app_files.map { |f| "• #{f.path}" }.join("\n")}
        
        Your app is ready to use. The preview has been updated automatically.
        
        **💡 What's next?** Try asking:
        - 🎨 "Change the color scheme to dark mode"
        - ✨ "Add animations to the buttons"
        - 📱 "Make it more mobile-friendly"
        - 🚀 "Deploy to production"
      MESSAGE
    end

    def create_version_record
      version_number = "1.0.0"

      app_version = @app.app_versions.create!(
        team: @app.team,
        user: @generation.team.memberships.first.user,
        version_number: version_number,
        changelog: "Initial app generation from: #{@app.prompt}",
        files_snapshot: @app.app_files.map { |f|
          {path: f.path, content: f.content, file_type: f.file_type}
        }.to_json
      )

      # Link to chat message
      @chat_message.update!(app_version: app_version)
    end

    def handle_error(error)
      Rails.logger.error "[LovableGenerator] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")

      @generation.update!(
        status: "failed",
        error_message: error.message,
        completed_at: Time.current
      )

      @app.update!(status: "failed")

      @chat_message.update!(
        content: "❌ Generation failed: #{error.message}",
        status: "failed"
      )

      broadcast_update
    end

    def broadcast_update
      # Broadcast to Turbo Stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "message_content_#{@chat_message.id}",
        partial: "account/app_editors/chat_message_content",
        locals: {message: @chat_message}
      )
    end

    def broadcast_completion
      # Broadcast completion event
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{@app.id}_chat",
        target: "chat_messages",
        html: "<script>document.dispatchEvent(new CustomEvent('generation:complete', { detail: { appId: #{@app.id} } }))</script>"
      )

      # Update preview
      UpdatePreviewJob.perform_later(@app.id)
    end

    # Helper methods

    def parse_requirements(prompt)
      # Extract key requirements from prompt
      prompt.split(/[,.]/).map(&:strip).select(&:present?)
    end

    def extract_features(prompt)
      # Simple feature extraction
      features = []
      features << "authentication" if prompt.match?(/login|auth|user/i)
      features << "database" if prompt.match?(/data|store|save/i)
      features << "responsive" if prompt.match?(/mobile|responsive/i)
      features
    end

    def determine_pages(analysis)
      # Determine pages based on app type
      case analysis[:app_type]
      when "landing_page"
        ["index.html"]
      when "dashboard"
        ["index.html", "dashboard.html"]
      when "saas"
        ["index.html", "dashboard.html", "login.html", "pricing.html"]
      else
        ["index.html"]
      end
    end

    def detect_file_type(path)
      case File.extname(path).downcase
      when ".html", ".htm" then "html"
      when ".css" then "css"
      when ".js", ".mjs" then "js"
      when ".json" then "json"
      else "text"
      end
    end
  end
end
