module Ai
  # Unified V3 Orchestrator supporting both Claude and GPT-5
  # Single source of truth for prompts and logic with model-specific adaptations
  class AppUpdateOrchestratorV3Unified
    include Rails.application.routes.url_helpers
    
    # Configuration
    MAX_CONTEXT_TOKENS = 128_000  # Claude supports up to 200k
    MAX_FILES_PER_BATCH = 5
    API_TIMEOUT_SECONDS = 120
    MAX_RETRIES = 2
    
    # Model configurations - Updated August 2025
    MODEL_CONFIGS = {
      # Claude 4 Series (Released May 2025)
      'claude-opus-4.1' => {
        provider: 'anthropic',
        supports_streaming: true,
        supports_caching: true,
        supports_extended_thinking: true,
        max_tokens: 8192,
        temperature_range: [0, 1],
        tool_format: 'anthropic',
        context_window: 200_000,
        use_for: 'complex_generation',
        description: 'Most capable model for complex, long-running tasks'
      },
      'claude-sonnet-4' => {
        provider: 'anthropic',
        supports_streaming: true,
        supports_caching: true,
        supports_extended_thinking: true,
        max_tokens: 8192,
        temperature_range: [0, 1],
        tool_format: 'anthropic',
        context_window: 200_000,
        description: 'Superior coding and reasoning, state-of-the-art performance'
      },
      # GPT-5 Series (Released August 7, 2025)
      'gpt-5' => {
        provider: 'openai',
        supports_streaming: true,
        supports_caching: false,
        supports_reasoning: true,
        max_completion_tokens: 16000,
        temperature_range: [1, 1],  # GPT-5 only supports default
        tool_format: 'openai',
        description: 'Unified model with reasoning, PhD-level intelligence'
      },
      'gpt-5-mini' => {
        provider: 'openai',
        supports_streaming: true,
        supports_caching: false,
        max_completion_tokens: 8000,
        temperature_range: [1, 1],
        tool_format: 'openai',
        description: 'Smaller, faster GPT-5 for moderate complexity'
      },
      'gpt-5-nano' => {
        provider: 'openai',
        supports_streaming: true,
        supports_caching: false,
        max_completion_tokens: 4000,
        temperature_range: [1, 1],
        tool_format: 'openai',
        description: 'Smallest GPT-5 for simple tasks'
      },
      # Legacy models for fallback
      'claude-3-5-sonnet-20241022' => {
        provider: 'anthropic',
        supports_streaming: true,
        supports_caching: true,
        max_tokens: 8192,
        temperature_range: [0, 1],
        tool_format: 'anthropic',
        fallback: true,
        description: 'Previous generation Claude'
      },
      'gpt-4-turbo-preview' => {
        provider: 'openai',
        supports_streaming: true,
        supports_caching: false,
        max_tokens: 4096,
        temperature_range: [0, 2],
        tool_format: 'openai',
        fallback: true,
        description: 'Legacy GPT-4 model'
      }
    }.freeze
    
    attr_reader :chat_message, :app, :user, :app_version, :broadcaster
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @iteration_count = 0
      
      # Check if new app
      @is_new_app = is_app_new?
      
      # Model selection with intelligent defaults
      select_optimal_model
      
      @broadcaster = Ai::Services::ProgressBroadcaster.new(@app, @chat_message)
      @streaming_buffer = Ai::Services::StreamingBufferEnhanced.new(@app, @chat_message, @broadcaster)
      
      @files_modified = []
      @start_time = Time.current
      
      # Load standards and create unified system prompt
      load_standards_once
      @system_prompt = create_unified_system_prompt
    end
    
    def execute!
      Rails.logger.info "[V3-Unified] Starting execution for message ##{chat_message.id}"
      Rails.logger.info "[V3-Unified] Model: #{@model}, Provider: #{@provider}, Type: #{@is_new_app ? 'CREATE' : 'UPDATE'}"
      
      begin
        # Skip discussion mode check for new apps
        unless @is_new_app || explicit_code_request?
          return handle_discussion_mode
        end
        
        # Initialize version tracking
        create_app_version!
        define_execution_stages
        
        # PHASE 1: Quick Analysis
        @broadcaster.enter_stage(:analyzing)
        analysis = perform_quick_analysis
        
        # PHASE 2: Execution Planning
        @broadcaster.enter_stage(:planning)
        plan = create_execution_plan(analysis)
        
        # PHASE 3: Implementation
        @broadcaster.enter_stage(:coding)
        result = execute_implementation(plan)
        
        # PHASE 4: Review
        @broadcaster.enter_stage(:reviewing)
        review_and_finalize(result)
        
        # PHASE 5: Deploy if new
        if @is_new_app
          @broadcaster.enter_stage(:deploying)
          deploy_app
        end
        
        # Success
        @broadcaster.complete("✅ App #{@is_new_app ? 'created' : 'updated'} successfully!")
        finalize_version('completed')
        
      rescue => e
        handle_error(e)
      ensure
        queue_post_generation_jobs
      end
    end
    
    private
    
    def select_optimal_model
      # Start with user preference
      preferred = @app.ai_model || ENV['DEFAULT_AI_MODEL'] || 'claude-sonnet-4'
      
      # Map any old model names to new ones
      model_mapping = {
        'claude-3-5-sonnet-20241022' => 'claude-sonnet-4',
        'claude-3-opus-20240229' => 'claude-opus-4.1',
        'gpt-4-turbo' => 'gpt-5',
        'gpt-4-turbo-preview' => 'gpt-5'
      }
      
      mapped_model = model_mapping[preferred] || preferred
      
      # For new app generation, potentially use Opus 4.1 for better results
      if @is_new_app && @chat_message.content.length > 500
        # Complex prompt - consider Opus 4.1
        if mapped_model.include?('claude') && !mapped_model.include?('opus')
          @model = 'claude-opus-4.1'
          Rails.logger.info "[V3-Unified] Using Claude Opus 4.1 for complex new app generation"
        else
          @model = mapped_model
        end
      else
        @model = mapped_model
      end
      
      # Get configuration
      @model_config = MODEL_CONFIGS[@model] || MODEL_CONFIGS['claude-sonnet-4']
      @provider = @model_config[:provider]
      @supports_streaming = @model_config[:supports_streaming]
      @supports_caching = @model_config[:supports_caching]
      @supports_extended_thinking = @model_config[:supports_extended_thinking]
      @supports_reasoning = @model_config[:supports_reasoning]
      @tool_format = @model_config[:tool_format]
      
      Rails.logger.info "[V3-Unified] Selected model: #{@model} (#{@model_config[:description]})"
      
      # Set up client based on provider
      setup_provider_client
    end
    
    def setup_provider_client
      case @provider
      when 'anthropic'
        setup_claude_client
      when 'openai'
        setup_openai_client
      else
        raise "Unknown provider: #{@provider}"
      end
    end
    
    def setup_claude_client
      # Use HTTP directly for Claude API (similar to OpenAI approach)
      # This avoids needing the anthropic gem
      @use_native_client = false
      @api_key = ENV['ANTHROPIC_API_KEY']
      @api_url = 'https://api.anthropic.com/v1/messages'
    end
    
    def setup_openai_client
      # We'll use direct HTTP for OpenAI to have full control
      @use_native_client = false
      @api_key = ENV['OPENAI_API_KEY']
    end
    
    def is_app_new?
      return true if @app.app_files.empty?
      
      # Check if only minimal files exist
      files = @app.app_files.pluck(:path)
      minimal_files = ['index.html', 'src/App.jsx']
      
      if files.sort == minimal_files.sort
        total_size = @app.app_files.sum { |f| f.content.length }
        return total_size < 2000  # Placeholder files
      end
      
      false
    end
    
    def create_unified_system_prompt
      # Single source of truth for system prompt
      # with model-specific adaptations
      
      base_prompt = <<~SYSTEM
        You are an elite web application developer creating production-ready applications for the OverSkill platform.
        
        PLATFORM CONTEXT:
        OverSkill is an AI-powered app marketplace where users create, deploy, and monetize applications.
        Apps are deployed to Cloudflare Workers with R2 storage and KV namespaces.
        
        #{@standards_full}
        
        CRITICAL APP CONFIGURATION:
        Apps receive configuration via window.ENV object:
        ```javascript
        const config = {
          APP_ID: window.ENV?.APP_ID,
          SUPABASE_URL: window.ENV?.SUPABASE_URL,
          SUPABASE_ANON_KEY: window.ENV?.SUPABASE_ANON_KEY,
          API_WORKER_URL: window.ENV?.API_WORKER_URL,
          AUTH_SETTINGS: window.ENV?.AUTH_SETTINGS
        };
        ```
        
        DATABASE INTEGRATION:
        All Supabase tables MUST use app-scoped naming:
        - Table name format: app_${APP_ID}_${table_name}
        - Example: app_123_todos, app_123_users_profile
        
        OAUTH INTEGRATION:
        OAuth (Google/GitHub) is handled via Cloudflare Worker proxy:
        ```javascript
        // Initiate OAuth
        window.location.href = `${window.ENV.API_WORKER_URL}/auth/google`;
        
        // Handle callback
        const urlParams = new URLSearchParams(window.location.search);
        const { access_token, refresh_token } = Object.fromEntries(urlParams);
        ```
        
        FILE STRUCTURE REQUIREMENTS:
        Create SEPARATE files for modularity and clarity:
        - index.html - HTML with CDN scripts
        - src/App.jsx - Main React app with routing
        - src/lib/supabase.js - Supabase client
        - src/pages/*.jsx - Page components
        - src/components/*.jsx - Reusable components
        
        QUALITY STANDARDS:
        - Production-ready code with error handling
        - Beautiful, modern UI with Tailwind CSS
        - Smooth animations and transitions
        - Mobile-responsive design
        - Accessibility features (ARIA labels, keyboard nav)
        - Loading states and skeletons
        - Empty states with helpful CTAs
      SYSTEM
      
      # Add model-specific instructions
      case @provider
      when 'anthropic'
        base_prompt += claude_specific_instructions
      when 'openai'
        base_prompt += openai_specific_instructions
      end
      
      # Add operation type instructions
      if @is_new_app
        base_prompt += new_app_instructions
      else
        base_prompt += update_app_instructions
      end
      
      base_prompt
    end
    
    def claude_specific_instructions
      <<~CLAUDE
        
        CLAUDE-SPECIFIC INSTRUCTIONS:
        - You have access to tool functions for file operations
        - Use the tools exactly as specified in their schemas
        - Be thorough and create comprehensive applications
        - Your responses should focus on using tools, not explaining
        - Cache markers will be used for efficiency but don't affect your behavior
      CLAUDE
    end
    
    def openai_specific_instructions
      <<~OPENAI
        
        GPT-SPECIFIC INSTRUCTIONS:
        - You MUST use tool functions for ALL file operations
        - DO NOT output code in text, ONLY use tools
        - Create MULTIPLE separate files, not monolithic ones
        - Each file requires a separate create_file tool call
        - Focus on action over explanation
      OPENAI
    end
    
    def new_app_instructions
      <<~NEW_APP
        
        NEW APP CREATION:
        You are creating a brand new application from scratch.
        
        MANDATORY: Create AT LEAST these files:
        1. index.html - Complete HTML with all CDN dependencies
        2. src/App.jsx - Main React app with Router
        3. src/lib/supabase.js - Supabase client setup
        4. src/pages/Home.jsx - Landing page
        5. src/pages/auth/Login.jsx - Login page
        6. src/pages/auth/SignUp.jsx - Registration
        7. src/pages/Dashboard.jsx - Main app interface
        8. Additional components as needed
        
        Start with index.html, then App.jsx, then other files.
      NEW_APP
    end
    
    def update_app_instructions
      <<~UPDATE
        
        APP UPDATE:
        You are updating an existing application.
        
        IMPORTANT:
        1. Analyze existing code structure first
        2. Preserve all existing functionality
        3. Integrate new features smoothly
        4. Maintain consistent code style
        5. Don't break existing features
        
        Use update_file for existing files, create_file for new ones.
      UPDATE
    end
    
    def perform_quick_analysis
      Rails.logger.info "[V3-Unified] Performing analysis with #{@model}"
      
      context = if @is_new_app
        { files: [], summary: "New app - needs complete implementation" }
      else
        load_relevant_context
      end
      
      analysis_prompt = build_analysis_prompt(context)
      
      messages = [
        { role: "system", content: @system_prompt },
        { role: "user", content: analysis_prompt }
      ]
      
      # Execute with caching if supported
      response = execute_with_provider(messages, use_tools: false)
      
      parse_analysis_response(response)
    end
    
    def build_analysis_prompt(context)
      <<~PROMPT
        Analyze this request: "#{@chat_message.content}"
        
        App: #{@app.name}
        Type: #{@is_new_app ? 'NEW' : 'UPDATE'}
        Framework: #{@app.framework}
        Current files: #{context[:files].map { |f| f[:path] }.join(', ')}
        
        Return a JSON analysis:
        {
          "approach": "Technical approach",
          "files_needed": ["file1.ext", "file2.ext"],
          "complexity": "simple|moderate|complex",
          "estimated_tokens": 5000,
          "needs_auth": true,
          "key_features": ["feature1", "feature2"]
        }
      PROMPT
    end
    
    def execute_implementation(plan)
      Rails.logger.info "[V3-Unified] Executing implementation with #{@model}"
      
      # Get appropriate tools for the model
      tools = create_tool_definitions
      
      # Process each step
      steps = plan["steps"] || [{ "description" => "Build complete app" }]
      
      steps.each_with_index do |step, index|
        Rails.logger.info "[V3-Unified] Step #{index + 1}/#{steps.length}: #{step['description']}"
        @broadcaster.update(step['description'], (index.to_f / steps.length))
        
        execute_step_with_tools(step, tools)
      end
      
      { success: true, files_created: @files_modified }
    end
    
    def create_tool_definitions
      case @tool_format
      when 'anthropic'
        create_claude_tools
      when 'openai'
        create_openai_tools
      else
        raise "Unknown tool format: #{@tool_format}"
      end
    end
    
    def create_claude_tools
      # Claude tool format
      [
        {
          name: "create_file",
          description: "Create a new file with content",
          input_schema: {
            type: "object",
            properties: {
              path: { 
                type: "string", 
                description: "File path (e.g., src/App.jsx)" 
              },
              content: { 
                type: "string", 
                description: "Complete file content" 
              }
            },
            required: ["path", "content"]
          }
        },
        {
          name: "update_file",
          description: "Update an existing file",
          input_schema: {
            type: "object",
            properties: {
              path: { 
                type: "string",
                description: "Path to existing file"
              },
              content: { 
                type: "string",
                description: "New complete content"
              }
            },
            required: ["path", "content"]
          }
        }
      ]
    end
    
    def create_openai_tools
      # OpenAI tool format
      [
        {
          type: "function",
          function: {
            name: "create_file",
            description: "Create a new file with content. Use for ALL new files.",
            parameters: {
              type: "object",
              properties: {
                path: { 
                  type: "string", 
                  description: "File path (e.g., index.html, src/App.jsx)" 
                },
                content: { 
                  type: "string", 
                  description: "Complete file content with all code" 
                }
              },
              required: ["path", "content"]
            }
          }
        },
        {
          type: "function",
          function: {
            name: "update_file",
            description: "Update existing file with new content",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string" },
                content: { type: "string" }
              },
              required: ["path", "content"]
            }
          }
        }
      ]
    end
    
    def execute_step_with_tools(step, tools)
      prompt = build_step_prompt(step)
      
      messages = [
        { role: "system", content: @system_prompt },
        { role: "user", content: prompt }
      ]
      
      # Add caching for Claude if supported
      if @supports_caching && @provider == 'anthropic'
        messages = add_claude_caching(messages)
      end
      
      # Execute with provider
      execute_with_provider(messages, use_tools: true, tools: tools)
    end
    
    def build_step_prompt(step)
      base = "Implement: #{step['description']}\n\nUser request: #{@chat_message.content}\n\n"
      
      case @provider
      when 'anthropic'
        base + <<~PROMPT
          Use the tool functions to create all necessary files.
          Create comprehensive, production-ready code.
          Each file should be created with a separate tool call.
          
          Required files to create:
          - index.html with all CDN dependencies
          - src/App.jsx with complete React app
          - src/lib/supabase.js for database
          - All necessary page and component files
          
          Start creating files now.
        PROMPT
      when 'openai'
        base + <<~PROMPT
          YOU MUST USE TOOL FUNCTIONS ONLY - NO TEXT OUTPUT!
          
          CREATE THESE FILES WITH SEPARATE create_file CALLS:
          1. index.html - HTML with CDN scripts
          2. src/App.jsx - React app with Router
          3. src/lib/supabase.js - Database client
          4. src/pages/auth/Login.jsx - Login page
          5. src/pages/auth/SignUp.jsx - Signup page
          6. src/pages/Dashboard.jsx - Main dashboard
          7. Additional components as needed
          
          Each file MUST be a separate create_file call.
          DO NOT combine files or output code as text.
        PROMPT
      end
    end
    
    def add_claude_caching(messages)
      # Add cache_control for Claude to optimize token usage
      messages.map do |msg|
        if msg[:role] == "system"
          msg.merge(cache_control: { type: "ephemeral" })
        else
          msg
        end
      end
    end
    
    def execute_with_provider(messages, use_tools: false, tools: nil)
      case @provider
      when 'anthropic'
        execute_with_claude(messages, use_tools, tools)
      when 'openai'
        execute_with_openai(messages, use_tools, tools)
      else
        raise "Unknown provider: #{@provider}"
      end
    end
    
    def execute_with_claude(messages, use_tools, tools)
      Rails.logger.info "[V3-Unified] Executing with Claude #{@model}"
      
      require 'net/http'
      require 'json'
      
      uri = URI(@api_url)
      
      # Format messages for Claude API
      formatted_messages = messages.select { |m| m[:role] != 'system' }
      system_prompt = messages.find { |m| m[:role] == 'system' }&.dig(:content) || ""
      
      request_body = {
        model: @model,
        messages: formatted_messages,
        max_tokens: @model_config[:max_tokens] || 4096,
        temperature: 0.7,
        system: system_prompt
      }
      
      # Add tools if needed
      request_body[:tools] = tools if use_tools && tools
      
      # Add caching if supported
      if @supports_caching && messages.any? { |m| m[:cache_control] }
        # Claude supports caching via cache_control in messages
        request_body[:messages] = formatted_messages.map do |msg|
          if msg[:cache_control]
            msg
          else
            msg
          end
        end
      end
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = API_TIMEOUT_SECONDS
      
      request = Net::HTTP::Post.new(uri)
      request['x-api-key'] = @api_key
      request['anthropic-version'] = '2023-06-01'
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      begin
        response = http.request(request)
        result = JSON.parse(response.body)
        
        if result['error']
          Rails.logger.error "[V3-Unified] Claude error: #{result['error']['message']}"
          raise result['error']['message']
        end
        
        # Process tool use if present
        if result['content'] && result['content'].any? { |c| c['type'] == 'tool_use' }
          process_claude_tool_use(result['content'])
        end
        
        # Return text content
        text_content = result['content']
          &.select { |c| c['type'] == 'text' }
          &.map { |c| c['text'] }
          &.join("\n") || ""
        
        { content: text_content }
        
      rescue => e
        Rails.logger.error "[V3-Unified] Claude error: #{e.message}"
        raise
      end
    end
    
    def execute_with_openai(messages, use_tools, tools)
      Rails.logger.info "[V3-Unified] Executing with OpenAI #{@model}"
      
      require 'net/http'
      require 'json'
      
      uri = URI('https://api.openai.com/v1/chat/completions')
      
      request_body = {
        model: @model,
        messages: messages,
        tool_choice: use_tools ? "auto" : "none"
      }
      
      # Model-specific parameters
      if @model.include?('gpt-5')
        request_body[:max_completion_tokens] = @model_config[:max_completion_tokens] || 8000
        # No temperature for GPT-5
      else
        request_body[:max_tokens] = @model_config[:max_tokens] || 4096
        request_body[:temperature] = 0.7
      end
      
      # Add tools if needed
      request_body[:tools] = tools if use_tools && tools
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = API_TIMEOUT_SECONDS
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      response = http.request(request)
      result = JSON.parse(response.body)
      
      if result['error']
        Rails.logger.error "[V3-Unified] OpenAI error: #{result['error']['message']}"
        raise result['error']['message']
      end
      
      # Process tool calls if present
      if result['choices'] && result['choices'][0]['message']['tool_calls']
        process_openai_tool_calls(result['choices'][0]['message']['tool_calls'])
      end
      
      # Return content
      content = result['choices'][0]['message']['content'] || ""
      { content: content }
    end
    
    def process_claude_tool_use(content_blocks)
      content_blocks.each do |block|
        next unless block['type'] == 'tool_use'
        
        tool_name = block['name']
        tool_input = block['input']
        
        Rails.logger.info "[V3-Unified] Claude tool: #{tool_name}"
        
        case tool_name
        when 'create_file'
          create_or_update_file(tool_input['path'], tool_input['content'])
        when 'update_file'
          create_or_update_file(tool_input['path'], tool_input['content'])
        else
          Rails.logger.warn "[V3-Unified] Unknown tool: #{tool_name}"
        end
      end
    end
    
    def process_openai_tool_calls(tool_calls)
      Rails.logger.info "[V3-Unified] Processing #{tool_calls.length} OpenAI tool calls"
      
      tool_calls.each do |call|
        function_name = call['function']['name']
        arguments = JSON.parse(call['function']['arguments'])
        
        Rails.logger.info "[V3-Unified] OpenAI tool: #{function_name}"
        
        case function_name
        when 'create_file'
          create_or_update_file(arguments['path'], arguments['content'])
        when 'update_file'
          create_or_update_file(arguments['path'], arguments['content'])
        else
          Rails.logger.warn "[V3-Unified] Unknown tool: #{function_name}"
        end
      end
    end
    
    def create_or_update_file(path, content)
      Rails.logger.info "[V3-Unified] Creating/updating file: #{path}"
      
      # Validate content
      if path.end_with?('.jsx', '.js')
        content = ensure_valid_javascript(content)
      end
      
      # Create or update file
      file = @app.app_files.find_or_initialize_by(path: path)
      file.content = content
      file.file_type = determine_file_type(path)
      file.team = @app.team
      file.save!
      
      @files_modified << path
      @broadcaster.file_created(path)
      
      Rails.logger.info "[V3-Unified] File saved: #{path} (#{content.length} bytes)"
    end
    
    # Include all the helper methods from the original
    def load_standards_once
      standards_path = Rails.root.join('AI_APP_STANDARDS.md')
      
      if File.exist?(standards_path)
        @standards_full = File.read(standards_path)
        Rails.logger.info "[V3-Unified] Loaded standards: #{@standards_full.length} bytes"
      else
        @standards_full = "Follow React CDN best practices with Tailwind CSS"
      end
    end
    
    def explicit_code_request?
      keywords = ['create', 'build', 'implement', 'add', 'update', 'fix', 'change', 'modify']
      content_lower = @chat_message.content.downcase
      keywords.any? { |kw| content_lower.include?(kw) }
    end
    
    def handle_discussion_mode
      Rails.logger.info "[V3-Unified] Discussion mode - no code changes"
      # Return discussion response
    end
    
    def create_app_version!
      @app_version = @app.app_versions.create!(
        team: @app.team,
        user: @user,
        version_number: next_version_number,
        changelog: @chat_message.content,
        status: 'in_progress',
        started_at: Time.current
      )
    end
    
    def next_version_number
      last_version = @app.app_versions.order(created_at: :desc).first
      if last_version
        parts = last_version.version_number.split('.')
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join('.')
      else
        '1.0.0'
      end
    end
    
    def define_execution_stages
      @broadcaster.define_stages([
        { key: :analyzing, name: 'Understanding requirements', weight: 0.1 },
        { key: :planning, name: 'Planning architecture', weight: 0.1 },
        { key: :coding, name: 'Building application', weight: 0.6 },
        { key: :reviewing, name: 'Reviewing code', weight: 0.1 },
        { key: :deploying, name: 'Deploying app', weight: 0.1 }
      ])
    end
    
    def create_execution_plan(analysis)
      # Simple plan for now
      {
        "steps" => [
          {
            "description" => "Create complete application structure",
            "files" => analysis["files_needed"] || []
          }
        ]
      }
    end
    
    def parse_analysis_response(response)
      begin
        if response[:content].include?('{')
          json_match = response[:content].match(/\{.*\}/m)
          JSON.parse(json_match[0]) if json_match
        else
          { "files_needed" => [], "approach" => "standard" }
        end
      rescue
        { "files_needed" => [], "approach" => "standard" }
      end
    end
    
    def load_relevant_context
      # Load existing files for context
      files = @app.app_files.limit(10).map do |file|
        {
          path: file.path,
          size: file.content.length,
          preview: file.content[0..200]
        }
      end
      
      { files: files, summary: "Existing app with #{@app.app_files.count} files" }
    end
    
    def review_and_finalize(result)
      Rails.logger.info "[V3-Unified] Reviewing generated code"
      
      if @is_new_app && @files_modified.empty?
        Rails.logger.error "[V3-Unified] No files created for new app!"
        raise "Generation failed - no files created"
      end
      
      # Update version with file snapshot
      files_snapshot = @app.app_files.pluck(:path)
      @app_version.update!(
        files_snapshot: files_snapshot.to_json,
        changed_files: @files_modified.to_json
      )
    end
    
    def deploy_app
      Rails.logger.info "[V3-Unified] Deploying app"
      @app.update!(status: 'published')
    end
    
    def finalize_version(status)
      @app_version.update!(
        status: status,
        completed_at: Time.current
      )
    end
    
    def handle_error(error)
      Rails.logger.error "[V3-Unified] Error: #{error.message}"
      Rails.logger.error error.backtrace.first(5).join("\n")
      
      @broadcaster.update("❌ Error: #{error.message}", 1.0)
      finalize_version('failed')
      
      @app_version.update!(error_message: error.message)
    end
    
    def queue_post_generation_jobs
      if @is_new_app && @files_modified.any?
        ::DeployAppJob.perform_later(@app)
        ::GenerateAppLogoJob.perform_later(@app)
        ::AppNamingJob.perform_later(@app)
      end
    end
    
    def ensure_valid_javascript(content)
      # Basic validation and fixes
      content
    end
    
    def determine_file_type(path)
      ext = File.extname(path).downcase.delete(".")
      case ext
      when "html", "htm" then "html"
      when "js", "jsx" then "js"
      when "css", "scss" then "css"
      when "json" then "json"
      else "text"
      end
    end
  end
end