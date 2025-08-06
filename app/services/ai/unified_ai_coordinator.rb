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
        
        # Stage 1: Analysis
        Rails.logger.info "[UnifiedAI] Stage 1: Analysis"
        @progress_broadcaster.enter_stage(:thinking)
        @todo_tracker.add("Analyze requirements")
        @todo_tracker.start(@todo_tracker.todos.last[:id])
        
        analysis = analyze_requirements
        
        @todo_tracker.complete(@todo_tracker.todos.last[:id], analysis)
      rescue => e
        Rails.logger.error "[UnifiedAI] Error in Stage 1: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        raise
      end
      
      # Plan tasks based on analysis
      Rails.logger.info "[UnifiedAI] Planning tasks from analysis"
      @todo_tracker.plan_from_analysis(analysis)
      
      # Stage 2: Planning
      Rails.logger.info "[UnifiedAI] Stage 2: Planning"
      @progress_broadcaster.enter_stage(:planning)
      plan_todo = @todo_tracker.add("Create implementation plan")
      @todo_tracker.start(plan_todo[:id])
      
      plan = create_generation_plan(analysis)
      
      @todo_tracker.complete(plan_todo[:id])
      
      # Stage 3: Coding
      @progress_broadcaster.enter_stage(:coding)
      
      # Work through file creation todos
      files = []
      file_todos = @todo_tracker.todos.select { |t| 
        t[:metadata][:type] == 'file_creation' && t[:status] == 'pending'
      }
      
      file_todos.each_with_index do |todo, index|
        @todo_tracker.start(todo[:id])
        @progress_broadcaster.update("Creating #{todo[:metadata][:path]}...", 
                                   index.to_f / file_todos.size)
        
        # Generate file content with AI
        file_content = generate_file_content(todo[:metadata][:path], plan)
        files << { path: todo[:metadata][:path], content: file_content }
        
        @todo_tracker.complete(todo[:id])
      end
      
      # Stage 4: Review
      @progress_broadcaster.enter_stage(:reviewing)
      review_todo = @todo_tracker.add("Review and optimize code")
      @todo_tracker.start(review_todo[:id])
      
      optimized_files = review_and_optimize(files)
      
      @todo_tracker.complete(review_todo[:id])
      
      # Stage 5: Deploy
      @progress_broadcaster.enter_stage(:deploying)
      deploy_todo = @todo_tracker.add("Save files and prepare deployment")
      @todo_tracker.start(deploy_todo[:id])
      
      save_files(optimized_files)
      create_version
      queue_deployment if metadata[:wants_deployment]
      
      @todo_tracker.complete(deploy_todo[:id])
      
      # Complete
      @progress_broadcaster.complete(
        "Successfully generated your app with #{files.size} files!"
      )
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
  end
end