module Deployment
  # Service that automatically fixes build errors and retries
  class SelfHealingBuildService
    MAX_RETRY_ATTEMPTS = 2

    attr_reader :app, :attempts, :fixes_applied

    def initialize(app)
      @app = app
      @attempts = 0
      @fixes_applied = []
    end

    def build_with_retry!
      Rails.logger.info "[SelfHealing] Starting build for app #{@app.id}"

      loop do
        @attempts += 1
        Rails.logger.info "[SelfHealing] Build attempt #{@attempts}/#{MAX_RETRY_ATTEMPTS}"

        # Try to build
        build_service = Deployment::ViteBuildService.new(@app)
        result = build_service.build_app!

        if result[:success]
          Rails.logger.info "[SelfHealing] Build succeeded on attempt #{@attempts}"
          return result.merge(
            self_healed: @attempts > 1,
            fixes_applied: @fixes_applied,
            attempts: @attempts
          )
        end

        # If we've exhausted retries, fail
        if @attempts >= MAX_RETRY_ATTEMPTS
          Rails.logger.error "[SelfHealing] Build failed after #{@attempts} attempts"
          Rails.logger.error "[SelfHealing] Final error: #{result[:error]}"
          return result.merge(
            self_healed: false,
            fixes_attempted: @fixes_applied,
            attempts: @attempts
          )
        end

        # Analyze errors and attempt fix
        Rails.logger.info "[SelfHealing] Analyzing build errors for automatic fixes..."
        fix_result = analyze_and_fix_errors(result[:error])

        unless fix_result[:success]
          Rails.logger.warn "[SelfHealing] Could not generate automatic fixes: #{fix_result[:reason]}"

          # Try AI-powered fixes as last resort
          if should_try_ai_fixes?
            Rails.logger.info "[SelfHealing] Attempting AI-powered fixes..."
            ai_fix_result = attempt_ai_fixes(result[:error])

            if ai_fix_result[:success]
              Rails.logger.info "[SelfHealing] AI applied #{ai_fix_result[:fixes_count]} fixes"
              @fixes_applied.concat(ai_fix_result[:fixes])
              next # Retry build with AI fixes
            end
          end

          return result.merge(
            self_healed: false,
            fixes_attempted: @fixes_applied,
            attempts: @attempts
          )
        end

        Rails.logger.info "[SelfHealing] Applied #{fix_result[:fixes_count]} automatic fixes, retrying build..."
        @fixes_applied.concat(fix_result[:fixes])
      end
    end

    private

    def analyze_and_fix_errors(error_output)
      # Analyze errors using BuildErrorAnalyzer
      analyzer = Ai::BuildErrorAnalyzer.new(error_output)
      analysis = analyzer.analyze

      unless analysis[:can_auto_fix]
        return {
          success: false,
          reason: "Errors are not auto-fixable: #{analysis[:errors_summary].join(", ")}"
        }
      end

      fixes_applied = []

      # Apply automatic fixes based on strategies
      analysis[:strategies].each do |strategy|
        case strategy[:action]
        when "fix_typescript_paths"
          if fix_typescript_paths
            fixes_applied << "Fixed TypeScript paths configuration"
          end
        when "fix_tsconfig_composite"
          if fix_tsconfig_composite
            fixes_applied << "Fixed tsconfig composite setting"
          end
        when "install_packages"
          strategy[:packages].each do |package|
            if add_missing_package(package)
              fixes_applied << "Added package: #{package}"
            end
          end
        when "add_type_declarations"
          if add_window_type_declarations(strategy[:properties])
            fixes_applied << "Added type declarations for: #{strategy[:properties].join(", ")}"
          end
        end
      end

      {
        success: fixes_applied.any?,
        fixes_count: fixes_applied.count,
        fixes: fixes_applied
      }
    end

    def fix_typescript_paths
      tsconfig_file = @app.app_files.find_by(path: "tsconfig.json")
      return false unless tsconfig_file

      begin
        config = JSON.parse(tsconfig_file.content)
        config["compilerOptions"] ||= {}
        config["compilerOptions"]["baseUrl"] = "."
        config["compilerOptions"]["paths"] = {
          "@/*" => ["./src/*"]
        }

        tsconfig_file.content = JSON.pretty_generate(config)
        tsconfig_file.save!

        Rails.logger.info "[SelfHealing] Fixed TypeScript paths in tsconfig.json"
        true
      rescue => e
        Rails.logger.error "[SelfHealing] Failed to fix TypeScript paths: #{e.message}"
        false
      end
    end

    def fix_tsconfig_composite
      tsconfig_node = @app.app_files.find_by(path: "tsconfig.node.json")
      return false unless tsconfig_node

      begin
        config = JSON.parse(tsconfig_node.content)
        config["compilerOptions"] ||= {}
        config["compilerOptions"]["composite"] = true
        config["compilerOptions"]["noEmit"] = false

        tsconfig_node.content = JSON.pretty_generate(config)
        tsconfig_node.save!

        Rails.logger.info "[SelfHealing] Fixed composite setting in tsconfig.node.json"
        true
      rescue => e
        Rails.logger.error "[SelfHealing] Failed to fix composite setting: #{e.message}"
        false
      end
    end

    def add_missing_package(package_name)
      package_json = @app.app_files.find_by(path: "package.json")
      return false unless package_json

      begin
        config = JSON.parse(package_json.content)
        config["dependencies"] ||= {}

        # Determine version (use latest for now)
        version = determine_package_version(package_name)
        config["dependencies"][package_name] = version

        package_json.content = JSON.pretty_generate(config)
        package_json.save!

        Rails.logger.info "[SelfHealing] Added package #{package_name}@#{version}"
        true
      rescue => e
        Rails.logger.error "[SelfHealing] Failed to add package #{package_name}: #{e.message}"
        false
      end
    end

    def determine_package_version(package_name)
      # Common package versions (could be expanded or fetched from npm)
      known_versions = {
        "clsx" => "^2.1.0",
        "tailwind-merge" => "^2.2.0",
        "sonner" => "^1.3.1",
        "next-themes" => "^0.2.1",
        "lucide-react" => "^0.344.0",
        "class-variance-authority" => "^0.7.0"
      }

      known_versions[package_name] || "latest"
    end

    def add_window_type_declarations(properties)
      # Create or update a type declaration file
      type_file = @app.app_files.find_or_initialize_by(path: "src/types/window.d.ts")

      content = type_file.content.presence || ""

      # Add interface if not exists
      if content.include?("interface Window")
        # Add properties to existing interface
        properties.each do |prop|
          unless content.include?("#{prop}:")
            content.sub!("interface Window {", "interface Window {\n      #{prop}: any;")
          end
        end
      else
        content += <<~TS
          declare global {
            interface Window {
              #{properties.map { |p| "#{p}: any;" }.join("\n      ")}
            }
          }
          
          export {};
        TS
      end

      type_file.content = content
      type_file.file_type = "typescript"
      type_file.team = @app.team
      type_file.save!

      Rails.logger.info "[SelfHealing] Added type declarations for Window properties"
      true
    rescue => e
      Rails.logger.error "[SelfHealing] Failed to add type declarations: #{e.message}"
      false
    end

    def should_try_ai_fixes?
      # Only try AI fixes on second attempt and if enabled
      @attempts == 1 && ENV["ENABLE_AI_BUILD_FIXES"] == "true"
    end

    def attempt_ai_fixes(error_output)
      # This would integrate with AppBuilderV5 or a dedicated AI fix service
      # For now, return unsuccessful to avoid infinite loops
      {success: false, reason: "AI fixes not yet implemented"}
    end
  end
end
