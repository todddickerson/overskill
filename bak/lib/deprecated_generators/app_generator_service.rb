module Ai
  class AppGeneratorService
    class GenerationError < StandardError; end

    attr_reader :app, :generation, :errors

    def initialize(app, generation = nil)
      @app = app
      @generation = generation || app.app_generations.last
      @errors = []
    end

    def generate!
      Rails.logger.info "[AppGenerator] Starting generation for App ##{app.id}"

      # Update generation status
      @generation.update!(
        started_at: Time.current,
        status: "generating"
      )

      # Update app status
      @app.update!(status: "generating")

      # Create initial progress message
      progress_message = create_progress_message("Starting generation...", 0)

      # Step 1: Enhance the prompt
      update_progress_message(progress_message, "Enhancing prompt with context...", 10)
      enhanced_prompt = enhance_prompt(@generation.prompt)

      # Step 2: Call AI to generate the app
      update_progress_message(progress_message, "Generating app with AI (this may take 1-2 minutes)...", 20)
      ai_response = generate_with_ai(enhanced_prompt)

      if ai_response[:success]
        update_progress_message(progress_message, "AI generation complete! Processing response...", 50)

        # Step 3: Parse the AI response (now using function calling)
        update_progress_message(progress_message, "Processing function call response...", 60)
        parsed_data = parse_function_call_response(ai_response)

        if parsed_data
          # Step 4: Security scan
          update_progress_message(progress_message, "Running security scan...", 70)
          if security_scan_passed?(parsed_data[:files])
            # Step 5: Create app files
            update_progress_message(progress_message, "Creating app files...", 80)
            create_app_files_with_progress(parsed_data[:files], progress_message)

            # Step 6: Update app metadata
            update_progress_message(progress_message, "Updating app metadata...", 90)
            update_app_metadata(parsed_data[:app])

            # Step 7: Mark generation as complete
            update_progress_message(progress_message, "Generation complete! ✅", 100)
            @generation.update!(
              completed_at: Time.current,
              status: "completed",
              ai_model: ai_response[:model],
              total_cost: (calculate_cost(ai_response[:usage]) * 100).to_i, # Store as cents
              duration_seconds: (Time.current - @generation.started_at).to_i,
              input_tokens: ai_response[:usage]&.dig("prompt_tokens"),
              output_tokens: ai_response[:usage]&.dig("completion_tokens")
            )

            @app.update!(
              status: "generated",
              ai_model: ai_response[:model],
              ai_cost: calculate_cost(ai_response[:usage])
            )

            Rails.logger.info "[AppGenerator] Successfully generated App ##{app.id}"

            # Mark progress as complete and clean up
            update_progress_message(progress_message, "✅ Generation complete! Your app is ready.", 100)

            {success: true}
          else
            update_progress_message(progress_message, "❌ Security scan failed - unsafe code detected", 100)
            handle_error("Security scan failed - potentially unsafe code detected")
          end
        else
          update_progress_message(progress_message, "❌ Failed to parse AI response", 100)
          handle_error("Failed to parse AI response")
        end
      else
        update_progress_message(progress_message, "❌ AI generation failed: #{ai_response[:error]}", 100)
        handle_error("AI generation failed: #{ai_response[:error]}")
      end
    rescue => e
      # Update progress message on error
      if defined?(progress_message) && progress_message
        update_progress_message(progress_message, "❌ Generation error: #{e.message}", 100)
      end
      handle_error("Generation error: #{e.message}")
      {success: false, error: e.message}
    end

    # Methods below are public for console debugging
    # private # Uncomment to make methods private in production

    def enhance_prompt(original_prompt)
      # For MVP, just add some context. Later we can make this smarter.
      <<~PROMPT
        Create a #{app.app_type} application with the following requirements:
        
        #{original_prompt}
        
        Additional context:
        - Framework preference: #{app.framework}
        - The app should be production-ready and polished
        - Include proper error handling
        - Make it visually appealing and responsive
      PROMPT
    end

    def generate_with_ai(enhanced_prompt)
      # Use the OpenRouter client with prompt templates
      client = Ai::OpenRouterClient.new
      client.generate_app(enhanced_prompt, framework: app.framework, app_type: app.app_type)
    end

    def parse_function_call_response(ai_response)
      Rails.logger.info "[AppGenerator] Parsing function call response"

      # Extract function call results
      tool_calls = ai_response[:tool_calls]

      unless tool_calls&.any?
        Rails.logger.error "[AppGenerator] No function calls found in AI response"
        return nil
      end

      # Find the generate_app function call
      generate_call = tool_calls.find { |call| call.dig("function", "name") == "generate_app" }

      unless generate_call
        Rails.logger.error "[AppGenerator] No generate_app function call found"
        return nil
      end

      begin
        # Parse the function arguments - this is already structured JSON
        arguments = generate_call.dig("function", "arguments")
        data = arguments.is_a?(String) ? JSON.parse(arguments) : arguments

        Rails.logger.info "[AppGenerator] Successfully parsed function call arguments"

        # Validate the structured data
        unless validate_function_call_data(data)
          Rails.logger.error "[AppGenerator] Function call data validation failed"
          return nil
        end

        {
          app: data["app"],
          files: data["files"],
          instructions: data["instructions"],
          deployment_notes: data["deployment_notes"],
          whats_next: data["whats_next"]
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[AppGenerator] Failed to parse function arguments: #{e.message}"
        Rails.logger.error "[AppGenerator] Arguments: #{arguments.inspect}"
        nil
      end
    end

    def parse_ai_response(content)
      Rails.logger.info "[AppGenerator] Parsing AI response (#{content.length} chars) - FALLBACK MODE"

      # Log response preview for debugging
      if ENV["VERBOSE_AI_LOGGING"] == "true"
        Rails.logger.info "[AppGenerator] AI Response preview: #{content[0..1000]}..."
      end

      # First try to extract JSON from markdown code blocks
      extracted_content = extract_json_from_markdown(content) || content

      begin
        # Try to parse as JSON
        data = JSON.parse(extracted_content)

        # Validate required fields
        unless validate_ai_response(data)
          Rails.logger.error "[AppGenerator] AI response validation failed"
          return nil
        end

        {
          app: data["app"],
          files: data["files"],
          instructions: data["instructions"],
          deployment_notes: data["deployment_notes"],
          whats_next: data["whats_next"]
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[AppGenerator] Failed to parse AI response as JSON: #{e.message}"
        Rails.logger.error "[AppGenerator] Content preview: #{extracted_content[0..500]}..."
        nil
      end
    end

    private

    def create_progress_message(message, progress)
      # Create a system message in the chat to show progress
      progress_msg = @app.app_chat_messages.create!(
        content: build_progress_content(message, progress),
        role: "system"
      )

      # Broadcast the new message via Turbo
      broadcast_chat_message(progress_msg)

      progress_msg
    end

    def update_progress_message(progress_message, message, progress)
      # Update the existing progress message
      progress_message.update!(
        content: build_progress_content(message, progress),
        updated_at: Time.current
      )

      # Broadcast the update via Turbo
      broadcast_chat_message_update(progress_message)
    end

    def build_progress_content(message, progress)
      # Use a visual progress bar with text characters instead of HTML
      progress_bar_width = 20
      filled_chars = (progress * progress_bar_width / 100).round
      empty_chars = progress_bar_width - filled_chars

      progress_bar = "█" * filled_chars + "░" * empty_chars

      <<~CONTENT
        **🔄 Generation Progress**

        #{message}

        Progress: #{progress}%

        `#{progress_bar}` #{progress}%
      CONTENT
    end

    def broadcast_chat_message(message)
      Turbo::StreamsChannel.broadcast_append_to(
        "app_#{@app.id}_chat",
        target: "chat_messages",
        partial: "account/app_editors/chat_message",
        locals: {message: message}
      )
    end

    def broadcast_chat_message_update(message)
      Turbo::StreamsChannel.broadcast_replace_to(
        "app_#{@app.id}_chat",
        target: "chat_message_#{message.id}",
        partial: "account/app_editors/chat_message",
        locals: {message: message}
      )
    end

    def extract_json_from_markdown(content)
      # Handle multiple possible markdown formats
      patterns = [
        /```json\s*\n?(.*?)\n?```/m,  # ```json\n...\n``` or ```json...```
        /```\s*\n?(.*?)\n?```/m       # ```\n...\n``` (no language specified)
      ]

      patterns.each do |pattern|
        match = content.match(pattern)
        return match[1].strip if match
      end

      nil
    end

    def validate_function_call_data(data)
      required_fields = %w[app files]
      missing_fields = required_fields.select { |field| data[field].nil? || data[field].empty? }

      if missing_fields.any?
        Rails.logger.error "[AppGenerator] Missing required fields in function call: #{missing_fields.join(", ")}"
        return false
      end

      # Validate app structure
      app_data = data["app"]
      required_app_fields = %w[name description type features tech_stack]
      missing_app_fields = required_app_fields.select { |field| app_data[field].nil? || app_data[field].empty? }

      if missing_app_fields.any?
        Rails.logger.error "[AppGenerator] Missing app fields: #{missing_app_fields.join(", ")}"
        return false
      end

      # Validate files structure
      if !data["files"].is_a?(Array) || data["files"].empty?
        Rails.logger.error "[AppGenerator] Files must be a non-empty array"
        return false
      end

      data["files"].each_with_index do |file, index|
        unless file.is_a?(Hash) && file["path"] && file["content"]
          Rails.logger.error "[AppGenerator] File #{index} missing path or content"
          return false
        end
      end

      Rails.logger.info "[AppGenerator] Function call data validation passed"
      true
    end

    def validate_ai_response(data)
      required_fields = %w[app files]
      missing_fields = required_fields.select { |field| data[field].nil? || data[field].empty? }

      if missing_fields.any?
        Rails.logger.error "[AppGenerator] Missing required fields: #{missing_fields.join(", ")}"
        return false
      end

      # Validate files structure
      if !data["files"].is_a?(Array) || data["files"].empty?
        Rails.logger.error "[AppGenerator] Files must be a non-empty array"
        return false
      end

      data["files"].each_with_index do |file, index|
        unless file.is_a?(Hash) && file["path"] && file["content"]
          Rails.logger.error "[AppGenerator] File #{index} missing path or content"
          return false
        end
      end

      true
    end

    def security_scan_passed?(files)
      # For MVP, just check for obvious dangerous patterns
      # Later we'll use Ai::SecurityScanner service

      dangerous_patterns = [
        /eval\s*\(/,
        /exec\s*\(/,
        /<script[^>]*src\s*=\s*["']https?:\/\/[^"']*malware/i,
        /document\.write\s*\(/,
        /\.innerHTML\s*=.*<script/i
      ]

      files.each do |file|
        content = file["content"] || file[:content]
        dangerous_patterns.each do |pattern|
          if content.match?(pattern)
            Rails.logger.warn "[AppGenerator] Security scan failed - found dangerous pattern"
            return false
          end
        end
      end

      true
    end

    def generate_auth_config(app)
      {
        auth_provider: "supabase",
        supabase_url: ENV["SUPABASE_URL"],
        supabase_anon_key: ENV["SUPABASE_ANON_KEY"],
        auth_options: {
          providers: ["email", "google", "github"],
          redirect_url: "#{app.published_url}/auth/callback",
          enable_signup: !app.invite_only?,
          require_email_verification: true
        }
      }
    end

    def generate_auth_code
      <<~JS
        // Supabase client initialization
        import { createClient } from '@supabase/supabase-js'
        
        const supabase = createClient(
          process.env.REACT_APP_SUPABASE_URL,
          process.env.REACT_APP_SUPABASE_ANON_KEY
        )
        
        // Auth hook
        export function useAuth() {
          const [user, setUser] = useState(null)
          const [loading, setLoading] = useState(true)
          
          useEffect(() => {
            // Get initial session
            supabase.auth.getSession().then(({ data: { session } }) => {
              setUser(session?.user ?? null)
              setLoading(false)
            })
            
            // Listen for auth changes
            const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
              setUser(session?.user ?? null)
            })
            
            return () => subscription.unsubscribe()
          }, [])
          
          return { user, loading, supabase }
        }
      JS
    end

    def create_app_files(files)
      # Clear existing files for regeneration
      Rails.logger.info "[AppGenerator] Clearing existing files for regeneration"
      @app.app_files.destroy_all

      # Validate and fix files before creating
      validated_files = validate_and_fix_files(files)

      validated_files.each do |file_data|
        @app.app_files.create!(
          team: @app.team,
          path: file_data["path"] || file_data[:path],
          content: file_data["content"] || file_data[:content],
          file_type: determine_file_type(file_data["path"] || file_data[:path]),
          size_bytes: (file_data["content"] || file_data[:content]).bytesize
        )
      end

      # Don't create version here - it's created by ProcessAppUpdateJob when there are actual changes
    end

    def create_app_files_with_progress(files, progress_message)
      # Clear existing files for regeneration
      Rails.logger.info "[AppGenerator] Clearing existing files for regeneration"
      @app.app_files.destroy_all

      # Validate and fix files before creating
      validated_files = validate_and_fix_files(files)

      validated_files.each_with_index do |file_data, index|
        file_path = file_data["path"] || file_data[:path]
        progress = 80 + (10 * (index + 1) / validated_files.length)

        update_progress_message(progress_message, "Creating #{file_path}...", progress)

        @app.app_files.create!(
          team: @app.team,
          path: file_path,
          content: file_data["content"] || file_data[:content],
          file_type: determine_file_type(file_path),
          size_bytes: (file_data["content"] || file_data[:content]).bytesize
        )

        # Small delay to make progress visible
        sleep(0.1)
      end

      # Don't create version here - it's created by ProcessAppUpdateJob when there are actual changes
    end

    def determine_file_type(path)
      extension = File.extname(path).downcase.delete(".")

      case extension
      when "html", "htm" then "html"
      when "js", "jsx" then "javascript"
      when "css", "scss", "sass" then "css"
      when "json" then "json"
      when "md", "markdown" then "markdown"
      when "tsx", "ts" then "typescript"
      when "vue" then "vue"
      else "other"
      end
    end

    def update_app_metadata(app_data)
      updates = {}

      updates[:name] = app_data["name"] if app_data["name"].present?
      updates[:description] = app_data["description"] if app_data["description"].present?

      # Generate slug from name if needed
      if updates[:name] && app.slug.blank?
        updates[:slug] = updates[:name].parameterize
      end

      @app.update!(updates) if updates.any?
    end

    def calculate_cost(usage)
      return 0.0 unless usage

      # Using Kimi K2 for all generation
      prompt_tokens = usage["prompt_tokens"] || 0
      completion_tokens = usage["completion_tokens"] || 0

      # Kimi K2 pricing (per 1M tokens)
      prompt_cost = (prompt_tokens / 1_000_000.0) * 0.30  # $0.30 per 1M tokens
      completion_cost = (completion_tokens / 1_000_000.0) * 0.30  # $0.30 per 1M tokens

      prompt_cost + completion_cost
    end

    def handle_error(message)
      Rails.logger.error "[AppGenerator] #{message}"
      @errors << message

      @generation.update!(
        completed_at: Time.current,
        status: "failed",
        error_message: message
      )

      @app.update!(status: "failed")

      {success: false, error: message}
    end

    def validate_and_fix_files(files)
      # Convert to consistent format for validation
      normalized_files = files.map do |file|
        {
          path: file["path"] || file[:path],
          content: file["content"] || file[:content],
          type: determine_file_type(file["path"] || file[:path])
        }
      end

      # Validate the files
      validation = Ai::CodeValidatorService.validate_files(normalized_files)

      if validation[:valid]
        files
      else
        # Log validation errors
        Rails.logger.warn "[AppGenerator] Code validation warnings:"
        validation[:errors].each do |error|
          Rails.logger.warn "  #{error[:file]}: #{error[:message]}"
        end

        # Try to fix common issues
        fixed_files = files.map do |file|
          path = file["path"] || file[:path]
          content = file["content"] || file[:content]
          file_type = determine_file_type(path)

          # Apply fixes for JavaScript and HTML files
          if file_type == "javascript" || file_type == "html"
            content = Ai::CodeValidatorService.fix_common_issues(content, file_type)
          end

          # Return in original format
          if file.is_a?(Hash) && file.key?("path")
            file.merge("content" => content)
          else
            file.merge(content: content)
          end
        end

        # Validate again after fixes
        normalized_fixed = fixed_files.map do |file|
          {
            path: file["path"] || file[:path],
            content: file["content"] || file[:content],
            type: determine_file_type(file["path"] || file[:path])
          }
        end

        retry_validation = Ai::CodeValidatorService.validate_files(normalized_fixed)
        if !retry_validation[:valid]
          Rails.logger.error "[AppGenerator] Code still has errors after fixes:"
          retry_validation[:errors].each do |error|
            Rails.logger.error "  #{error[:file]}: #{error[:message]}"
          end
        end

        fixed_files
      end
    end
  end
end
