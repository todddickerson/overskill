# Enhanced V4 App Builder with improved chat UX feedback - FIXED VERSION
module Ai
  class AppBuilderV4Enhanced
    include Rails.application.routes.url_helpers
    
    attr_reader :chat_message, :app, :broadcaster
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app || create_app
      @broadcaster = ChatProgressBroadcasterV2.new(chat_message)
      @start_time = Time.current
      @generated_files = []
      @errors = []
    end
    
    def execute!
      Rails.logger.info "[AppBuilderV4Enhanced] Starting enhanced generation for message ##{chat_message.id}"
      
      begin
        # Mark app as generating
        app.update!(status: 'generating')
        
        # Phase 1: Understanding Requirements
        broadcaster.broadcast_phase(1, "Understanding Requirements", 6)
        analyze_requirements
        
        # Phase 2: Planning Architecture  
        broadcaster.broadcast_phase(2, "Planning Architecture", 6)
        plan_architecture
        
        # Phase 3: Setting Up Foundation
        broadcaster.broadcast_phase(3, "Setting Up Foundation", 6)
        setup_foundation_with_feedback
        
        # Phase 4: Generating Features
        broadcaster.broadcast_phase(4, "Generating Features", 6)
        generate_features_with_feedback
        
        # Phase 5: Validating & Building
        broadcaster.broadcast_phase(5, "Validating & Building", 6)
        validate_and_build_with_feedback
        
        # Phase 6: Deploying
        broadcaster.broadcast_phase(6, "Deploying", 6)
        deploy_with_feedback
        
        # Complete!
        app.update!(status: 'ready')
        chat_message.update!(status: 'completed')
        
        broadcaster.broadcast_completion(
          success: true,
          stats: {
            files_generated: @generated_files.count,
            build_time: Time.current - @start_time,
            app_url: app.preview_url
          }
        )
        
        { success: true, app: app }
        
      rescue => e
        handle_error(e)
        { success: false, error: e.message }
      end
    end
    
    private
    
    def create_app
      App.create!(
        team: chat_message.user.current_team,
        name: "App #{SecureRandom.hex(4)}",
        description: extract_app_description,
        status: 'generating'
      )
    end
    
    def analyze_requirements
      # Extract app type and requirements from chat message
      requirements = extract_requirements_from_message
      
      # Broadcast sub-tasks
      broadcaster.broadcast_file_operation(:creating, "requirements.json", requirements.to_json)
      
      # Store requirements for later phases
      @requirements = requirements
      
      broadcaster.broadcast_file_operation(:created, "requirements.json")
    end
    
    def plan_architecture
      # Determine file structure
      files_to_generate = determine_file_structure(@requirements)
      
      # Broadcast planning details
      files_to_generate.each do |file_path|
        broadcaster.broadcast_file_operation(:creating, file_path, nil, "planned")
      end
      
      # Check dependencies - but DON'T create package.json yet
      dependencies = extract_dependencies(files_to_generate)
      missing_deps = check_missing_dependencies(dependencies)
      
      broadcaster.broadcast_dependency_check(dependencies, missing_deps, [])
      
      # Store dependencies for later use instead of creating package.json
      @planned_dependencies = dependencies
      @missing_dependencies = missing_deps
      
      @planned_files = files_to_generate
    end
    
    def setup_foundation_with_feedback
      Rails.logger.info "[AppBuilderV4Enhanced] Setting up foundation with live feedback"
      
      # Generate shared template files with progress
      template_service = SharedTemplateService.new(app)
      foundation_files = template_service.generate_foundation_files
      
      # Use transaction for atomic file creation
      ActiveRecord::Base.transaction do
        foundation_files.each do |file_data|
          # Show file being created
          broadcaster.broadcast_file_operation(:creating, file_data[:path], file_data[:content][0..200])
          
          # Create or update the file (using find_or_create_by for safety)
          app_file = app.app_files.find_or_create_by(path: file_data[:path]) do |f|
            f.content = file_data[:content]
            f.team = app.team
          end
          
          # Update content if file already exists
          if app_file.persisted? && app_file.content != file_data[:content]
            app_file.update!(content: file_data[:content])
          end
          
          @generated_files << app_file
          
          # Mark as created
          broadcaster.broadcast_file_operation(:created, file_data[:path])
          
          # Small delay for visual effect
          sleep 0.05
        end
      end
      
      # Now handle dependencies after foundation files are created
      if @missing_dependencies&.any?
        update_package_json_dependencies(@missing_dependencies)
        broadcaster.broadcast_dependency_check(@planned_dependencies, [], @missing_dependencies)
      end
      
    rescue ActiveRecord::RecordNotUnique => e
      # Handle duplicate key error gracefully
      Rails.logger.warn "[AppBuilderV4Enhanced] Duplicate file detected, continuing: #{e.message}"
      # Continue with existing files
    rescue => e
      Rails.logger.error "[AppBuilderV4Enhanced] Foundation setup failed: #{e.message}"
      raise
    end
    
    def generate_features_with_feedback
      Rails.logger.info "[AppBuilderV4Enhanced] Generating app-specific features"
      
      # Use AI to generate feature files
      feature_files = generate_feature_files_with_ai
      
      # Request approval if significant changes
      if feature_files.any? { |f| f[:requires_approval] }
        changes = feature_files.map do |f|
          {
            file_path: f[:path],
            action: f[:action],
            preview: f[:content][0..500]
          }
        end
        
        callback_id = SecureRandom.hex(8)
        broadcaster.request_user_approval(changes, callback_id)
        
        # Wait for approval (with timeout)
        approved = wait_for_approval(callback_id, timeout: 30.seconds)
        
        unless approved
          broadcaster.broadcast_error(
            "Changes were not approved",
            ["Review the proposed changes", "Modify your request", "Try again"],
            nil
          )
          return
        end
      end
      
      # Generate the files with transaction safety
      ActiveRecord::Base.transaction do
        feature_files.each do |file_data|
          broadcaster.broadcast_file_operation(:creating, file_data[:path], file_data[:content][0..200])
          
          if file_data[:action] == 'update'
            # Update existing file
            existing_file = app.app_files.find_by(path: file_data[:path])
            if existing_file
              broadcaster.broadcast_file_operation(:updated, file_data[:path], generate_diff(existing_file.content, file_data[:content]))
              existing_file.update!(content: file_data[:content])
            end
          else
            # Create new file (with duplicate protection)
            app_file = app.app_files.find_or_create_by(path: file_data[:path]) do |f|
              f.content = file_data[:content]
              f.team = app.team
            end
            @generated_files << app_file unless @generated_files.include?(app_file)
          end
          
          broadcaster.broadcast_file_operation(:created, file_data[:path])
          sleep 0.05
        end
      end
    rescue => e
      Rails.logger.error "[AppBuilderV4Enhanced] Feature generation failed: #{e.message}"
      broadcaster.broadcast_error(
        "Failed to generate features",
        ["Check the error details", "Try simplifying your request"],
        e.message
      )
      raise
    end
    
    def validate_and_build_with_feedback
      Rails.logger.info "[AppBuilderV4Enhanced] Building app with live output"
      
      # Ensure we have required files before building
      required_files = ['package.json', 'src/main.tsx', 'index.html']
      missing_files = required_files - app.app_files.pluck(:path)
      
      if missing_files.any?
        broadcaster.broadcast_error(
          "Missing required files for build",
          ["Files needed: #{missing_files.join(', ')}", "Regenerate the app"],
          nil
        )
        raise "Missing required files: #{missing_files.join(', ')}"
      end
      
      # Start the build process
      builder = Deployment::ExternalViteBuilder.new(app)
      
      broadcaster.broadcast_build_output("Installing dependencies...", :stdout)
      sleep 1
      broadcaster.broadcast_build_output("Building application...", :stdout)
      
      # Execute build
      build_result = builder.build_for_preview
      
      if build_result[:success]
        broadcaster.broadcast_build_output("✓ Build completed successfully!", :stdout)
        @built_code = build_result[:built_code]
      else
        broadcaster.broadcast_error(
          "Build failed: #{build_result[:error]}",
          [
            "Check your code for syntax errors",
            "Ensure all dependencies are installed",
            "Review the build output above"
          ],
          build_result[:error]
        )
        raise "Build failed"
      end
    rescue => e
      Rails.logger.error "[AppBuilderV4Enhanced] Build failed: #{e.message}"
      raise
    end
    
    def deploy_with_feedback
      Rails.logger.info "[AppBuilderV4Enhanced] Deploying with progress updates"
      
      broadcaster.broadcast_build_output("Deploying to Cloudflare Workers...", :stdout)
      
      deployer = Deployment::CloudflareWorkersDeployer.new(app)
      deployment_result = deployer.deploy_with_secrets(
        built_code: @built_code,
        deployment_type: :preview
      )
      
      if deployment_result[:success]
        app.update!(
          preview_url: deployment_result[:worker_url],
          status: 'ready'
        )
        
        broadcaster.broadcast_build_output("✓ Deployed successfully!", :stdout)
        broadcaster.broadcast_build_output("URL: #{deployment_result[:worker_url]}", :stdout)
      else
        broadcaster.broadcast_error(
          "Deployment failed",
          ["Check Cloudflare API credentials", "Verify worker limits"],
          deployment_result[:error]
        )
        raise "Deployment failed"
      end
    rescue => e
      Rails.logger.error "[AppBuilderV4Enhanced] Deployment failed: #{e.message}"
      raise
    end
    
    def handle_error(error)
      Rails.logger.error "[AppBuilderV4Enhanced] Error: #{error.message}"
      Rails.logger.error error.backtrace.first(10).join("\n")
      
      # Update app status to failed
      app.update!(status: 'failed') rescue nil
      chat_message.update!(status: 'failed') rescue nil
      
      # Broadcast user-friendly error
      suggestions = case error.message
      when /duplicate key/i
        ["Files may already exist", "Clear existing files and retry", "Check for duplicate file paths"]
      when /Supabase/
        ["Check Supabase credentials", "Verify database connection"]
      when /dependency|package/
        ["Install missing packages", "Check package.json"]
      when /syntax/
        ["Review generated code", "Check for syntax errors"]
      else
        ["Try regenerating the app", "Simplify your requirements"]
      end
      
      broadcaster.broadcast_error(
        simplify_error_message(error.message),
        suggestions,
        error.backtrace.first(5).join("\n")
      )
      
      broadcaster.broadcast_completion(
        success: false,
        stats: {
          error: error.message,
          duration: Time.current - @start_time
        }
      )
    end
    
    # Helper methods
    
    def extract_requirements_from_message
      # Parse the chat message for requirements
      {
        app_type: detect_app_type(chat_message.content),
        features: extract_features(chat_message.content),
        technologies: ['React', 'TypeScript', 'Tailwind', 'Supabase']
      }
    end
    
    def determine_file_structure(requirements)
      # Basic file structure
      files = [
        'src/App.tsx',
        'src/main.tsx', 
        'src/index.css',
        'src/lib/supabase.ts',
        'src/components/Layout.tsx'
      ]
      
      # Add feature-specific files
      case requirements[:app_type]
      when 'todo'
        files += [
          'src/components/TodoList.tsx',
          'src/components/TodoItem.tsx',
          'src/hooks/useTodos.ts'
        ]
      when 'chat'
        files += [
          'src/components/ChatWindow.tsx',
          'src/components/MessageList.tsx',
          'src/hooks/useMessages.ts'
        ]
      end
      
      files
    end
    
    def extract_dependencies(files)
      # Extract from planned files
      deps = ['react', 'react-dom', '@supabase/supabase-js', 'tailwindcss']
      
      # Add based on features
      deps << 'react-router-dom' if files.any? { |f| f.include?('router') }
      deps << 'framer-motion' if @requirements[:features].include?('animations')
      
      deps
    end
    
    def check_missing_dependencies(deps)
      # Check against package.json if it exists
      package_json = app.app_files.find_by(path: 'package.json')
      return deps unless package_json
      
      begin
        existing = JSON.parse(package_json.content)['dependencies']&.keys || []
        deps - existing
      rescue JSON::ParserError
        deps
      end
    end
    
    def update_package_json_dependencies(deps)
      # Update package.json with missing dependencies
      package_json_file = app.app_files.find_by(path: 'package.json')
      return unless package_json_file
      
      begin
        package_json = JSON.parse(package_json_file.content)
        package_json['dependencies'] ||= {}
        
        deps.each do |dep|
          package_json['dependencies'][dep] ||= 'latest'
        end
        
        package_json_file.update!(content: JSON.pretty_generate(package_json))
        Rails.logger.info "[AppBuilderV4Enhanced] Updated package.json with #{deps.count} dependencies"
      rescue => e
        Rails.logger.warn "[AppBuilderV4Enhanced] Could not update package.json: #{e.message}"
      end
    end
    
    def generate_feature_files_with_ai
      # This would call Claude/GPT to generate files
      # For now, return mock data
      []
    end
    
    def wait_for_approval(callback_id, timeout:)
      # In real implementation, this would wait for WebSocket response
      true
    end
    
    def generate_diff(old_content, new_content)
      # Generate a simple diff preview
      "- #{old_content.lines.first(3).join}\n+ #{new_content.lines.first(3).join}"
    end
    
    def detect_app_type(content)
      case content.downcase
      when /todo|task/
        'todo'
      when /chat|message/
        'chat'
      when /blog|post/
        'blog'
      else
        'generic'
      end
    end
    
    def extract_features(content)
      features = []
      features << 'animations' if content.match?(/animat|smooth|transition/i)
      features << 'auth' if content.match?(/login|auth|user/i)
      features << 'database' if content.match?(/data|store|save/i)
      features
    end
    
    def extract_app_description
      # Extract from chat message
      chat_message.content.lines.first(2).join(' ').truncate(200)
    end
    
    def simplify_error_message(technical_error)
      case technical_error
      when /PG::UniqueViolation/
        "A file with this name already exists"
      when /duplicate key/i
        "Some files already exist in this app"
      when /undefined method/
        "There was a problem generating your app"
      when /SyntaxError/
        "The generated code has syntax errors"
      else
        technical_error.split("\n").first
      end
    end
  end
end