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

      # Step 1: Enhance the prompt
      enhanced_prompt = enhance_prompt(@generation.prompt)

      # Step 2: Call AI to generate the app
      ai_response = generate_with_ai(enhanced_prompt)

      if ai_response[:success]
        # Step 3: Parse the AI response
        parsed_data = parse_ai_response(ai_response[:content])

        if parsed_data
          # Step 4: Security scan
          if security_scan_passed?(parsed_data[:files])
            # Step 5: Create app files
            create_app_files(parsed_data[:files])

            # Step 6: Update app metadata
            update_app_metadata(parsed_data[:app])

            # Step 7: Mark generation as complete
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
            {success: true}
          else
            handle_error("Security scan failed - potentially unsafe code detected")
          end
        else
          handle_error("Failed to parse AI response")
        end
      else
        handle_error("AI generation failed: #{ai_response[:error]}")
      end
    rescue => e
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

    def parse_ai_response(content)
      begin
        # Try to parse as JSON
        data = JSON.parse(content)

        # Validate required fields
        return nil unless data["app"] && data["files"]

        {
          app: data["app"],
          files: data["files"],
          instructions: data["instructions"],
          deployment_notes: data["deployment_notes"],
          whats_next: data["whats_next"]
        }
      rescue JSON::ParserError => e
        Rails.logger.error "[AppGenerator] Failed to parse AI response as JSON: #{e.message}"

        # Try to extract JSON from markdown code blocks
        json_match = content.match(/```json\n(.*?)\n```/m)
        if json_match
          content = json_match[1]
          retry
        end

        nil
      end
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

    def create_app_files(files)
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
        return files
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
          
          # Apply fixes for JavaScript files
          if file_type == "javascript"
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
