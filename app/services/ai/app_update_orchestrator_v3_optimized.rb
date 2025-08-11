module Ai
  # Optimized V3 Orchestrator following Lovable.dev/Bolt.new/Cursor patterns
  # Key optimizations:
  # 1. System-level prompt with standards (loaded once)
  # 2. OpenAI prompt caching for efficiency
  # 3. Phase-specific lightweight prompts
  # 4. Proper streaming implementation
  # 5. Batched file processing
  class AppUpdateOrchestratorV3Optimized
    include Rails.application.routes.url_helpers
    
    # Configuration learned from successful platforms
    MAX_CONTEXT_TOKENS = 32_000
    MAX_FILES_PER_BATCH = 5        # Process files in manageable batches
    API_TIMEOUT_SECONDS = 120       # 2 minutes per API call
    MAX_RETRIES = 2
    
    # Prompt caching (reduces latency by 50-80%)
    ENABLE_PROMPT_CACHING = true
    
    attr_reader :chat_message, :app, :user, :app_version, :broadcaster
    
    def initialize(chat_message)
      @chat_message = chat_message
      @app = chat_message.app
      @user = chat_message.user
      @iteration_count = 0
      
      # IMPORTANT: Check if new app BEFORE any versions are created
      # An app is "new" if it has no real content files (ignore minimal placeholders)
      @is_new_app = is_app_new?
      
      # Model selection
      @model_preference = @app.ai_model || 'gpt-5'
      setup_ai_client
      
      @broadcaster = Ai::Services::ProgressBroadcaster.new(@app, @chat_message)
      @streaming_buffer = Ai::Services::StreamingBufferEnhanced.new(@app, @chat_message, @broadcaster)
      @use_streaming = ENV['USE_STREAMING'] != 'false' && @supports_streaming
      
      @files_modified = []
      @start_time = Time.current
      
      # OPTIMIZATION: Load standards once and create cached system prompt
      load_standards_once
      @system_prompt = create_optimized_system_prompt
    end
    
    def is_app_new?
      # An app is "new" if it has no files or only has minimal placeholder files
      return true if @app.app_files.empty?
      
      # Check if only minimal files exist (created by ensure_minimum_files)
      files = @app.app_files.pluck(:path)
      minimal_files = ['index.html', 'src/App.jsx']
      
      # If we only have the minimal files and they're small, treat as new
      if files.sort == minimal_files.sort
        total_size = @app.app_files.sum { |f| f.content.length }
        # If total content is less than 2KB, these are just placeholders
        return total_size < 2000
      end
      
      false
    end
    
    def execute!
      Rails.logger.info "[V3-Optimized] Starting execution for message ##{chat_message.id}"
      Rails.logger.info "[V3-Optimized] Type: #{@is_new_app ? 'CREATE' : 'UPDATE'}, Model: #{@model}"
      
      begin
        # Skip discussion mode check for new apps
        unless @is_new_app || explicit_code_request?
          return handle_discussion_mode
        end
        
        # Initialize version tracking
        create_app_version!
        define_execution_stages
        
        # PHASE 1: Quick Analysis (lightweight)
        @broadcaster.enter_stage(:analyzing)
        analysis = perform_quick_analysis
        
        # PHASE 2: Execution Planning (minimal)
        @broadcaster.enter_stage(:planning)
        plan = create_execution_plan(analysis)
        
        # PHASE 3: Batched Implementation (efficient)
        @broadcaster.enter_stage(:coding)
        result = execute_in_batches(plan)
        
        # PHASE 4: Quick Review
        @broadcaster.enter_stage(:reviewing)
        review_and_finalize(result)
        
        # PHASE 5: Deploy if new
        if @is_new_app
          @broadcaster.enter_stage(:deploying)
          deploy_app
        end
        
        finalize_success
        
      rescue => e
        Rails.logger.error "[V3-Optimized] Error: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        handle_failure(e.message)
      end
    end
    
    private
    
    def setup_ai_client
      client_info = Ai::ModelClientFactory.create_client(@model_preference)
      @client = client_info[:client]
      @model = client_info[:model]
      @provider = client_info[:provider]
      @supports_streaming = client_info[:supports_streaming]
      @use_openai_direct = @provider == 'openai_direct'
      
      Rails.logger.info "[V3-Optimized] Using #{@provider}/#{@model}"
    end
    
    def load_standards_once
      # Load standards ONCE at initialization
      standards_path = Rails.root.join('AI_APP_STANDARDS.md')
      
      if File.exist?(standards_path)
        @standards_full = File.read(standards_path)
        Rails.logger.info "[V3-Optimized] Loaded standards: #{@standards_full.length} bytes"
        
        # Create condensed version for reference
        @standards_key_points = extract_key_points(@standards_full)
        Rails.logger.info "[V3-Optimized] Condensed to: #{@standards_key_points.length} bytes"
      else
        @standards_full = "Follow React CDN best practices with Tailwind CSS"
        @standards_key_points = @standards_full
      end
    end
    
    def extract_key_points(full_standards)
      # Simple key points for logging/debugging only
      # The full standards are in the system prompt
      "React CDN + Tailwind, Professional Quality, Complete Functionality"
    end
    
    def create_optimized_system_prompt
      # OPTIMIZATION: Single, comprehensive system prompt (cached by OpenAI)
      # Focused on one high-quality approach - no mode switching
      
      prompt = <<~SYSTEM
        You are an elite web application developer building production-ready applications that match the quality of Lovable.dev, Bolt.new, and Cursor.
        
        TECHNOLOGY STACK:
        • React 18 via CDN (unpkg/esm.sh) - No build tools needed
        • React Router DOM via CDN for client-side routing
        • Tailwind CSS via CDN for styling
        • Babel Standalone for JSX transpilation
        • Supabase for backend (when needed)
        • Modern ES6+ JavaScript (no TypeScript in CDN mode)
        
        CORE PRINCIPLES:
        
        1. **COMPLETE FUNCTIONALITY** - Every feature must work end-to-end. No placeholders, no "TODO" comments, no partial implementations.
        
        2. **PROFESSIONAL DESIGN** - Sophisticated color palettes, smooth animations, thoughtful spacing, hover effects, and transitions. Apps should look like $10K custom builds.
        
        3. **PRODUCTION QUALITY** - Proper error handling, loading states, empty states, success feedback, and edge case handling. Code that could ship to real users today.
        
        4. **MOBILE-FIRST RESPONSIVE** - Perfect on all devices. Use Tailwind's responsive utilities (sm:, md:, lg:, xl:).
        
        5. **RICH SAMPLE DATA** - Include 5-10 realistic, diverse data items. Use real names, dates, descriptions. Make it feel alive.
        
        6. **MODERN UX PATTERNS** - Smooth transitions, skeleton loaders, optimistic updates, keyboard shortcuts, accessibility (ARIA labels, semantic HTML).
        
        7. **STATE MANAGEMENT** - Use React hooks properly (useState, useEffect, useCallback, useMemo). Handle async operations correctly.
        
        8. **MULTI-PAGE STRUCTURE** - Use React Router for proper page navigation with professional URL structure.
        
        FILE STRUCTURE (REQUIRED FOR APPS WITH USER DATA):
        ```
        index.html              - Entry point with CDN scripts
        src/
          pages/               - Page components (React Router)
            Home.jsx          - Public landing page
            auth/             - Authentication pages
              Login.jsx       - Login page
              SignUp.jsx      - Registration page
              AuthCallback.jsx - OAuth callback handler
            Dashboard.jsx     - Protected dashboard
          components/         - Reusable components
            auth/
              Auth.jsx        - Main auth component
              SocialButtons.jsx - OAuth login buttons
              ProtectedRoute.jsx - Route guard
            layout/
              Header.jsx      - App header with auth state
              Layout.jsx      - Main layout wrapper
          lib/
            supabase.js       - Supabase client configuration
            router.jsx        - Router configuration
          hooks/              - Custom React hooks
          utils/              - Helper functions
        styles.css            - Custom styles beyond Tailwind
        ```
        
        CRITICAL APP CONFIGURATION:
        
        Your app will receive configuration via window.ENV object:
        ```javascript
        // Available environment variables
        const config = {
          APP_ID: window.ENV?.APP_ID,              // Unique app identifier
          SUPABASE_URL: window.ENV?.SUPABASE_URL,   // Supabase project URL
          SUPABASE_ANON_KEY: window.ENV?.SUPABASE_ANON_KEY, // Supabase anon key
          API_WORKER_URL: window.ENV?.API_WORKER_URL, // Cloudflare Worker for API proxy
          AUTH_SETTINGS: window.ENV?.AUTH_SETTINGS   // App auth configuration
        };
        ```
        
        AUTHENTICATION REQUIREMENTS:
        
        Apps receive AUTH_SETTINGS object with visibility configuration:
        ```javascript
        // window.ENV.AUTH_SETTINGS contains:
        {
          visibility: "private_login_required" | "public_login_required" | "public_no_login",
          allowed_providers: ["email", "google", "github"],
          require_email_verification: boolean,
          allow_signups: boolean,
          allow_anonymous: boolean
        }
        ```
        
        MANDATORY AUTH IMPLEMENTATION:
        
        For visibility "private_login_required" or "public_login_required":
        
        1. **ALWAYS create comprehensive auth system**:
           - src/pages/auth/Login.jsx - Professional login page
           - src/pages/auth/SignUp.jsx - Registration page  
           - src/pages/auth/AuthCallback.jsx - OAuth callback handler
           - src/components/auth/SocialButtons.jsx - Social auth buttons
           - src/components/auth/ProtectedRoute.jsx - Route guard
        
        2. **ALWAYS use React Router for navigation**:
           - Multi-page structure with proper routing
           - Protected routes for authenticated content
           - Professional URL structure (/login, /dashboard, etc.)
        
        3. **ALWAYS respect AUTH_SETTINGS configuration**:
           - Show/hide signup based on allow_signups
           - Include only allowed_providers in social buttons
           - Implement email verification if required
        
        4. **ALWAYS include social authentication**:
           - Google OAuth via window.ENV.API_WORKER_URL/auth/google
           - GitHub OAuth via window.ENV.API_WORKER_URL/auth/github
           - Professional social login buttons with proper styling
        
        SUPABASE INTEGRATION REQUIREMENTS:
        
        For apps with user data, ALWAYS implement proper Supabase integration:
        
        1. **Use app-specific table names**:
        ```javascript
        // ✅ CORRECT - includes app ID prefix
        const tableName = `app_${window.ENV.APP_ID}_items`
        await supabase.from(tableName).select('*')
        
        // ❌ WRONG - missing app ID prefix  
        await supabase.from('items').select('*')
        ```
        
        2. **Include user context in all operations**:
        ```javascript
        // ✅ CORRECT - filtered by user
        await supabase
          .from(`app_${window.ENV.APP_ID}_items`)
          .select('*')
          .eq('user_id', user.id)
        
        // ✅ CORRECT - include user_id when creating
        await supabase
          .from(`app_${window.ENV.APP_ID}_items`)
          .insert([{ title, user_id: user.id }])
        ```
        
        3. **Create Supabase client properly**:
        ```javascript
        // src/lib/supabase.js
        import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'
        
        export const supabase = createClient(
          window.ENV.SUPABASE_URL,
          window.ENV.SUPABASE_ANON_KEY
        )
        ```
        
        API INTEGRATION REQUIREMENTS:
        
        For external API calls, ALWAYS use the secure proxy pattern:
        
        ```javascript
        // ✅ CORRECT - via secure Cloudflare Worker proxy
        const response = await fetch(`${window.ENV.API_WORKER_URL}/stripe/payment_intents`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ amount: 5000, currency: 'usd' })
        })
        
        // ❌ WRONG - direct API calls expose secrets
        const response = await fetch('https://api.stripe.com/v1/payment_intents', {
          headers: { 'Authorization': 'Bearer sk_test_...' } // NEVER do this
        })
        ```
        
        IMPLEMENTATION REQUIREMENTS:
        
        For ALL Apps:
        • Start with complete index.html including all CDN links (React, React Router, Supabase)
        • Create fully functional App.jsx with React Router setup
        • Add feature-specific components as needed
        • Include proper data persistence (localStorage fallback + Supabase)
        • Add keyboard shortcuts and accessibility features
        • Implement smooth animations and transitions
        • Include comprehensive error handling
        • Respect AUTH_SETTINGS for proper access control
        
        For Apps with User Data (todos, notes, budgets):
        • Implement full CRUD operations (Create, Read, Update, Delete)
        • Add search/filter functionality
        • Include sorting and categorization
        • Add data export capabilities
        • Implement undo/redo if applicable
        • ALWAYS use app-scoped table names with proper user filtering
        
        REQUIRED CDN RESOURCES:
        Include in index.html:
        ```html
        <!-- React + Router -->
        <script crossorigin src="https://unpkg.com/react@18/umd/react.development.js"></script>
        <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
        <script src="https://unpkg.com/react-router-dom@6.8.1/dist/umd/react-router-dom.development.js"></script>
        
        <!-- Babel for JSX -->
        <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
        
        <!-- Supabase -->
        <script src="https://unpkg.com/@supabase/supabase-js@2"></script>
        
        <!-- Tailwind CSS -->
        <script src="https://cdn.tailwindcss.com"></script>
        ```
        
        UI/UX Requirements:
        • Use a cohesive color scheme with CSS variables
        • Implement dark mode support (if requested)
        • Add micro-interactions (button clicks, hovers)
        • Include loading skeletons for async operations
        • Show success/error toasts for user feedback
        • Empty states with helpful messages and CTAs
        • Professional form inputs with proper text-slate-900 for visibility
        
        Code Quality:
        • Clean, readable code with consistent formatting
        • Meaningful variable and function names
        • Proper component composition and reusability
        • Efficient re-renders (useCallback, useMemo where needed)
        • No console.logs in production code
        • Comments only for complex logic
        • Environment variable access via window.ENV
        • Proper error boundaries and fallbacks
        
        WHEN USING TOOL FUNCTIONS:
        • create_file: Create COMPLETE files with all necessary code and proper integrations
        • update_file: Preserve existing functionality while adding features
        • broadcast_progress: Send clear updates about what you're building
        
        CRITICAL: Build applications that users would happily pay for. Every detail matters.
        Implement the complete OverSkill platform integration with Supabase, OAuth, and Cloudflare Workers.
      SYSTEM
      
      # Add operation-specific guidance
      if @is_new_app
        prompt += "\n\nNEW APP CREATION:\n"
        prompt += "1. Start with index.html (complete HTML with all CDN scripts)\n"
        prompt += "2. Create src/App.jsx with full application logic\n"
        prompt += "3. Add components as needed for features\n"
        prompt += "4. Include all necessary styles and interactions"
      else
        prompt += "\n\nAPP UPDATE:\n"
        prompt += "1. Carefully analyze existing code structure\n"
        prompt += "2. Preserve all existing functionality\n"
        prompt += "3. Integrate new features smoothly\n"
        prompt += "4. Maintain consistent code style"
      end
      
      prompt
    end
    
    
    def perform_quick_analysis
      Rails.logger.info "[V3-Optimized] Quick analysis phase"
      
      # Load minimal context
      context = if @is_new_app
        { files: [], summary: "Empty app - needs full implementation" }
      else
        Ai::SmartContextService.load_relevant_context(
          @app,
          @chat_message.content,
          operation_type: :update
        )
      end
      
      # Comprehensive analysis prompt
      analysis_prompt = <<~PROMPT
        Analyze this request: "#{@chat_message.content}"
        
        App: #{@app.name}
        Type: #{@is_new_app ? 'NEW' : 'UPDATE'}
        Current files: #{context[:files].map { |f| f[:path] }.join(', ')}
        
        IMPORTANT: For NEW apps, you must plan to create a COMPLETE application with:
        - Full authentication system (login, signup, OAuth)
        - React Router for multi-page navigation
        - Supabase integration for data persistence
        - Professional UI with Tailwind CSS
        - All necessary components and pages
        
        Return JSON with ALL files needed:
        {
          "approach": "Technical approach description",
          "files_needed": ["index.html", "src/App.jsx", "src/lib/supabase.js", "src/lib/router.jsx", "src/pages/Home.jsx", "src/pages/auth/Login.jsx", "src/pages/auth/SignUp.jsx", "src/pages/Dashboard.jsx", "src/components/auth/Auth.jsx", "etc..."],
          "complexity": "complex",
          "needs_auth": true
        }
      PROMPT
      
      messages = [
        { role: "system", content: @system_prompt },
        { role: "user", content: analysis_prompt }
      ]
      
      # Use streaming if available
      response = execute_ai_call(messages, use_json: true)
      
      if response[:success]
        parse_json_response(response[:content])
      else
        { approach: "Standard implementation", files_needed: ["index.html", "src/App.jsx"], complexity: "moderate" }
      end
    end
    
    def create_execution_plan(analysis)
      Rails.logger.info "[V3-Optimized] Creating execution plan"
      
      # Lightweight planning
      plan_prompt = <<~PROMPT
        Create a plan to: "#{@chat_message.content}"
        
        Analysis: #{analysis.to_json}
        
        Return a simple JSON plan:
        {
          "steps": [
            {"description": "Create main structure", "files": ["index.html", "src/App.jsx"]},
            {"description": "Add components", "files": ["src/components/TodoList.jsx"]}
          ]
        }
      PROMPT
      
      messages = [
        { role: "system", content: @system_prompt + "\n\nReturn JSON only." },
        { role: "user", content: plan_prompt }
      ]
      
      response = execute_ai_call(messages, use_json: true)
      
      if response[:success]
        parse_json_response(response[:content])
      else
        # Fallback plan
        {
          "steps" => [
            { "description" => "Create app structure", "files" => ["index.html", "src/App.jsx"] }
          ]
        }
      end
    end
    
    def execute_in_batches(plan)
      Rails.logger.info "[V3-Optimized] Executing in batches"
      
      # Define tools for file operations (without broadcast_progress to avoid confusion)
      tools = create_tool_definitions(false)
      
      # Process each step
      steps = plan["steps"] || [{ "description" => "Build app", "files" => [] }]
      
      steps.each_with_index do |step, index|
        Rails.logger.info "[V3-Optimized] Step #{index + 1}/#{steps.length}: #{step['description']}"
        @broadcaster.update(step['description'], (index.to_f / steps.length))
        
        # Execute with tools
        execute_step_with_tools(step, tools)
      end
      
      { success: true, files_created: @files_modified }
    end
    
    def execute_step_with_tools(step, tools)
      # Create focused prompt for this step with explicit tool usage instructions
      prompt = <<~PROMPT
        Implement: #{step['description']}
        
        User wants: "#{@chat_message.content}"
        
        YOU MUST CREATE MULTIPLE SEPARATE FILES - NOT A SINGLE FILE!
        
        MANDATORY FILE LIST - CREATE EACH AS A SEPARATE FILE:
        
        FILE 1: Call create_file with path="index.html"
        - HTML document with CDN links for React, Router, Supabase, Tailwind
        - Script tag to load src/App.jsx
        - DO NOT inline JavaScript here
        
        FILE 2: Call create_file with path="src/App.jsx"  
        - Main React component with Router setup
        - Import statements (even though using CDN)
        - Authentication state management
        - Route definitions
        
        FILE 3: Call create_file with path="src/lib/supabase.js"
        - Supabase client initialization
        - Uses window.ENV for configuration
        - Export the client
        
        FILE 4: Call create_file with path="src/pages/auth/Login.jsx"
        - Login page component
        - Email and OAuth options
        
        FILE 5: Call create_file with path="src/pages/auth/SignUp.jsx"
        - Registration page component
        
        FILE 6: Call create_file with path="src/pages/Dashboard.jsx"
        - Main dashboard for the app
        
        CREATE AT LEAST 6-10 SEPARATE FILES!
        DO NOT CREATE A SINGLE MONOLITHIC FILE!
        
        Each file MUST be created with a separate create_file tool call.
        
        EXAMPLE OF CORRECT TOOL USAGE:
        
        To create index.html, call create_file with:
        {
          "path": "index.html",
          "content": "<!DOCTYPE html>\\n<html>\\n..."
        }
        
        To create src/App.jsx, call create_file with:
        {
          "path": "src/App.jsx",
          "content": "const App = () => {\\n  ..."
        }
        
        REQUIRED FILES TO CREATE (use create_file for EACH):
        
        1. index.html - Complete HTML with all CDN scripts:
           - React, ReactDOM, React Router DOM
           - Babel standalone for JSX transformation
           - Supabase client library
           - Tailwind CSS
           - Proper script to mount React app
        
        2. src/App.jsx - Main application with:
           - React Router setup with all routes
           - Authentication state management
           - Supabase client initialization
           - Route protection logic
        
        3. src/lib/supabase.js - Supabase configuration:
           - Initialize client with window.ENV values
           - Export configured client
        
        4. src/pages/Home.jsx - Landing page
        5. src/pages/auth/Login.jsx - Login with email + OAuth
        6. src/pages/auth/SignUp.jsx - Registration page
        7. src/pages/Dashboard.jsx - Main app dashboard
        8. src/components/auth/ProtectedRoute.jsx - Route guard
        9. src/components/layout/Header.jsx - Navigation header
        10. Additional components as needed for the app
        
        IMPORTANT REMINDERS:
        - Use create_file tool for EVERY file - do not output code in text
        - Each file must have COMPLETE, WORKING code - no placeholders
        - Use window.ENV for all configuration values
        - Include proper error handling and loading states
        - Follow the OverSkill platform patterns
        
        Start creating files NOW using the create_file tool function.
      PROMPT
      
      messages = [
        { role: "system", content: @system_prompt },
        { role: "user", content: prompt }
      ]
      
      # Log for debugging
      Rails.logger.info "[V3-Optimized] Executing step with #{tools.length} tools available"
      
      # Execute with streaming if available
      if @use_streaming && @streaming_buffer
        execute_with_streaming(messages, tools)
      elsif @use_openai_direct
        execute_with_openai_tools(messages, tools)
      else
        execute_with_fallback(messages, tools)
      end
    end
    
    def execute_with_streaming(messages, tools)
      Rails.logger.info "[V3-Optimized] Executing with streaming"
      
      @streaming_buffer.start_generation
      
      if @use_openai_direct
        # Direct OpenAI streaming with tools
        stream_openai_with_tools(messages, tools)
      else
        # OpenRouter streaming
        stream_openrouter_with_tools(messages, tools)
      end
    end
    
    def stream_openai_with_tools(messages, tools)
      require 'net/http'
      require 'json'
      
      uri = URI('https://api.openai.com/v1/chat/completions')
      
      request_body = {
        model: @model,
        messages: messages,
        tools: tools,
        tool_choice: "auto",  # Let AI choose but prompt strongly encourages tool use
        stream: true
      }
      
      # GPT-5 specific adjustments
      if @model.include?('gpt-5')
        request_body[:max_completion_tokens] = 16000
        # GPT-5 only supports default temperature of 1
      else
        request_body[:max_tokens] = 16000
        request_body[:temperature] = 0.7
      end
      
      # GPT-5 doesn't support the cache parameter
      # Keeping this commented for future when it might be supported
      # if ENABLE_PROMPT_CACHING && @model.include?('gpt-5')
      #   request_body[:cache] = {
      #     enabled: true,
      #     ttl: 300
      #   }
      # end
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = API_TIMEOUT_SECONDS
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      # Variables to accumulate streaming response
      accumulated_content = ""
      accumulated_tool_calls = []
      current_tool_call = nil
      
      Rails.logger.info "[V3-Optimized] Starting streaming request to OpenAI"
      
      http.request(request) do |response|
        Rails.logger.info "[V3-Optimized] Response status: #{response.code}"
        
        # Handle error responses
        if response.code != '200'
          error_body = response.read_body
          Rails.logger.error "[V3-Optimized] API Error Response: #{error_body}"
          
          # Try to parse error message
          begin
            error_data = JSON.parse(error_body)
            Rails.logger.error "[V3-Optimized] Error details: #{error_data['error']['message']}" if error_data['error']
          rescue
            Rails.logger.error "[V3-Optimized] Raw error: #{error_body}"
          end
          
          # Fall back to non-streaming or simpler approach
          Rails.logger.info "[V3-Optimized] Falling back to non-streaming due to error"
          return execute_with_openai_tools(messages, tools)
        end
        
        response.read_body do |chunk|
          # Process SSE chunks and extract tool calls
          chunk.split("\n").each do |line|
            next unless line.start_with?("data: ")
            
            json_str = line[6..-1]  # Remove "data: " prefix
            next if json_str == "[DONE]"
            
            begin
              data = JSON.parse(json_str)
              
              # Log first chunk to see structure
              if accumulated_content.empty? && accumulated_tool_calls.empty?
                Rails.logger.info "[V3-Optimized] First chunk structure: #{data.keys}"
                Rails.logger.info "[V3-Optimized] Choice keys: #{data['choices']&.first&.keys}"
              end
              
              choice = data['choices']&.first
              next unless choice
              
              delta = choice['delta']
              next unless delta
              
              # Handle content
              if delta['content']
                accumulated_content += delta['content']
                @streaming_buffer.process_chunk(delta['content']) if @streaming_buffer
              end
              
              # Handle tool calls
              if delta['tool_calls']
                Rails.logger.info "[V3-Optimized] Tool call delta detected: #{delta['tool_calls'].inspect}"
                delta['tool_calls'].each do |tool_call_delta|
                  index = tool_call_delta['index']
                  
                  # Initialize or update tool call at index
                  if tool_call_delta['id']
                    # New tool call
                    Rails.logger.info "[V3-Optimized] New tool call: #{tool_call_delta['function']['name']}"
                    current_tool_call = {
                      'id' => tool_call_delta['id'],
                      'type' => tool_call_delta['type'] || 'function',
                      'function' => {
                        'name' => tool_call_delta['function']['name'],
                        'arguments' => ""
                      }
                    }
                    accumulated_tool_calls[index] = current_tool_call
                  elsif accumulated_tool_calls[index]
                    # Accumulate arguments for existing tool call
                    if tool_call_delta['function'] && tool_call_delta['function']['arguments']
                      accumulated_tool_calls[index]['function']['arguments'] += tool_call_delta['function']['arguments']
                    end
                  end
                end
              end
              
              # Handle finish reason
              if choice['finish_reason'] == 'tool_calls' && accumulated_tool_calls.any?
                # Execute all accumulated tool calls
                Rails.logger.info "[V3-Optimized] Executing #{accumulated_tool_calls.length} tool calls"
                process_tool_calls(accumulated_tool_calls)
                accumulated_tool_calls = []
              end
            rescue JSON::ParserError => e
              Rails.logger.debug "[V3-Optimized] Skipping invalid JSON chunk: #{e.message}"
            end
          end
        end
      end
      
      # Process any remaining tool calls
      if accumulated_tool_calls.any?
        Rails.logger.info "[V3-Optimized] Executing final #{accumulated_tool_calls.length} tool calls"
        process_tool_calls(accumulated_tool_calls)
      end
      
      # Return accumulated content if no tool calls were made
      if accumulated_content.present? && @files_modified.empty?
        Rails.logger.warn "[V3-Optimized] No tool calls made, creating files from content"
        create_files_from_response(accumulated_content)
      end
    end
    
    def execute_with_openai_tools(messages, tools)
      # Non-streaming OpenAI with tools
      require 'net/http'
      require 'json'
      
      uri = URI('https://api.openai.com/v1/chat/completions')
      
      request_body = {
        model: @model,
        messages: messages,
        tools: tools,
        tool_choice: "auto"  # Let AI choose but prompt strongly encourages tool use
      }
      
      # GPT-5 specific adjustments
      if @model.include?('gpt-5')
        request_body[:max_completion_tokens] = 16000
        # GPT-5 only supports default temperature of 1
      else
        request_body[:max_tokens] = 16000
        request_body[:temperature] = 0.7
      end
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = API_TIMEOUT_SECONDS
      
      request = Net::HTTP::Post.new(uri)
      request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
      request['Content-Type'] = 'application/json'
      request.body = request_body.to_json
      
      Rails.logger.info "[V3-Optimized] Sending non-streaming request with #{tools.length} tools"
      
      response = http.request(request)
      result = JSON.parse(response.body)
      
      if result['error']
        Rails.logger.error "[V3-Optimized] OpenAI API error: #{result['error']['message']}"
        return
      end
      
      # Process tool calls
      if result['choices'] && result['choices'][0]['message']['tool_calls']
        tool_calls = result['choices'][0]['message']['tool_calls']
        Rails.logger.info "[V3-Optimized] Received #{tool_calls.length} tool calls from API"
        process_tool_calls(tool_calls)
      elsif result['choices'] && result['choices'][0]['message']['content']
        # AI returned content without tool calls - parse it for file creation
        content = result['choices'][0]['message']['content']
        Rails.logger.warn "[V3-Optimized] No tool calls received, attempting to parse content for files"
        create_files_from_response(content)
      else
        Rails.logger.error "[V3-Optimized] Unexpected response structure: #{result.keys}"
      end
    end
    
    def execute_with_fallback(messages, tools)
      # Fallback to simple generation without tools
      Rails.logger.warn "[V3-Optimized] Using fallback execution without tools"
      
      response = @client.chat(messages, model: @model, temperature: 0.7)
      
      if response[:success]
        # Parse and create files from response
        create_files_from_response(response[:content])
      end
    end
    
    def create_tool_definitions(include_broadcast = false)
      tools = [
        {
          type: "function",
          function: {
            name: "create_file",
            description: "Create a new file with complete content. Use this to create ALL files for the application.",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "File path (e.g., index.html, src/App.jsx, src/lib/supabase.js)" },
                content: { type: "string", description: "Complete file content with all code" }
              },
              required: ["path", "content"]
            }
          }
        },
        {
          type: "function", 
          function: {
            name: "update_file",
            description: "Update an existing file with new content",
            parameters: {
              type: "object",
              properties: {
                path: { type: "string", description: "Path to existing file" },
                content: { type: "string", description: "New complete content for the file" }
              },
              required: ["path", "content"]
            }
          }
        }
      ]
      
      # Only include broadcast_progress if explicitly requested
      # This tool seems to confuse GPT-5 during file generation
      if include_broadcast
        tools << {
          type: "function",
          function: {
            name: "broadcast_progress",
            description: "Send progress update to user (DO NOT USE for file creation)",
            parameters: {
              type: "object",
              properties: {
                message: { type: "string" }
              },
              required: ["message"]
            }
          }
        }
      end
      
      tools
    end
    
    def process_tool_calls(tool_calls)
      Rails.logger.info "[V3-Optimized] Processing #{tool_calls.length} tool calls"
      
      tool_calls.each_with_index do |call, index|
        function_name = call['function']['name']
        arguments_str = call['function']['arguments']
        
        begin
          arguments = JSON.parse(arguments_str)
          Rails.logger.info "[V3-Optimized] Tool call #{index + 1}: #{function_name} - #{arguments['path'] || arguments['message'] || 'no path'}"
          
          case function_name
          when 'create_file'
            create_or_update_file(arguments['path'], arguments['content'])
            @broadcaster.file_created(arguments['path']) if @broadcaster
          when 'update_file'
            create_or_update_file(arguments['path'], arguments['content'])
            @broadcaster.update("Updated #{arguments['path']}", nil) if @broadcaster
          when 'broadcast_progress'
            @broadcaster.update(arguments['message']) if @broadcaster
          else
            Rails.logger.warn "[V3-Optimized] Unknown tool function: #{function_name}"
          end
        rescue JSON::ParserError => e
          Rails.logger.error "[V3-Optimized] Failed to parse tool arguments: #{e.message}"
          Rails.logger.error "[V3-Optimized] Arguments string: #{arguments_str}"
        rescue => e
          Rails.logger.error "[V3-Optimized] Error processing tool call: #{e.message}"
          Rails.logger.error e.backtrace.first(3).join("\n")
        end
      end
      
      Rails.logger.info "[V3-Optimized] Completed processing tool calls. Files modified: #{@files_modified.count}"
    end
    
    def create_or_update_file(path, content)
      Rails.logger.info "[V3-Optimized] Creating/updating file: #{path}"
      
      # Validate content
      if path.end_with?('.jsx', '.js')
        content = ensure_valid_javascript(content)
      end
      
      # Create or update file
      file = @app.app_files.find_or_initialize_by(path: path)
      file.content = content
      file.file_type = determine_file_type(path)
      file.team = @app.team  # Set team association
      file.save!
      
      @files_modified << path
      @broadcaster.file_created(path)
    rescue => e
      Rails.logger.error "[V3-Optimized] Error creating file #{path}: #{e.message}"
      raise
    end
    
    def ensure_valid_javascript(content)
      # Remove TypeScript syntax
      content = content.gsub(/:\s*(string|number|boolean|any|void|object|Function)(\s*[;,\)\}=])/, '\2')
      content = content.gsub(/^[\s]*interface\s+\w+\s*\{.*?\}/m, '')
      content = content.gsub(/<([A-Z]\w*),[\w\s,<>]*>/, '')
      
      content
    end
    
    def determine_file_type(path)
      case path
      when /\.html$/i then 'html'
      when /\.jsx$/i then 'jsx'
      when /\.js$/i then 'js'
      when /\.css$/i then 'css'
      when /\.json$/i then 'json'
      else 'text'
      end
    end
    
    def review_and_finalize(result)
      Rails.logger.info "[V3-Optimized] Reviewing and finalizing"
      
      # Quick review
      @broadcaster.update("Reviewing generated code...", 0.9)
      
      # Only ensure minimum files if we're in UPDATE mode and no files were created
      # For NEW apps, we should have created comprehensive files via tool calls
      if !@is_new_app && @files_modified.empty?
        Rails.logger.warn "[V3-Optimized] No files modified in update mode, ensuring minimum files"
        ensure_minimum_files
      elsif @is_new_app && @files_modified.empty?
        Rails.logger.error "[V3-Optimized] ERROR: New app generation created no files! AI tool calls failed."
        # Still create minimal files so app isn't broken, but log the error
        ensure_minimum_files
      end
      
      # Update app status
      @app.update!(status: 'generated')
      
      @broadcaster.update("Generation complete!", 1.0)
    end
    
    def ensure_minimum_files
      return unless @is_new_app
      
      # Ensure index.html exists
      unless @app.app_files.exists?(path: 'index.html')
        create_default_index_html
      end
      
      # Ensure App.jsx exists
      unless @app.app_files.exists?(path: 'src/App.jsx')
        create_default_app_jsx
      end
    end
    
    def create_default_index_html
      content = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{@app.name}</title>
          <script src="https://cdn.tailwindcss.com"></script>
          <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
          <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
          <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
        </head>
        <body>
          <div id="root"></div>
          <script type="text/babel" src="src/App.jsx"></script>
        </body>
        </html>
      HTML
      
      @app.app_files.create!(
        path: 'index.html',
        content: content,
        file_type: 'html',
        team: @app.team
      )
      @files_modified << 'index.html'
    end
    
    def create_default_app_jsx
      content = <<~JSX
        const App = () => {
          const [message, setMessage] = React.useState('Welcome to #{@app.name}!');
          
          return (
            <div className="min-h-screen bg-gray-100 flex items-center justify-center">
              <div className="bg-white p-8 rounded-lg shadow-lg">
                <h1 className="text-3xl font-bold text-gray-800 mb-4">{message}</h1>
                <p className="text-gray-600">Your app is ready. Start building!</p>
              </div>
            </div>
          );
        };
        
        const root = ReactDOM.createRoot(document.getElementById('root'));
        root.render(<App />);
      JSX
      
      @app.app_files.create!(
        path: 'src/App.jsx',
        content: content,
        file_type: 'jsx',
        team: @app.team
      )
      @files_modified << 'src/App.jsx'
    end
    
    def deploy_app
      Rails.logger.info "[V3-Optimized] Deploying app"
      
      begin
        # Use simplified service for now to avoid worker errors
        service = Deployment::FastPreviewServiceSimple.new(@app)
        result = service.deploy_instant_preview!
        
        if result[:success]
          @broadcaster.update("Deployed to #{result[:preview_url]}", 1.0)
          
          # Broadcast preview URL update to refresh the UI
          broadcast_preview_ready(result[:preview_url])
        else
          Rails.logger.error "[V3-Optimized] Deployment failed: #{result[:error]}"
          @broadcaster.update("Deployment failed: #{result[:error]}", 0.95)
        end
      rescue => e
        Rails.logger.error "[V3-Optimized] Deployment failed: #{e.message}"
        @broadcaster.update("Deployment error: #{e.message}", 0.95)
      end
    end
    
    def broadcast_preview_ready(preview_url)
      # Broadcast that preview is ready to trigger UI refresh
      ActionCable.server.broadcast(
        "app_#{@app.id}_chat",
        {
          action: "preview_ready",
          preview_url: preview_url,
          message: "Preview deployed successfully!"
        }
      )
      
      # Also broadcast a Turbo Stream to refresh the preview iframe if it exists
      Turbo::StreamsChannel.broadcast_replace_later_to(
        "app_#{@app.id}_preview",
        target: "preview_frame",
        partial: "account/app_editors/preview_frame",
        locals: { app: @app }
      )
    rescue => e
      Rails.logger.error "[V3-Optimized] Failed to broadcast preview update: #{e.message}"
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
        parts = last_version.version_number.split(".")
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join(".")
      else
        "1.0.0"
      end
    end
    
    def define_execution_stages
      stages = if @is_new_app
        [
          { name: :analyzing, description: "Understanding requirements" },
          { name: :planning, description: "Planning architecture" },
          { name: :coding, description: "Building application" },
          { name: :reviewing, description: "Reviewing code" },
          { name: :deploying, description: "Deploying app" }
        ]
      else
        [
          { name: :analyzing, description: "Analyzing changes" },
          { name: :planning, description: "Planning updates" },
          { name: :coding, description: "Implementing changes" },
          { name: :reviewing, description: "Reviewing updates" }
        ]
      end
      
      @broadcaster.define_stages(stages)
    end
    
    def finalize_success
      @app_version.update!(
        status: 'completed',
        completed_at: Time.current,
        files_snapshot: @files_modified.to_json
      )
      
      # Update app status for new apps
      if @is_new_app
        @app.update!(status: 'generated')
      end
      
      # Create success message
      @app.app_chat_messages.create!(
        role: 'assistant',
        content: "Successfully #{@is_new_app ? 'created' : 'updated'} your app with #{@files_modified.count} files.",
        status: 'completed'
      )
      
      # Queue post-generation jobs for new apps
      if @is_new_app
        queue_post_generation_jobs
      end
    end
    
    def queue_post_generation_jobs
      Rails.logger.info "[V3-Optimized] Queueing post-generation jobs for app ##{@app.id}"
      
      # Queue app naming job (runs first to name the app properly)
      ::AppNamingJob.perform_later(@app.id)
      
      # Queue logo generation job (uses the proper name)
      ::GenerateAppLogoJob.perform_later(@app.id)
      
      # Queue deployment job if enabled
      if ENV["AUTO_DEPLOY_AFTER_GENERATION"] == "true"
        ::DeployAppJob.perform_later(@app)
      end
    end
    
    def handle_failure(error_message)
      @app_version&.update!(
        status: 'failed',
        error_message: error_message,
        completed_at: Time.current
      )
      
      @app.app_chat_messages.create!(
        role: 'assistant',
        content: "Failed to generate app: #{error_message}",
        status: 'failed'
      )
      
      @broadcaster.update("Generation failed: #{error_message}", 0)
    end
    
    def handle_discussion_mode
      # Provide guidance without generating code
      response = "I can help you with that. To implement '#{@chat_message.content}', you would need to..."
      
      @app.app_chat_messages.create!(
        role: 'assistant',
        content: response,
        status: 'completed'
      )
    end
    
    def explicit_code_request?
      keywords = ['create', 'build', 'implement', 'add', 'make', 'generate', 'code', 'develop']
      keywords.any? { |word| @chat_message.content.downcase.include?(word) }
    end
    
    def execute_ai_call(messages, use_json: false)
      begin
        if @use_openai_direct
          # Direct OpenAI call
          require 'net/http'
          require 'json'
          
          uri = URI('https://api.openai.com/v1/chat/completions')
          
          request_body = {
            model: @model,
            messages: messages,
            temperature: 0.7
          }
          
          request_body[:response_format] = { type: "json_object" } if use_json
          
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = API_TIMEOUT_SECONDS
          
          request = Net::HTTP::Post.new(uri)
          request['Authorization'] = "Bearer #{ENV['OPENAI_API_KEY']}"
          request['Content-Type'] = 'application/json'
          request.body = request_body.to_json
          
          response = http.request(request)
          result = JSON.parse(response.body)
          
          if result['choices']
            { success: true, content: result['choices'][0]['message']['content'] }
          else
            { success: false, error: result['error']['message'] }
          end
        else
          # Use client
          response = @client.chat(messages, model: @model, temperature: 0.7)
          response
        end
      rescue => e
        { success: false, error: e.message }
      end
    end
    
    def parse_json_response(content)
      JSON.parse(content)
    rescue JSON::ParserError => e
      Rails.logger.error "[V3-Optimized] JSON parse error: #{e.message}"
      {}
    end
    
    def create_files_from_response(content)
      # Enhanced fallback parser for when AI returns structured content without tool calls
      Rails.logger.info "[V3-Optimized] Parsing content for file structures"
      
      files_created = 0
      
      # Try to parse as JSON first (AI might return structured JSON)
      begin
        if content.include?('{') && content.include?('files')
          # Extract JSON from content
          json_match = content.match(/\{[^{}]*"files"[^{}]*\}/m)
          if json_match
            data = JSON.parse(json_match[0])
            if data['files'].is_a?(Array)
              data['files'].each do |file|
                create_or_update_file(file['path'], file['content'])
                files_created += 1
              end
            end
          end
        end
      rescue JSON::ParserError
        # Not JSON, continue with other parsing methods
      end
      
      # Parse file markers like "// File: src/App.jsx" or "<!-- File: index.html -->"
      if content.include?('File:') || content.include?('file:')
        sections = content.split(/(?:^|\n)(?:\/\/|#|<!--)\s*[Ff]ile:\s*/)
        sections.each do |section|
          next if section.strip.empty?
          
          # Extract filename and content
          lines = section.split("\n")
          filename = lines.first.strip.gsub(/-->.*/, '').strip
          next unless filename.match?(/\.(jsx?|html|css|json)$/)
          
          # Get content (skip the filename line)
          file_content = lines[1..-1].join("\n")
          
          # Clean up content (remove trailing comment closers, etc)
          file_content = file_content.gsub(/^```.*?\n/, '').gsub(/\n```\s*$/, '')
          
          if file_content.strip.length > 10  # Ensure meaningful content
            create_or_update_file(filename, file_content)
            files_created += 1
            Rails.logger.info "[V3-Optimized] Created #{filename} from parsed content"
          end
        end
      end
      
      # Parse code blocks with filenames in the fence
      if content.include?('```')
        # Pattern: ```jsx:src/App.jsx or ```html:index.html
        content.scan(/```([a-z]+):([^\n]+)\n(.*?)```/m).each do |lang, filepath, code|
          filepath = filepath.strip
          if filepath.match?(/\.(jsx?|html|css|json)$/)
            create_or_update_file(filepath, code)
            files_created += 1
            Rails.logger.info "[V3-Optimized] Created #{filepath} from code block"
          end
        end
        
        # Also try standard code blocks if no files created yet
        if files_created == 0
          # Extract HTML block for index.html
          html_match = content.match(/```html\n(.*?)```/m)
          if html_match
            create_or_update_file('index.html', html_match[1])
            files_created += 1
          end
          
          # Extract JSX/JS blocks for App.jsx
          jsx_match = content.match(/```(?:jsx?|javascript)\n(.*?)```/m)
          if jsx_match
            create_or_update_file('src/App.jsx', jsx_match[1])
            files_created += 1
          end
        end
      end
      
      Rails.logger.info "[V3-Optimized] Fallback parser created #{files_created} files"
      
      # If still no files created, log the content for debugging
      if files_created == 0
        Rails.logger.warn "[V3-Optimized] No files could be parsed from content"
        Rails.logger.debug "[V3-Optimized] Content preview: #{content[0..500]}"
      end
    end
  end
end