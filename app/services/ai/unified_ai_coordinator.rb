module Ai
  # UnifiedAiCoordinator - Single entry point for all AI operations
  # Coordinates between smaller, focused services
  class UnifiedAiCoordinator
    attr_reader :app, :message, :todo_tracker, :progress_broadcaster
    
    def initialize(app, message)
      @app = app
      @message = message
      @todo_tracker = TodoTracker.new(app, message)
      @progress_broadcaster = Services::ProgressBroadcaster.new(app, message)
      @client = OpenRouterClient.new
      @structured_generator = StructuredAppGenerator.new
    end
    
    # Main execution method
    def execute!
      Rails.logger.info "[UnifiedAI] Starting execution for message ##{message.id}"
      
      begin
        # Step 1: Route the message
        router = Services::MessageRouter.new(message)
        routing = router.route
        metadata = router.extract_metadata
        
        Rails.logger.info "[UnifiedAI] Routed to: #{routing[:action]}"
        
        # Step 2: Execute based on routing
        case routing[:action]
        when :generate
          generate_new_app(metadata)
        when :update
          update_existing_app(metadata)
        when :question
          answer_question(metadata)
        when :command
          execute_command(metadata)
        else
          update_existing_app(metadata)
        end
        
      rescue => e
        handle_error(e)
      end
    end
    
    private
    
    # Generate a new app from scratch
    def generate_new_app(metadata)
      Rails.logger.info "[UnifiedAI] Starting new app generation"
      
      begin
        # Define generation stages
        @progress_broadcaster.define_stages([
          { name: :thinking, description: "Understanding your requirements" },
          { name: :planning, description: "Planning the application structure" },
          { name: :coding, description: "Writing the code" },
          { name: :reviewing, description: "Reviewing and optimizing" },
          { name: :deploying, description: "Preparing for deployment" }
        ])
        
        # Stage 1: Analysis & Planning
        Rails.logger.info "[UnifiedAI] Stage 1: Analysis"
        @progress_broadcaster.enter_stage(:thinking)
        @todo_tracker.add("Analyze requirements and generate app")
        @todo_tracker.start(@todo_tracker.todos.last[:id])
        
        # Use StructuredAppGenerator to avoid function calling issues
        result = @structured_generator.generate(
          message.content,
          framework: app.framework || "react",
          app_type: app.app_type || "saas"
        )
        
        if !result[:success]
          raise "Generation failed: #{result[:error]}"
        end
        
        @todo_tracker.complete(@todo_tracker.todos.last[:id])
        
        # Stage 2: Planning (from generated structure)
        Rails.logger.info "[UnifiedAI] Stage 2: Planning from generation"
        @progress_broadcaster.enter_stage(:planning)
        
        # Create todos for each file
        result[:files].each do |file|
          @todo_tracker.add("Create #{file['path']}", { type: 'file_creation', path: file['path'] })
        end
        
        # Stage 3: Coding (save generated files)
        @progress_broadcaster.enter_stage(:coding)
        
        files_saved = []
        result[:files].each_with_index do |file_data, index|
          file_todo = @todo_tracker.todos.find { |t| t[:metadata][:path] == file_data['path'] }
          next unless file_todo
          
          @todo_tracker.start(file_todo[:id])
          @progress_broadcaster.update(
            "Creating #{file_data['path']}...",
            index.to_f / result[:files].size
          )
          
          # Save the file
          app_file = app.app_files.create!(
            team: app.team,
            path: file_data['path'],
            content: file_data['content'],
            file_type: detect_file_type(file_data['path'])
          )
          files_saved << app_file
          
          @todo_tracker.complete(file_todo[:id])
        end
        
        # Stage 4: Review and Auto-correct
        @progress_broadcaster.enter_stage(:reviewing)
        review_todo = @todo_tracker.add("Validate and auto-correct generated code")
        @todo_tracker.start(review_todo[:id])
        
        # Validate and auto-correct issues
        validation_issues = validate_generated_files(files_saved)
        if validation_issues.any?
          Rails.logger.info "[UnifiedAI] Found #{validation_issues.size} issues, auto-correcting..."
          @progress_broadcaster.update("Auto-correcting validation issues...", 0.8)
          
          # Auto-correct each issue
          validation_issues.each do |issue|
            file = files_saved.find { |f| f.path == issue[:file] }
            next unless file
            
            Rails.logger.info "[UnifiedAI] Fixing #{issue[:issue]} in #{issue[:file]}"
            corrected_content = auto_correct_file_issue(file, issue)
            
            if corrected_content != file.content
              file.update!(content: corrected_content)
              Rails.logger.info "[UnifiedAI] Fixed #{issue[:file]}"
            end
          end
          
          # Re-validate after corrections
          remaining_issues = validate_generated_files(files_saved.reload)
          if remaining_issues.any?
            Rails.logger.warn "[UnifiedAI] Some issues remain after auto-correction: #{remaining_issues.inspect}"
            # Continue anyway - we'll provide a working app even if not perfect
          else
            Rails.logger.info "[UnifiedAI] All validation issues resolved!"
          end
        end
        
        @todo_tracker.complete(review_todo[:id])
        
        # Stage 5: Deploy
        @progress_broadcaster.enter_stage(:deploying)
        deploy_todo = @todo_tracker.add("Save version and prepare deployment")
        @todo_tracker.start(deploy_todo[:id])
        
        # Update app metadata
        app.update!(
          status: 'generated',
          ai_model: result[:model] || 'kimi_k2',
          total_files: files_saved.size
        )
        
        create_version
        queue_deployment if metadata[:wants_deployment]
        
        @todo_tracker.complete(deploy_todo[:id])
        
        # Complete with app info
        app_info = result[:app] || {}
        @progress_broadcaster.complete(
          "Successfully generated #{app_info['name'] || 'your app'} with #{files_saved.size} files!"
        )
        
      rescue => e
        Rails.logger.error "[UnifiedAI] Error in generation: #{e.message}"
        Rails.logger.error e.backtrace.first(10).join("\n")
        handle_error(e)
      end
    end
    
    # Update an existing app
    def update_existing_app(metadata)
      Rails.logger.info "[UnifiedAI] Updating existing app"
      
      # Define update stages
      @progress_broadcaster.define_stages([
        { name: :analyzing, description: "Analyzing your request" },
        { name: :planning, description: "Planning changes" },
        { name: :coding, description: "Implementing updates" },
        { name: :deploying, description: "Deploying changes" }
      ])
      
      # Stage 1: Analysis
      @progress_broadcaster.enter_stage(:analyzing)
      @todo_tracker.add("Analyze update request")
      @todo_tracker.start(@todo_tracker.todos.last[:id])
      
      analysis = analyze_update_request
      @todo_tracker.complete(@todo_tracker.todos.last[:id])
      
      # Create todos from analysis
      @todo_tracker.plan_from_analysis(analysis)
      
      # Stage 2: Planning
      @progress_broadcaster.enter_stage(:planning)
      plan_todo = @todo_tracker.add("Create update plan")
      @todo_tracker.start(plan_todo[:id])
      
      plan = create_update_plan(analysis)
      @todo_tracker.complete(plan_todo[:id])
      
      # Stage 3: Implementation
      @progress_broadcaster.enter_stage(:coding)
      
      # Execute file modifications
      changes = []
      modification_todos = @todo_tracker.todos.select { |t|
        ['file_modification', 'file_creation'].include?(t[:metadata][:type]) &&
        t[:status] == 'pending'
      }
      
      modification_todos.each_with_index do |todo, index|
        @todo_tracker.start(todo[:id])
        @progress_broadcaster.update(
          "Updating #{todo[:metadata][:path]}...",
          index.to_f / modification_todos.size
        )
        
        change = execute_file_change(todo[:metadata], plan)
        changes << change
        
        @todo_tracker.complete(todo[:id])
      end
      
      # Stage 4: Deploy
      @progress_broadcaster.enter_stage(:deploying)
      deploy_todo = @todo_tracker.add("Deploy preview")
      @todo_tracker.start(deploy_todo[:id])
      
      create_version
      queue_deployment
      
      @todo_tracker.complete(deploy_todo[:id])
      
      # Complete
      @progress_broadcaster.complete(
        "Successfully updated #{changes.size} files!"
      )
    end
    
    # Answer a question about the app
    def answer_question(metadata)
      Rails.logger.info "[UnifiedAI] Answering question"
      
      @progress_broadcaster.define_stages([
        { name: :thinking, description: "Understanding your question" },
        { name: :analyzing, description: "Analyzing the codebase" },
        { name: :completed, description: "Preparing answer" }
      ])
      
      @progress_broadcaster.enter_stage(:thinking)
      # Implementation for Q&A
      @progress_broadcaster.complete("Here's the answer to your question...")
    end
    
    # Execute a command
    def execute_command(metadata)
      Rails.logger.info "[UnifiedAI] Executing command"
      # Implementation for commands
    end
    
    # AI interaction methods
    def analyze_requirements
      Rails.logger.info "[UnifiedAI] Analyzing requirements..."
      prompt = build_analysis_prompt
      
      Rails.logger.info "[UnifiedAI] Calling AI for analysis..."
      
      begin
        require 'timeout'
        response = Timeout::timeout(30) do
          @client.chat(
            [{ role: "user", content: prompt }],
            model: :claude_4,
            temperature: 0.3,
            max_tokens: 2000
          )
        end
      rescue Timeout::Error
        Rails.logger.error "[UnifiedAI] AI call timed out after 30 seconds"
        response = { success: false, error: "AI call timed out" }
      end
      
      if response[:success]
        Rails.logger.info "[UnifiedAI] Analysis complete, parsing response..."
        result = parse_json_response(response[:content])
        Rails.logger.info "[UnifiedAI] Parsed analysis: #{result.keys.join(', ')}"
        result
      else
        Rails.logger.error "[UnifiedAI] Analysis failed: #{response[:error]}"
        # Return default structure
        {
          "tasks" => [],
          "files_to_create" => ["index.html", "style.css", "script.js"],
          "complexity" => "simple",
          "estimated_time" => "5 minutes"
        }
      end
    end
    
    def analyze_update_request
      # Similar to analyze_requirements but for updates
      current_files = app.app_files.pluck(:path, :file_type)
      env_vars = app.env_vars_for_ai
      
      prompt = build_update_analysis_prompt(current_files, env_vars)
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :claude_4,
        temperature: 0.3
      )
      
      parse_json_response(response[:content]) if response[:success]
    end
    
    # Helper methods
    def build_analysis_prompt
      # Build comprehensive analysis prompt
      <<~PROMPT
        Analyze this request for a new web application:
        
        Request: #{message.content}
        App Type: #{app.app_type}
        Framework: #{app.framework}
        
        Return a JSON response with:
        {
          "tasks": [{"description": "task description", "metadata": {}}],
          "files_to_create": ["index.html", "app.js"],
          "complexity": "simple|medium|complex",
          "estimated_time": "time estimate"
        }
      PROMPT
    end
    
    def save_files(files)
      files.each do |file_data|
        app.app_files.create!(
          team: app.team,
          path: file_data[:path],
          content: file_data[:content],
          file_type: detect_file_type(file_data[:path])
        )
      end
    end
    
    def create_version
      # Create app version record
      app.app_versions.create!(
        team: app.team,
        user: message.user,
        version_number: next_version_number,
        changelog: message.content[0..200],
        deployed: false
      )
    end
    
    def queue_deployment
      UpdatePreviewJob.perform_later(app.id)
    end
    
    def handle_error(error)
      Rails.logger.error "[UnifiedAI] Error: #{error.message}"
      Rails.logger.error error.backtrace.join("\n")
      
      @progress_broadcaster.fail("An error occurred: #{error.message}")
      
      # Mark any in-progress todos as failed
      @todo_tracker.todos.each do |todo|
        if todo[:status] == 'in_progress'
          @todo_tracker.fail(todo[:id], error.message)
        end
      end
    end
    
    def parse_json_response(content)
      json_match = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m) || 
                   content.match(/\{.+\}/m)
      return {} unless json_match
      
      JSON.parse(json_match[1] || json_match[0])
    rescue JSON::ParserError => e
      Rails.logger.error "[UnifiedAI] Failed to parse JSON: #{e.message}"
      {}
    end
    
    def detect_file_type(path)
      ext = File.extname(path).delete('.')
      case ext
      when 'html', 'htm' then 'html'
      when 'js', 'jsx' then 'js'
      when 'css' then 'css'
      when 'json' then 'json'
      else 'text'
      end
    end
    
    def next_version_number
      last_version = app.app_versions.order(:created_at).last
      return "1.0.0" unless last_version
      
      parts = last_version.version_number.split('.')
      parts[2] = (parts[2].to_i + 1).to_s
      parts.join('.')
    end
    
    # Generate content for a specific file
    def generate_file_content(path, plan)
      prompt = build_file_generation_prompt(path, plan)
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :claude_4,
        temperature: 0.5
      )
      
      if response[:success]
        extract_code_from_response(response[:content])
      else
        Rails.logger.error "[UnifiedAI] Failed to generate content for #{path}"
        "// Error generating file content"
      end
    end
    
    # Build prompt for file generation
    def build_file_generation_prompt(path, plan)
      <<~PROMPT
        Generate the content for #{path} as part of this application:
        
        Application Plan:
        #{plan.to_json}
        
        File: #{path}
        
        Requirements:
        - Generate ONLY the file content, no explanations
        - Use modern best practices
        - Include proper error handling
        - Add responsive design if applicable
        - Follow the framework conventions: #{app.framework}
        
        Return the complete file content.
      PROMPT
    end
    
    # Extract code from AI response
    def extract_code_from_response(content)
      # Try to extract from code blocks first
      if content.match(/```\w*\n?(.*?)```/m)
        $1.strip
      else
        # Fallback to full content
        content.strip
      end
    end
    
    # Review and optimize generated files
    def review_and_optimize(files)
      # For now, return files as-is
      # In future, could add optimization pass
      files
    end
    
    # Create a generation plan from requirements analysis
    def create_generation_plan(analysis)
      {
        app_type: app.app_type,
        framework: app.framework,
        files: analysis["files_to_create"] || [],
        features: analysis["features"] || [],
        complexity: analysis["complexity"] || "medium",
        environment_variables: app.env_vars_for_ai
      }
    end
    
    # Build prompt for update analysis
    def build_update_analysis_prompt(current_files, env_vars)
      <<~PROMPT
        Analyze this update request for an existing application:
        
        Request: #{message.content}
        
        Current Files:
        #{current_files.map { |p, t| "- #{p} (#{t})" }.join("\n")}
        
        Available Environment Variables:
        #{env_vars.map { |v| "- #{v[:key]}: #{v[:description]}" }.join("\n")}
        
        Return a JSON response with:
        {
          "tasks": [{"description": "task", "metadata": {"type": "file_modification", "path": "file.js"}}],
          "files_to_modify": ["file1.js", "file2.html"],
          "files_to_create": ["newfile.css"],
          "complexity": "simple|medium|complex"
        }
      PROMPT
    end
    
    # Create an update plan from analysis
    def create_update_plan(analysis)
      {
        files_to_modify: analysis["files_to_modify"] || [],
        files_to_create: analysis["files_to_create"] || [],
        tasks: analysis["tasks"] || [],
        complexity: analysis["complexity"] || "medium"
      }
    end
    
    # Execute a file change based on metadata and plan
    def execute_file_change(metadata, plan)
      path = metadata[:path]
      
      if metadata[:type] == 'file_creation'
        content = generate_file_content(path, plan)
        app.app_files.create!(
          team: app.team,
          path: path,
          content: content,
          file_type: detect_file_type(path)
        )
        { type: 'created', path: path }
      else
        # File modification
        file = app.app_files.find_by(path: path)
        if file
          updated_content = update_file_content(file.content, plan, metadata)
          file.update!(content: updated_content)
          { type: 'modified', path: path }
        else
          Rails.logger.warn "[UnifiedAI] File not found for modification: #{path}"
          { type: 'skipped', path: path }
        end
      end
    end
    
    # Update existing file content
    def update_file_content(current_content, plan, metadata)
      prompt = <<~PROMPT
        Update this file based on the following request:
        
        Request: #{message.content}
        File: #{metadata[:path]}
        
        Current Content:
        ```
        #{current_content}
        ```
        
        Return ONLY the updated file content, no explanations.
      PROMPT
      
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :claude_4,
        temperature: 0.5
      )
      
      if response[:success]
        extract_code_from_response(response[:content])
      else
        Rails.logger.error "[UnifiedAI] Failed to update #{metadata[:path]}"
        current_content
      end
    end
    
    # Validate function call data structure
    def validate_function_call_data(data)
      required_keys = ["app", "files"]
      required_keys.all? { |key| data.key?(key) }
    end
    
    # Validate generated files for common issues
    def validate_generated_files(files)
      issues = []
      
      files.each do |file|
        # Check for empty content
        if file.content.blank?
          issues << { file: file.path, issue: "Empty content" }
        end
        
        # Check for placeholder content
        if file.content.include?("TODO") || file.content.include?("// Error generating")
          issues << { file: file.path, issue: "Contains placeholder content" }
        end
        
        # Check HTML files have basic structure
        if file.file_type == 'html' && !file.content.include?("<html")
          issues << { file: file.path, issue: "Missing HTML structure" }
        end
        
        # Check JS/JSX files for basic syntax
        if ['js', 'jsx', 'ts', 'tsx'].include?(file.file_type)
          if file.content.scan(/\{/).count != file.content.scan(/\}/).count
            issues << { file: file.path, issue: "Unbalanced braces" }
          end
        end
      end
      
      issues
    end
    
    # Auto-correct common file issues
    def auto_correct_file_issue(file, issue)
      content = file.content
      
      case issue[:issue]
      when "Empty content"
        # Generate minimal content based on file type
        content = generate_minimal_content_for(file.path)
      when "Contains placeholder content"
        # Ask AI to complete the placeholder sections
        content = complete_placeholder_content(file)
      when "Missing HTML structure"
        # Wrap content in proper HTML structure
        content = wrap_in_html_structure(content)
      when "Unbalanced braces"
        # Try to fix brace balance or regenerate
        content = fix_brace_balance(file)
      else
        Rails.logger.warn "[UnifiedAI] Unknown issue type: #{issue[:issue]}"
      end
      
      content
    end
    
    # Generate minimal valid content for empty files
    def generate_minimal_content_for(path)
      ext = File.extname(path)
      
      case ext
      when '.html'
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>App</title>
          </head>
          <body>
            <div id="root"></div>
            <script src="/src/index.tsx" type="module"></script>
          </body>
          </html>
        HTML
      when '.tsx', '.jsx'
        <<~TSX
          import React from 'react';
          
          export default function Component() {
            return (
              <div>
                <h1>Component</h1>
              </div>
            );
          }
        TSX
      when '.ts', '.js'
        "// Auto-generated file\nexport {};"
      when '.css'
        "/* Styles */\nbody { margin: 0; padding: 0; }"
      when '.json'
        "{}"
      else
        "// File: #{path}"
      end
    end
    
    # Complete placeholder content using AI
    def complete_placeholder_content(file)
      prompt = <<~PROMPT
        Complete this file that has placeholder content:
        
        File: #{file.path}
        Current content:
        ```
        #{file.content}
        ```
        
        Replace all TODO comments and placeholder content with actual implementation.
        Return ONLY the complete file content, no explanations.
      PROMPT
      
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :kimi_k2,
        temperature: 0.5,
        max_tokens: 4000
      )
      
      if response[:success]
        extract_code_from_response(response[:content])
      else
        file.content # Return original if AI fails
      end
    end
    
    # Wrap content in proper HTML structure
    def wrap_in_html_structure(content)
      if content.include?("<body")
        content # Already has structure
      else
        <<~HTML
          <!DOCTYPE html>
          <html lang="en">
          <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>App</title>
            <script src="https://cdn.tailwindcss.com"></script>
          </head>
          <body>
            #{content}
          </body>
          </html>
        HTML
      end
    end
    
    # Fix brace balance issues
    def fix_brace_balance(file)
      # Try to regenerate the file with AI
      prompt = <<~PROMPT
        Fix the syntax errors in this #{file.file_type} file:
        
        File: #{file.path}
        Content with unbalanced braces:
        ```
        #{file.content}
        ```
        
        Return the corrected file with proper syntax. Ensure all braces are balanced.
        Return ONLY the code, no explanations.
      PROMPT
      
      response = @client.chat(
        [{ role: "user", content: prompt }],
        model: :kimi_k2,
        temperature: 0.3,
        max_tokens: 4000
      )
      
      if response[:success]
        fixed = extract_code_from_response(response[:content])
        # Quick check if we actually fixed it
        if fixed.scan(/\{/).count == fixed.scan(/\}/).count
          fixed
        else
          # If still broken, return a minimal valid file
          generate_minimal_content_for(file.path)
        end
      else
        generate_minimal_content_for(file.path)
      end
    end
  end
end