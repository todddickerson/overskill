module Ai
  # Enhanced AI-powered app generator with Claude 4 and environment variable support
  class EnhancedAppGenerator
    include ActionCable::Channel::Broadcasting
    
    attr_reader :app, :generation, :chat_message, :client
    
    # Lovable.dev-style generation stages
    GENERATION_STAGES = {
      understanding: { icon: "🤔", message: "Understanding your vision...", progress: 0..10 },
      planning: { icon: "📋", message: "Planning the architecture...", progress: 10..25 },
      designing: { icon: "🎨", message: "Designing the interface...", progress: 25..40 },
      coding: { icon: "💻", message: "Writing the code...", progress: 40..70 },
      optimizing: { icon: "⚡", message: "Optimizing performance...", progress: 70..85 },
      finalizing: { icon: "✅", message: "Finalizing your app...", progress: 85..100 }
    }.freeze
    
    def initialize(app, generation = nil, chat_message = nil)
      @app = app
      @generation = generation || app.app_generations.create!(prompt: app.prompt, status: "generating")
      @chat_message = chat_message || create_initial_message
      @client = OpenRouterClient.new
      @current_stage = nil
      @files_generated = []
      @environment_vars = {}
    end
    
    def generate!
      Rails.logger.info "[EnhancedGenerator] Starting generation for App ##{app.id}"
      
      begin
        # Stage 1: Understanding
        enter_stage(:understanding)
        context = analyze_requirements_with_ai
        
        # Stage 2: Planning
        enter_stage(:planning)
        architecture = plan_architecture_with_ai(context)
        
        # Stage 3: Designing
        enter_stage(:designing)
        design_system = create_design_system_with_ai(architecture)
        
        # Stage 4: Coding
        enter_stage(:coding)
        generated_files = generate_code_with_ai(architecture, design_system)
        
        # Stage 5: Optimizing
        enter_stage(:optimizing)
        optimized_files = optimize_and_validate(generated_files)
        
        # Stage 6: Finalizing
        enter_stage(:finalizing)
        result = finalize_app(optimized_files)
        
        complete_generation(result)
        { success: true, result: result }
        
      rescue => e
        handle_generation_error(e)
        { success: false, error: e.message }
      end
    end
    
    private
    
    def create_initial_message
      app.app_chat_messages.create!(
        role: "assistant",
        content: "🚀 Starting app generation...",
        status: "executing"
      )
    end
    
    def enter_stage(stage_key)
      @current_stage = stage_key
      stage = GENERATION_STAGES[stage_key]
      
      progress = stage[:progress].begin
      update_progress_message("#{stage[:icon]} #{stage[:message]}", progress)
      
      # Simulate sub-progress within stage
      Thread.new do
        3.times do |i|
          sleep 0.5
          sub_progress = progress + ((stage[:progress].end - progress) * (i + 1) / 3.0).round
          update_progress_message("#{stage[:icon]} #{stage[:message]}", sub_progress)
        end
      end
    end
    
    def analyze_requirements_with_ai
      Rails.logger.info "[EnhancedGenerator] Analyzing requirements with AI"
      
      # Load AI standards
      ai_standards = File.read(Rails.root.join('AI_APP_STANDARDS.md'))
      
      # Build comprehensive prompt
      prompt = build_analysis_prompt(ai_standards)
      
      messages = [
        {
          role: "system",
          content: "You are an expert app architect analyzing requirements for a web application. Consider database needs, authentication, and deployment requirements."
        },
        {
          role: "user",
          content: prompt
        }
      ]
      
      response = @client.chat(messages, model: :claude_4, temperature: 0.3, max_tokens: 4000)
      
      if response[:success]
        parse_json_from_response(response[:content])
      else
        raise "Failed to analyze requirements: #{response[:error]}"
      end
    end
    
    def plan_architecture_with_ai(context)
      Rails.logger.info "[EnhancedGenerator] Planning architecture with AI"
      
      # Check if app needs database
      needs_database = context["needs_database"] || app.prompt.match?(/data|store|user|login|save/i)
      
      messages = [
        {
          role: "system",
          content: "You are an expert software architect. Plan a scalable, maintainable architecture for the web application."
        },
        {
          role: "user",
          content: build_architecture_prompt(context, needs_database)
        }
      ]
      
      response = @client.chat(messages, model: :claude_4, temperature: 0.3, max_tokens: 4000)
      
      if response[:success]
        architecture = parse_json_from_response(response[:content])
        
        # Extract environment variables needed
        if architecture["environment_variables"]
          @environment_vars = architecture["environment_variables"]
        end
        
        architecture
      else
        raise "Failed to plan architecture: #{response[:error]}"
      end
    end
    
    def create_design_system_with_ai(architecture)
      Rails.logger.info "[EnhancedGenerator] Creating design system with AI"
      
      messages = [
        {
          role: "system",
          content: "You are an expert UI/UX designer. Create a sophisticated, modern design system for the application."
        },
        {
          role: "user",
          content: build_design_prompt(architecture)
        }
      ]
      
      response = @client.chat(messages, model: :claude_4, temperature: 0.5, max_tokens: 3000)
      
      if response[:success]
        parse_json_from_response(response[:content])
      else
        raise "Failed to create design system: #{response[:error]}"
      end
    end
    
    def generate_code_with_ai(architecture, design_system)
      Rails.logger.info "[EnhancedGenerator] Generating code with AI function calling"
      
      # Use function calling for structured code generation
      result = @client.generate_app(
        build_generation_prompt(architecture, design_system),
        framework: app.framework,
        app_type: app.app_type
      )
      
      if result[:success] && result[:tool_calls]&.any?
        # Extract files from function call
        tool_call = result[:tool_calls].first
        args = JSON.parse(tool_call.dig("function", "arguments"))
        files = args["files"] || []
        
        # Add environment variable configuration if needed
        if @environment_vars.any?
          files << generate_env_config_file
        end
        
        # Update progress for each file
        files.each_with_index do |file, index|
          progress = 40 + ((index.to_f / files.length) * 25).round
          update_progress_message("💻 Creating #{file['path']}...", progress)
          sleep 0.2
        end
        
        @files_generated = files
        files
      else
        raise "Failed to generate code: #{result[:error] || 'No function calls returned'}"
      end
    end
    
    def optimize_and_validate(files)
      Rails.logger.info "[EnhancedGenerator] Optimizing and validating code"
      
      optimized_files = []
      
      files.each_with_index do |file, index|
        progress = 70 + ((index.to_f / files.length) * 15).round
        update_progress_message("⚡ Optimizing #{file['path']}...", progress)
        
        # Validate and fix common issues
        content = file["content"]
        file_type = detect_file_type(file["path"])
        
        # Add OverSkill.js integration for error handling
        if file_type == "html" && !content.include?("overskill.js")
          content = inject_overskill_js(content)
        end
        
        # Inject environment variables if needed
        if @environment_vars.any? && (file_type == "js" || file_type == "html")
          content = inject_env_vars(content, file_type)
        end
        
        optimized_files << file.merge("content" => content)
        sleep 0.1
      end
      
      optimized_files
    end
    
    def finalize_app(files)
      Rails.logger.info "[EnhancedGenerator] Finalizing app"
      
      # Save files to database
      saved_files = []
      files.each do |file_data|
        app_file = app.app_files.create!(
          team: app.team,
          path: file_data["path"],
          content: file_data["content"],
          file_type: detect_file_type(file_data["path"]),
          size_bytes: file_data["content"].bytesize,
          is_entry_point: file_data["path"] == "index.html"
        )
        saved_files << app_file
      end
      
      # Create app version
      version = create_app_version(saved_files)
      
      # Deploy preview with environment variables
      deploy_preview_with_env_vars
      
      { files: saved_files, version: version, environment_vars: @environment_vars }
    end
    
    def complete_generation(result)
      # Update generation record
      @generation.update!(
        status: "completed",
        completed_at: Time.current,
        ai_model: "claude-4",
        total_cost: calculate_generation_cost
      )
      
      # Update app
      app.update!(
        status: "generated",
        ai_model: "claude-4"
      )
      
      # Create completion message
      completion_message = build_completion_message(result)
      chat_message.update!(
        content: completion_message,
        status: "completed"
      )
      
      broadcast_completion
    end
    
    def build_analysis_prompt(ai_standards)
      <<~PROMPT
        Analyze the following app request and provide a comprehensive understanding:
        
        User Request: #{app.prompt}
        App Type: #{app.app_type}
        Framework: #{app.framework}
        
        #{ai_standards}
        
        Provide a JSON response with:
        {
          "core_features": ["list of main features"],
          "user_personas": ["target users"],
          "needs_database": true/false,
          "needs_auth": true/false,
          "api_integrations": ["needed APIs"],
          "data_entities": ["users", "posts", etc],
          "complexity_level": "simple/medium/complex",
          "success_criteria": ["what makes this app successful"]
        }
      PROMPT
    end
    
    def build_architecture_prompt(context, needs_database)
      <<~PROMPT
        Design the architecture for this application:
        
        Context: #{context.to_json}
        
        Requirements:
        - Framework: #{app.framework}
        - Deployment: Cloudflare Workers
        - Database: #{needs_database ? 'Supabase with RLS' : 'None'}
        
        Return JSON with:
        {
          "pages": [{"path": "index.html", "purpose": "..."}],
          "components": [{"name": "Header", "reusable": true}],
          "data_flow": "description",
          "state_management": "approach",
          "environment_variables": {
            "SUPABASE_URL": "Required for database",
            "SUPABASE_ANON_KEY": "Required for database",
            "APP_ID": "Unique app identifier"
          },
          "database_schema": {
            "tables": [
              {
                "name": "table_name",
                "columns": [{"name": "col", "type": "text", "required": true}]
              }
            ]
          }
        }
      PROMPT
    end
    
    def build_design_prompt(architecture)
      <<~PROMPT
        Create a sophisticated design system for:
        
        Architecture: #{architecture.to_json}
        App Type: #{app.app_type}
        
        Return JSON with:
        {
          "color_palette": {
            "primary": "#hex",
            "secondary": "#hex",
            "accent": "#hex",
            "background": "#hex",
            "text": "#hex",
            "muted": "#hex",
            "border": "#hex"
          },
          "typography": {
            "font_family": "Inter, system-ui, sans-serif",
            "heading_sizes": ["3xl", "2xl", "xl", "lg"],
            "body_sizes": ["base", "sm", "xs"]
          },
          "spacing": {
            "unit": "0.25rem",
            "scale": [0, 1, 2, 4, 6, 8, 12, 16, 24, 32]
          },
          "components": {
            "button_variants": ["primary", "secondary", "ghost"],
            "card_styles": "description",
            "form_elements": "description"
          },
          "animations": {
            "transitions": "all 200ms ease",
            "hover_effects": "scale, shadow"
          }
        }
      PROMPT
    end
    
    def build_generation_prompt(architecture, design_system)
      <<~PROMPT
        Generate a complete #{app.framework} application:
        
        User Request: #{app.prompt}
        Architecture: #{architecture.to_json}
        Design System: #{design_system.to_json}
        
        Requirements:
        1. Create all necessary HTML, CSS, and JavaScript files
        2. Use Tailwind CSS via CDN for styling
        3. Include realistic sample data (5-10 items minimum)
        4. Implement all features as working functionality
        5. Add loading states and error handling
        6. Ensure mobile responsiveness
        7. Use modern JavaScript (ES6+)
        8. Include environment variable placeholders where needed
        
        The app must be production-ready and impressive, not a prototype.
      PROMPT
    end
    
    def generate_env_config_file
      {
        "path" => "env-config.js",
        "content" => <<~JS
          // Environment configuration for Cloudflare Workers
          // These values will be injected at deployment time
          window.ENV = {
            #{@environment_vars.map { |key, desc| "  #{key}: globalThis.#{key} || '#{key}_PLACEHOLDER'," }.join("\n")}
            APP_VERSION: '1.0.0',
            ENVIRONMENT: globalThis.ENVIRONMENT || 'development'
          };
          
          // Helper function to get environment variables
          window.getEnv = function(key, defaultValue = '') {
            return window.ENV[key] || defaultValue;
          };
          
          // Log environment (remove in production)
          console.log('Environment loaded:', Object.keys(window.ENV));
        JS
      }
    end
    
    def inject_overskill_js(html_content)
      # Inject OverSkill.js for error handling and editor communication
      injection = <<~HTML
        <script src="/overskill.js"></script>
        <script>
          // Initialize OverSkill integration
          if (typeof OverSkill !== 'undefined') {
            OverSkill.init({
              appId: window.ENV?.APP_ID || 'dev',
              debug: true
            });
          }
        </script>
      HTML
      
      if html_content.include?("</body>")
        html_content.sub("</body>", "#{injection}\n</body>")
      else
        html_content + "\n#{injection}"
      end
    end
    
    def inject_env_vars(content, file_type)
      if file_type == "html" && !content.include?("env-config.js")
        # Add env-config.js script tag
        script_tag = '<script src="/env-config.js"></script>'
        if content.include?("</head>")
          content.sub("</head>", "#{script_tag}\n</head>")
        else
          script_tag + "\n" + content
        end
      elsif file_type == "js"
        # Replace hardcoded values with env vars
        content = content.gsub(/['"]https:\/\/.*\.supabase\.co['"]/i, 'window.getEnv("SUPABASE_URL")')
        content = content.gsub(/['"]eyJ[^'"]+['"]/i, 'window.getEnv("SUPABASE_ANON_KEY")')
        content
      else
        content
      end
    end
    
    def deploy_preview_with_env_vars
      return unless @environment_vars.any?
      
      # Queue deployment job with environment variables
      DeployPreviewJob.perform_later(
        app.id,
        environment_variables: @environment_vars
      )
    end
    
    def create_app_version(files)
      version_number = app.app_versions.count + 1
      
      app.app_versions.create!(
        team: app.team,
        user: app.team.memberships.first.user,
        version_number: "1.#{version_number}.0",
        changelog: "Generated from: #{app.prompt[0..100]}...",
        files_snapshot: files.map { |f| 
          { path: f.path, content: f.content, file_type: f.file_type }
        }.to_json,
        deployed: false
      )
    end
    
    def build_completion_message(result)
      <<~MESSAGE
        ✅ **Your app has been generated successfully!**
        
        **📁 Files created:**
        #{result[:files].map { |f| "• #{f.path}" }.join("\n")}
        
        #{@environment_vars.any? ? "**🔐 Environment variables configured:**\n#{@environment_vars.keys.map { |k| "• #{k}" }.join("\n")}\n\n" : ""}
        
        **✨ What's next?** Try asking:
        • "Add user authentication with Google login"
        • "Create a dark mode theme"
        • "Add animations and transitions"
        • "Connect to a database for data persistence"
        • "Deploy to production"
        
        Your app is ready in the preview! 🚀
      MESSAGE
    end
    
    def update_progress_message(status, progress)
      bar_length = 20
      filled = (bar_length * progress / 100.0).round
      empty = bar_length - filled
      progress_bar = "█" * filled + "░" * empty
      
      content = <<~MESSAGE
        **🚀 Generation Progress**
        
        #{status}
        
        `#{progress_bar}` #{progress}%
      MESSAGE
      
      chat_message.update!(content: content)
      broadcast_update
    end
    
    def broadcast_update
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{app.id}_chat",
        target: "message_content_#{chat_message.id}",
        partial: "account/app_editors/chat_message_content",
        locals: { message: chat_message }
      )
    end
    
    def broadcast_completion
      # Broadcast completion event
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{app.id}_chat",
        target: "chat_messages",
        html: "<script>document.dispatchEvent(new CustomEvent('generation:complete'));</script>"
      )
      
      # Update preview
      UpdatePreviewJob.perform_later(app.id)
    end
    
    def handle_generation_error(error)
      Rails.logger.error "[EnhancedGenerator] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      @generation.update!(
        status: "failed",
        error_message: error.message,
        completed_at: Time.current
      )
      
      app.update!(status: "failed")
      
      chat_message.update!(
        content: "❌ Generation failed: #{error.message}\n\nPlease try again or contact support.",
        status: "failed"
      )
      
      broadcast_update
    end
    
    def parse_json_from_response(content)
      # Extract JSON from response
      json_match = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m) || content.match(/\{.+\}/m)
      return {} unless json_match
      
      JSON.parse(json_match[1] || json_match[0])
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse JSON: #{e.message}"
      {}
    end
    
    def detect_file_type(path)
      case File.extname(path).downcase
      when '.html', '.htm' then 'html'
      when '.css' then 'css'
      when '.js', '.mjs' then 'js'
      when '.json' then 'json'
      else 'text'
      end
    end
    
    def calculate_generation_cost
      # Estimate based on Claude 4 pricing
      # Rough estimate: ~10K tokens input, ~20K tokens output
      input_cost = (10_000 / 1_000_000.0) * 3.0  # $3 per 1M input tokens
      output_cost = (20_000 / 1_000_000.0) * 15.0  # $15 per 1M output tokens
      input_cost + output_cost
    end
  end
end