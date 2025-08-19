module Ai
  class OpenRouterClient
    include HTTParty
    base_uri ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

    MODELS = {
      gpt5: "openai/gpt-5",  # Primary: 40% cheaper, larger context, advanced reasoning
      claude_sonnet_4: "anthropic/claude-sonnet-4", # Fallback: Reliable function calling
      kimi_k2: "moonshotai/kimi-k2",  # Alternative: Cost-effective with great quality
    }.freeze

    # Model specifications for dynamic token allocation
    MODEL_SPECS = {
      "openai/gpt-5" => { 
        context: 272_000,  # GPT-5 has 272K input context
        max_output: 128_000, # GPT-5 supports 128K output
        cost_per_1k: 0.00125 # $1.25/M input, $10/M output averaged
      },
      "moonshotai/kimi-k2" => { 
        context: 64_000, 
        max_output: 32_000, # Leave room for input in 64k total context
        cost_per_1k: 0.012 # Very cost-effective
      },
      "anthropic/claude-sonnet-4" => { 
        context: 200_000, 
        max_output: 60_000,  # Claude Sonnet 4 supports up to 64k output, use 60k for safety  
        cost_per_1k: 0.30   # Higher quality but more expensive
      }
    }.freeze

    DEFAULT_MODEL = :gpt5  # GPT-5 as default: 40% cheaper, better performance

    def initialize(api_key = nil)
      @api_key = api_key || ENV.fetch("OPENROUTER_API_KEY")
      @options = {
        headers: {
          "Authorization" => "Bearer #{@api_key}",
          "HTTP-Referer" => ENV.fetch("OPENROUTER_REFERER", "https://overskill.app"),
          "X-Title" => "OverSkill Platform",
          "Content-Type" => "application/json"
        },
        timeout: 300  # 5 minute timeout - GPT-5 needs more time for reasoning
      }
      @context_cache = ContextCacheService.new
      @error_handler = EnhancedErrorHandler.new
      
      # Initialize Anthropic client for prompt caching
      @anthropic_client = AnthropicClient.new if ENV["ANTHROPIC_API_KEY"]
      
      # Initialize GPT-5 client for OpenAI models
      # GPT-5 released August 7, 2025 - use direct OpenAI API
      openai_key = ENV["OPENAI_API_KEY"]
      if openai_key && openai_key != "dummy-key" && openai_key != "your-openai-key-here"
        # Use direct OpenAI API for GPT-5 models
        @gpt5_client = OpenaiGpt5Client.instance
        Rails.logger.info "[OpenRouter] Initialized with direct OpenAI GPT-5 client"
      else
        Rails.logger.info "[OpenRouter] No valid OpenAI key, will use OpenRouter fallback"
      end
    end

    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_cache: true, use_anthropic: true)
      # Use GPT-5 direct API for OpenAI models if available
      if @gpt5_client && gpt5_model?(model)
        Rails.logger.info "[AI] Using OpenAI GPT-5 direct API" if ENV["VERBOSE_AI_LOGGING"] == "true"
        
        # Determine reasoning level based on context
        reasoning_level = determine_reasoning_level(messages)
        
        begin
          # GPT-5 only supports default temperature (1.0)
          gpt5_temperature = 1.0
          
          return @gpt5_client.chat(
            messages,
            model: normalize_gpt5_model(model),
            temperature: gpt5_temperature,
            max_tokens: max_tokens,
            reasoning_level: reasoning_level,
            use_cache: use_cache
          )
        rescue => e
          Rails.logger.error "[AI] GPT-5 failed: #{e.message}"
          # Return failure instead of fallback to avoid tool_use_id issues  
          return { success: false, error: "GPT-5 failed: #{e.message}" }
        end
      end
      
      # Use Anthropic direct API for Claude models if available and requested
      if use_anthropic && @anthropic_client && model.to_s.include?("claude")
        Rails.logger.info "[AI] Using Anthropic direct API for #{model}" if ENV["VERBOSE_AI_LOGGING"] == "true"
        
        # Create cache breakpoints for optimal caching
        ai_standards = get_ai_standards_content
        cache_breakpoints = @anthropic_client.create_cache_breakpoints(ai_standards)
        
        return @anthropic_client.chat(
          messages, 
          model: model, 
          temperature: temperature, 
          max_tokens: max_tokens,
          use_cache: use_cache,
          cache_breakpoints: cache_breakpoints
        )
      end

      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end

      # Check cache first if enabled
      if use_cache
        request_hash = generate_request_hash(messages, model_id, temperature)
        cached_response = @context_cache.get_cached_model_response(request_hash)
        if cached_response
          Rails.logger.info "[AI] Using cached response for model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"
          return cached_response
        end
      end

      body = {
        model: model_id,
        messages: messages,
        max_tokens: max_tokens,
        stream: false
      }

      # Only include temperature for non-GPT-5 requests (OpenRouter path)
      body[:temperature] = temperature unless gpt5_model?(model_id)

      Rails.logger.info "[AI] Calling OpenRouter with model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("openrouter_chat_#{model_id}") do |attempt|
        response = self.class.post("/chat/completions", @options.merge(body: body.to_json))
        
        unless response.success?
          error_message = response.parsed_response["error"] || "HTTP #{response.code}"
          raise HTTParty::Error.new("OpenRouter API error: #{error_message}")
        end
        
        response
      end
      
      unless retry_result[:success]
        return {
          success: false,
          error: retry_result[:error],
          suggestion: retry_result[:suggestion],
          attempts: retry_result[:attempt]
        }
      end
      
      response = retry_result[:result]
      result = response.parsed_response
      usage = result.dig("usage")

      if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
        Rails.logger.info "[AI] Token usage - Prompt: #{usage["prompt_tokens"]}, Completion: #{usage["completion_tokens"]}, Cost: $#{calculate_cost(usage, model_id)}"
      end

      response_data = {
        success: true,
        content: result.dig("choices", 0, "message", "content"),
        usage: usage,
        model: model_id
      }

      # Cache successful response if caching is enabled
      if use_cache
        request_hash = generate_request_hash(messages, model_id, temperature)
        @context_cache.cache_model_response(request_hash, response_data)
      end

      response_data
    end

    def stream_chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, &block)
      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end
      
      # Disable streaming for GPT-5 models (requires org verification)
      use_streaming = !model_id.include?("gpt-5")
      
      body = {
        model: model_id,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: use_streaming  # Stream only for non-GPT-5 models
      }
      
      Rails.logger.info "[AI] Starting streaming chat with model: #{model_id}"
      
      uri = URI.parse("https://openrouter.ai/api/v1/chat/completions")
      
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Post.new(uri.path)
        request['Authorization'] = "Bearer #{@api_key}"
        request['Content-Type'] = 'application/json'
        request['HTTP-Referer'] = 'https://overskill.com'
        request['X-Title'] = 'OverSkill App Generation'
        request.body = body.to_json
        
        http.request(request) do |response|
          response.read_body do |chunk|
            # Parse SSE chunks
            chunk.split("\n").each do |line|
              next unless line.start_with?("data: ")
              
              data = line[6..-1].strip
              next if data == "[DONE]"
              
              begin
                json = JSON.parse(data)
                content = json.dig("choices", 0, "delta", "content")
                
                if content
                  # Yield the content chunk to the block
                  block.call(content)
                end
              rescue JSON::ParserError => e
                Rails.logger.warn "[AI] Failed to parse streaming chunk: #{e.message}"
              end
            end
          end
        end
      end
      
      Rails.logger.info "[AI] Streaming completed"
      { success: true }
    rescue => e
      Rails.logger.error "[AI] Streaming error: #{e.message}"
      { success: false, error: e.message }
    end
    
    def chat_with_tools(messages, tools, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_anthropic: true)
      # Use GPT-5 direct API for OpenAI models if available
      if @gpt5_client && gpt5_model?(model)
        Rails.logger.info "[AI] Using OpenAI GPT-5 direct API with tools" if ENV["VERBOSE_AI_LOGGING"] == "true"
        
        # Determine reasoning level based on context
        reasoning_level = determine_reasoning_level(messages)
        
        begin
          # GPT-5 only supports default temperature (1.0)
          gpt5_temperature = 1.0
          
          return @gpt5_client.chat_with_tools(
            messages,
            tools,
            model: normalize_gpt5_model(model),
            reasoning_level: reasoning_level,
            temperature: gpt5_temperature
          )
        rescue => e
          Rails.logger.error "[AI] GPT-5 with tools failed: #{e.message}"
          # Return failure instead of fallback to avoid tool_use_id issues
          return { success: false, error: "GPT-5 failed: #{e.message}" }
        end
      end
      
      # Use Anthropic direct API for Claude models if available and requested
      if use_anthropic && @anthropic_client && model.to_s.include?("claude")
        Rails.logger.info "[AI] Using Anthropic direct API with tools for #{model}" if ENV["VERBOSE_AI_LOGGING"] == "true"
        
        # Convert OpenAI format tools to Anthropic format
        anthropic_tools = convert_openai_tools_to_anthropic(tools)
        
        # Convert OpenAI format messages to Anthropic format
        anthropic_messages = convert_openai_messages_to_anthropic(messages)
        
        # Create cache breakpoints for optimal caching
        ai_standards = get_ai_standards_content
        cache_breakpoints = @anthropic_client.create_cache_breakpoints(ai_standards)
        
        return @anthropic_client.chat_with_tools(
          anthropic_messages, 
          anthropic_tools,
          model: model, 
          temperature: temperature, 
          max_tokens: max_tokens,
          use_cache: true,
          cache_breakpoints: cache_breakpoints
        )
      end

      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end

      body = {
        model: model_id,
        messages: messages,
        tools: tools,
        tool_choice: "auto", # Let the model decide when to use tools
        max_tokens: max_tokens,
        stream: false
      }

      # Only include temperature for non-GPT-5 requests (OpenRouter path)
      body[:temperature] = temperature unless gpt5_model?(model_id)

      Rails.logger.info "[AI] Calling OpenRouter with tools, model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("openrouter_tools_#{model_id}") do |attempt|
        response = self.class.post("/chat/completions", @options.merge(body: body.to_json))
        
        unless response.success?
          error_message = response.parsed_response["error"] || "HTTP #{response.code}"
          raise HTTParty::Error.new("OpenRouter API error: #{error_message}")
        end
        
        response
      end
      
      unless retry_result[:success]
        return {
          success: false,
          error: retry_result[:error],
          suggestion: retry_result[:suggestion],
          attempts: retry_result[:attempt]
        }
      end
      
      response = retry_result[:result]

      result = response.parsed_response
      usage = result.dig("usage")
      choice = result.dig("choices", 0)
      message = choice&.dig("message")

      if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
        Rails.logger.info "[AI] Token usage - Prompt: #{usage["prompt_tokens"]}, Completion: #{usage["completion_tokens"]}, Cost: $#{calculate_cost(usage, model_id)}"
      end

      # Check if the model used function calling
      tool_calls = message&.dig("tool_calls")
      
      # Return successful response regardless of whether tools were called
      # The AI might choose not to use tools, which is valid
      {
        success: true,
        content: message&.dig("content") || "",
        tool_calls: tool_calls || [],  # Return empty array if no tool calls
        usage: usage,
        model: model_id
      }
    end

    def generate_app(prompt, framework: "react", app_type: nil)
      # Load the generated app standards
      standards = ::File.read(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) rescue ""
      
      # Build comprehensive prompt with tech stack requirements
      full_prompt = <<~PROMPT
        Create a production-ready web application with these requirements:
        
        USER REQUEST: #{prompt}
        
        MANDATORY TECH STACK:
        - Frontend: React 18+ with TypeScript (NOT JavaScript)
        - Build: Vite
        - Styling: Tailwind CSS
        - Deployment: Cloudflare Workers (NOT Node.js)
        - Database: Supabase with Row-Level Security
        - State: Zustand
        - Forms: React Hook Form + Zod
        
        CRITICAL REQUIREMENTS:
        1. Include Supabase client with RLS context setting (setRLSContext function)
        2. Include Overskill analytics integration (auto-track page views)
        3. Include wrangler.toml for Cloudflare Workers deployment
        4. Use TypeScript for ALL code files (.tsx, .ts)
        5. Include complete package.json with exact dependencies
        
        #{standards}
      PROMPT
      
      # Use function calling for structured output - no more JSON parsing errors!
      messages = [
        {
          role: "system", 
          content: "You are an expert full-stack developer specializing in React, TypeScript, Cloudflare Workers, and Supabase. Generate complete, production-ready applications."
        },
        {
          role: "user", 
          content: full_prompt
        }
      ]

      tools = [
        {
          type: "function",
          function: {
            name: "generate_app",
            description: "Generate a complete web application with all necessary files",
            parameters: {
              type: "object",
              properties: {
                app: {
                  type: "object",
                  properties: {
                    name: { type: "string", description: "Application name" },
                    description: { type: "string", description: "What the app does" },
                    type: { type: "string", description: "App category" },
                    features: { 
                      type: "array", 
                      items: { type: "string" },
                      description: "List of key features"
                    },
                    tech_stack: { 
                      type: "array", 
                      items: { type: "string" },
                      description: "Technologies used"
                    }
                  },
                  required: ["name", "description", "type", "features", "tech_stack"]
                },
                files: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      path: { type: "string", description: "File path (e.g., index.html)" },
                      content: { type: "string", description: "Complete file content" }
                    },
                    required: ["path", "content"]
                  },
                  description: "All application files"
                },
                instructions: { 
                  type: "string", 
                  description: "Setup and deployment instructions" 
                },
                deployment_notes: { 
                  type: "string", 
                  description: "Important deployment considerations" 
                }
              },
              required: ["app", "files"]
            }
          }
        }
      ]

      # Use GPT-5 as primary (40% cost savings vs Sonnet-4!)
      Rails.logger.info "[AI] Using GPT-5 for superior generation with cost savings"
      result = chat_with_tools(messages, tools, model: :gpt5, temperature: 0.7, max_tokens: 32000)
      
      # Check if function calling was successful
      if result[:success] && result[:tool_calls]&.any?
        Rails.logger.info "[AI] GPT-5 function calling successful! Cost savings: 40-45%"
      else
        Rails.logger.warn "[AI] GPT-5 failed, trying Claude Sonnet 4 as fallback"
        result = chat_with_tools(messages, tools, model: :claude_sonnet_4, temperature: 0.7, max_tokens: 16000)
        
        # Track the fallback for monitoring
        Rails.logger.info "[AI] Claude Sonnet 4 fallback result: success=#{result[:success]}, tool_calls=#{result[:tool_calls]&.any?}"
      end
      
      result
    end

    def update_app(user_request, current_files, app_context)
      # Use function calling for app updates too
      messages = [
        {
          role: "system", 
          content: "You are an expert web developer. Use the update_app function to make precise changes to the existing application based on the user's request."
        },
        {
          role: "user", 
          content: "Update the application: #{user_request}\n\nCurrent files:\n#{current_files.map { |f| "#{f[:path]}: #{f[:content][0..200]}..." }.join("\n\n")}"
        }
      ]

      tools = [
        {
          type: "function",
          function: {
            name: "update_app",
            description: "Update specific files in the web application",
            parameters: {
              type: "object",
              properties: {
                changes: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      file_path: { type: "string", description: "Path of file to update" },
                      new_content: { type: "string", description: "Complete new file content" },
                      change_description: { type: "string", description: "What was changed" }
                    },
                    required: ["file_path", "new_content", "change_description"]
                  },
                  description: "List of file changes to make"
                },
                summary: { 
                  type: "string", 
                  description: "Summary of all changes made" 
                }
              },
              required: ["changes", "summary"]
            }
          }
        }
      ]

      # Use GPT-5 as primary model with increased token limit for complex apps
      result = chat_with_tools(messages, tools, model: :gpt5, temperature: 0.7, max_tokens: 32000)
      
      if !result[:success] || !result[:tool_calls]&.any?
        Rails.logger.warn "[AI] GPT-5 app update function calling failed, trying Claude Sonnet 4"
        result = chat_with_tools(messages, tools, model: :claude_sonnet_4, temperature: 0.7, max_tokens: 16000)
      end
      
      result
    end
    
    def analyze_app_update_request(request:, current_files:, app_context:)
      messages = [
        {role: "system", content: "You are an AI assistant helping to plan app updates. Analyze the request and create a detailed plan."},
        {role: "user", content: build_analysis_prompt(request, current_files, app_context)}
      ]
      
      response = chat(messages, model: :claude_sonnet, temperature: 0.3, max_tokens: 2000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          plan = JSON.parse(content, symbolize_names: true)
          { success: true, plan: plan }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse plan: #{e.message}" }
        end
      else
        response
      end
    end
    
    def execute_app_update(plan)
      messages = [
        {role: "system", content: "You are an expert web developer. Execute the plan and generate the necessary code changes."},
        {role: "user", content: build_execution_prompt(plan)}
      ]
      
      response = chat(messages, model: :kimi_k2, temperature: 0.5, max_tokens: 8000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          changes = JSON.parse(content, symbolize_names: true)
          { success: true, changes: changes }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse changes: #{e.message}" }
        end
      else
        response
      end
    end
    
    def fix_app_issues(issues:, current_files:)
      messages = [
        {role: "system", content: "You are an expert web developer. Fix the identified issues in the code."},
        {role: "user", content: build_fix_prompt(issues, current_files)}
      ]
      
      response = chat(messages, model: :kimi_k2, temperature: 0.3, max_tokens: 8000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          changes = JSON.parse(content, symbolize_names: true)
          { success: true, changes: changes }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse fixes: #{e.message}" }
        end
      else
        response
      end
    end

    private
    
    # Normalize model to OpenAI GPT-5 model id
    def normalize_gpt5_model(model)
      str = model.to_s
      return 'gpt-5' if str == 'gpt5' || str.include?('gpt-5')
      model
    end

    # Detect GPT-5 across symbols and strings (including OpenRouter ids)
    def gpt5_model?(model)
      str = (model.is_a?(Symbol) ? model.to_s : model.to_s).downcase
      str == 'gpt5' || str.include?('gpt-5') || str.include?('openai/gpt-5')
    end
    
    # Convert OpenAI format tools to Anthropic format
    def convert_openai_tools_to_anthropic(openai_tools)
      return [] unless openai_tools.is_a?(Array)
      
      openai_tools.map do |tool|
        if tool[:type] == "function" && tool[:function]
          {
            name: tool[:function][:name],
            description: tool[:function][:description],
            input_schema: tool[:function][:parameters] || {
              type: "object",
              properties: {},
              required: []
            }
          }
        else
          # If it's not in OpenAI format, log and skip
          Rails.logger.warn "[OpenRouterClient] Skipping tool with unexpected format: #{tool.inspect}"
          nil
        end
      end.compact
    end
    
    # Convert OpenAI format messages to Anthropic format
    def convert_openai_messages_to_anthropic(messages)
      return messages unless messages.is_a?(Array)
      
      Rails.logger.info "[OpenRouterClient] Converting #{messages.length} messages to Anthropic format" if ENV["VERBOSE_AI_LOGGING"] == "true"
      
      # Filter out any messages that might cause issues
      valid_messages = messages.select do |message|
        message.is_a?(Hash) && message[:role]
      end
      
      valid_messages.map do |message|
        if message[:role] == "tool"
          # Convert OpenAI tool result to Anthropic user message with tool_result
          tool_call_id = message[:tool_call_id] || message["tool_call_id"]
          content_value = message[:content] || message["content"]
          
          Rails.logger.debug "[OpenRouterClient] Converting tool result with ID: #{tool_call_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"
          
          {
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: tool_call_id,
                content: content_value
              }
            ]
          }
        elsif message[:role] == "assistant" && message[:tool_calls]
          # Convert OpenAI assistant message with tool_calls to Anthropic format
          content_parts = []
          
          # Add text content if present
          if message[:content] && !message[:content].empty?
            content_parts << { type: "text", text: message[:content] }
          end
          
          # Add tool use calls
          message[:tool_calls].each do |tool_call|
            if tool_call[:function]
              tool_id = tool_call[:id] || tool_call["id"]
              function_name = tool_call[:function][:name] || tool_call["function"]["name"]
              function_args = tool_call[:function][:arguments] || tool_call["function"]["arguments"] || "{}"
              
              arguments = begin
                JSON.parse(function_args)
              rescue
                {}
              end
              
              Rails.logger.debug "[OpenRouterClient] Converting tool_use with ID: #{tool_id}, name: #{function_name}" if ENV["VERBOSE_AI_LOGGING"] == "true"
              
              content_parts << {
                type: "tool_use",
                id: tool_id,
                name: function_name,
                input: arguments
              }
            end
          end
          
          {
            role: "assistant",
            content: content_parts
          }
        else
          # Return message as-is but remove tool_calls field if it exists for non-assistant messages
          clean_message = message.dup
          clean_message.delete(:tool_calls) unless message[:role] == "assistant"
          clean_message
        end
      end
    end
    
    def build_analysis_prompt(request, current_files, app_context)
      prompt = <<~PROMPT
        CRITICAL: You are working within OverSkill, a platform that generates client-side web apps deployed to Cloudflare Workers.
        
        PLATFORM CONSTRAINTS:
        - Apps are FILE-BASED ONLY (HTML, CSS, JS files served directly)
        - NO build processes, npm, package.json, node_modules, or compilation
        - NO server-side code, backends, or Node.js APIs
        - NO external package installation or complex imports
        - Apps run in sandboxed iframe environments with limited APIs
        - Use VANILLA JavaScript, HTML5, and CSS3 (with approved exceptions)
        
        APPROVED TECHNOLOGIES (work within OverSkill constraints):
        - ✅ React: Component-based architecture via CDN (react, react-dom via unpkg.com)
        - ✅ Tailwind CSS: Use full minified build via CDN (all utility classes available)
        - ✅ Shadcn/ui Components: Professional React components (adapt HTML/CSS to JSX)
        - ✅ Alpine.js: Lightweight JavaScript framework for non-React apps only
        - ✅ Chart.js: Professional data visualization (cdn.jsdelivr.net/npm/chart.js)
        - ✅ Lucide React: React icon components (unpkg.com/lucide-react)
        - ✅ Animate.css: Professional animations and transitions (cdnjs.cloudflare.com/ajax/libs/animate.css)
        - ✅ Modern ES6+ JavaScript features (async/await, destructuring, arrow functions)
        - ✅ CSS3 features (flexbox, grid, custom properties, animations)
        - ✅ HTML5 APIs (localStorage, sessionStorage, fetch, canvas, geolocation)
        
        FORBIDDEN APPROACHES:
        - Do NOT suggest npm install, build scripts, or package management
        - Do NOT recommend development servers, git clone, or repository operations
        - Do NOT propose service workers, external dependencies, or backend solutions
        - Do NOT suggest system-level debugging or server management
        
        CORRECT DEBUGGING APPROACH:
        - Use console.log() and browser DevTools for debugging
        - Implement try-catch blocks and error handling in JavaScript
        - Check DOM elements exist before manipulation
        - Use defensive programming and validation
        
        DESIGN EXCELLENCE REQUIREMENTS:
        Your goal is to create sophisticated, professional-grade applications that truly WOW users.
        
        VISUAL DESIGN STANDARDS:
        - Choose sophisticated color palettes with specific hex codes (e.g., #1a1a1a, #f8f9fa, accent colors)
        - Plan typography hierarchy for readability and elegance
        - Use generous white space and clean layouts
        - Leverage Shadcn/ui components for professional, accessible interfaces (buttons, cards, dialogs, forms)
        - Copy Shadcn/ui HTML/CSS directly - no installation required, works with Tailwind CDN
        - Consider industry-specific aesthetics (e.g., gallery-style for art apps, dashboard-style for business)
        - Create cohesive design systems using consistent component patterns
        
        DATABASE & BACKEND INTEGRATION:
        OverSkill provides secure backend database capabilities via Supabase integration:
        - Apps can have DATABASE TABLES with custom schemas (users, posts, products, etc.)
        - Tables support various COLUMN TYPES: text, number, boolean, date, datetime, select, multiselect
        - AUTHENTICATION via OAuth providers (Google, GitHub, Auth0) through secure Cloudflare Workers
        - API INTEGRATIONS (Stripe, SendGrid, OpenAI, etc.) proxied securely through Workers
        - NO direct database connections in client code - all data access via secure endpoints
        
        WHEN PLANNING APPS THAT NEED DATA:
        1. **IDENTIFY DATA REQUIREMENTS**: What entities need to be stored? (users, posts, comments, etc.)
        2. **DESIGN SCHEMA**: What fields does each entity need? (name, email, content, timestamps)
        3. **PLAN RELATIONSHIPS**: How do entities connect? (posts belong to users, comments belong to posts)
        4. **SUGGEST SCHEMA**: In your response, include a "database_schema" section with table definitions
        5. **CONSIDER AUTH**: Does the app need user authentication? Suggest appropriate OAuth providers
        6. **API NEEDS**: Does the app need third-party services? (payments, emails, AI features)
        
        SCHEMA SPECIFICATION FORMAT:
        ```json
        "database_schema": {
          "tables": [
            {
              "name": "users",
              "description": "Application user accounts",
              "columns": [
                {"name": "email", "type": "text", "required": true},
                {"name": "name", "type": "text", "required": true},
                {"name": "avatar_url", "type": "text", "required": false}
              ]
            },
            {
              "name": "posts", 
              "description": "Blog posts or content",
              "columns": [
                {"name": "title", "type": "text", "required": true},
                {"name": "content", "type": "text", "required": true},
                {"name": "author_email", "type": "text", "required": true},
                {"name": "published_at", "type": "datetime", "required": false}
              ]
            }
          ]
        }
        ```
        
        COMPLETE SYSTEM THINKING:
        - Plan holistic user experiences, not just individual features
        - Consider the complete data flow from user input to storage to display
        - Think about user authentication and authorization needs
        - Plan for data validation, error handling, and edge cases
        - Consider data relationships and how different sections connect
        - Include sample/placeholder data to make the app feel real and professional
        - Design for the complete user journey, not just technical functionality
        
        User Request: #{request}
        
        Current App Context:
        - Name: #{app_context[:name]}
        - Type: #{app_context[:type]}
        - Framework: #{app_context[:framework]} (IMPORTANT: Generate #{app_context[:framework]} code, not vanilla JS)
        
        Current Files:
        #{current_files.map { |f| "- #{f[:path]} (#{f[:type]})" }.join("\n")}
        
        Return a JSON response with this structure:
        {
          "analysis": "Deep analysis of user needs and how to create a sophisticated solution",
          "approach": "Professional, design-first approach using vanilla web technologies",
          "design_language": {
            "color_palette": {"primary": "#hex", "secondary": "#hex", "accent": "#hex", "background": "#hex"},
            "typography": "Description of font hierarchy and styling approach",
            "aesthetic": "Overall visual theme and inspiration (e.g., 'Clean gallery aesthetic', 'Modern dashboard')"
          },
          "steps": [
            {"description": "Step with design and UX considerations", "files_affected": ["file1.js"], "design_notes": "Visual/UX considerations"},
            {"description": "Step focusing on professional polish", "files_affected": ["file2.css"], "design_notes": "Aesthetic improvements"}
          ],
          "system_architecture": ["How different components work together as a cohesive system"],
          "user_experience_flow": ["Key user journeys and how they flow through the app"],
          "professional_touches": ["Specific elements that will make this app feel polished and impressive"]
        }
      PROMPT
    end
    
    def build_execution_prompt(plan)
      prompt = <<~PROMPT
        CRITICAL: Execute this plan within OverSkill's platform constraints.
        
        EXECUTION CONSTRAINTS:
        - Generate ONLY vanilla HTML, CSS, and JavaScript files (with approved exceptions)
        - NO build processes, imports, or external dependencies (except approved CDNs)
        - Files must be self-contained and work when served directly
        - Use modern JavaScript (ES6+) but ensure browser compatibility
        - Include proper error handling and defensive programming
        
        APPROVED EXTERNAL RESOURCES:
        - ✅ React: <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
        - ✅ React DOM: <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
        - ✅ Babel Standalone: <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script> (for JSX)
        - ✅ Tailwind CSS: Include via CDN link in HTML head section
        - ✅ Shadcn/ui Components: Adapt HTML/CSS to React JSX components
        - ✅ Alpine.js: <script src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js" defer></script> (vanilla apps only)
        - ✅ Chart.js: <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        - ✅ Lucide React: Use with React apps for consistent icons
        - ✅ Animate.css: <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/animate.css/4.1.1/animate.min.css">
        - ✅ OverSkill.js: <script src="overskill.js"></script> (enhanced error handling and editor communication)
        - ✅ Web fonts (Google Fonts, etc.) via CDN links
        
        IMPLEMENTATION REQUIREMENTS:
        - All JavaScript must work without compilation or bundling
        - CSS can be standard CSS3 OR Tailwind utility classes (via CDN)
        - HTML must be valid HTML5 that works in iframe sandbox
        - Include console.log statements for debugging
        - Add try-catch blocks around potentially failing operations
        
        TAILWIND CSS USAGE:
        - Include via: <link href="https://cdn.tailwindcss.com" rel="stylesheet">
        - Use utility classes freely (bg-blue-500, flex, grid, etc.)
        - All Tailwind classes are available (no purging/optimization needed)
        
        REACT COMPONENT USAGE (when framework is React):
        - Create functional React components with hooks (useState, useEffect)
        - Use JSX syntax with type="text/babel" for browser compilation
        - Adapt Shadcn/ui HTML to React JSX components
        - Use className instead of class for CSS classes
        - Implement proper React patterns (components, props, state)
        - Include React.createElement fallbacks if needed
        
        VANILLA JS USAGE (when framework is vanilla):
        - Alpine.js: Add x-data, x-show, x-on directives for interactivity
        - Direct DOM manipulation with modern JavaScript
        - Use standard HTML class attributes
        
        UNIVERSAL USAGE (all frameworks):
        - Chart.js: Create professional charts and data visualizations
        - Lucide Icons: Use appropriate icon system for framework
        - Animate.css: Add smooth animations with utility classes
        - OverSkill.js: Provides error handling, editor communication, and development tools
        
        Plan to Execute:
        #{plan.to_json}
        
        Generate the complete updated code for all affected files following OverSkill constraints.
        
        Return a JSON response with this structure:
        {
          "summary": "Brief summary of changes made (within platform constraints)",
          "files": [
            {
              "path": "filename.ext",
              "content": "complete vanilla file content here (no imports/build tools)",
              "summary": "What was changed in this file"
            }
          ],
          "whats_next": [
            {"title": "Client-side improvement", "description": "Suggestion using vanilla technologies"}
          ],
          "validation_issues": [
            {"severity": "warning", "title": "Issue", "description": "Description", "file": "file.js"}
          ]
        }
      PROMPT
    end
    
    def build_fix_prompt(issues, current_files)
      prompt = <<~PROMPT
        CRITICAL: Fix these issues within OverSkill's platform constraints.
        
        PLATFORM CONSTRAINTS:
        - Use ONLY vanilla HTML, CSS/Tailwind, and JavaScript  
        - NO build tools, npm, external packages, or server-side solutions
        - Implement client-side debugging with console.log and try-catch
        - Ensure code works when files are served directly (no compilation)
        
        APPROVED STYLING OPTIONS:
        - ✅ Standard CSS3 with all modern features
        - ✅ Tailwind CSS via CDN (all utility classes available)
        - ✅ Combination of custom CSS + Tailwind utilities
        
        Issues to Fix:
        #{issues.map { |i| "- #{i[:severity]}: #{i[:title]} in #{i[:file]}" }.join("\n")}
        
        Current Files:
        #{current_files.map { |f| "File: #{f[:path]}\n```\n#{f[:content]}\n```" }.join("\n\n")}
        
        DEBUGGING APPROACH:
        - Add console.log statements to trace execution
        - Use try-catch blocks around potentially failing code
        - Check if DOM elements exist before manipulating them
        - Validate data types and values before operations
        - Include fallback UI for error states
        
        Return a JSON response with this structure:
        {
          "summary": "Summary of fixes applied (using vanilla technologies)",
          "files": [
            {
              "path": "filename.ext",
              "content": "complete fixed file content with error handling"
            }
          ],
          "fixes": [
            {"issue": "Issue description", "solution": "How it was fixed using client-side approach"}
          ]
        }
      PROMPT
    end

    def calculate_cost(usage, model_id)
      # Cost estimates per 1M tokens from OpenRouter
      costs = {
        "openai/gpt-5" => {prompt: 1.25, completion: 10.00},  # GPT-5 pricing
        "moonshotai/kimi-k2" => {prompt: 0.30, completion: 0.30},  # $0.30 per 1M tokens
        "deepseek/deepseek-chat" => {prompt: 0.001, completion: 0.002},
        "google/gemini-1.5-flash" => {prompt: 0.00015, completion: 0.0006},
        "anthropic/claude-3.5-sonnet" => {prompt: 0.003, completion: 0.015}
      }

      rates = costs[model_id] || {prompt: 0.001, completion: 0.001}

      prompt_cost = (usage["prompt_tokens"] / 1_000_000.0) * rates[:prompt]
      completion_cost = (usage["completion_tokens"] / 1_000_000.0) * rates[:completion]

      (prompt_cost + completion_cost).round(6)
    end
    
    # Determine reasoning level based on request complexity
    def determine_reasoning_level(messages)
      content = messages.map { |m| m[:content] || m['content'] || '' }.join(' ')
      
      # High reasoning for complex tasks
      if content.match?(/complex|analyze|debug|architect|plan|strategy|optimize/i)
        :high
      # Low reasoning for simple queries
      elsif content.match?(/simple|quick|list|explain|what is|how to/i)
        :low
      # Minimal for basic responses
      elsif content.length < 200
        :minimal
      # Default to medium for most tasks
      else
        :medium
      end
    end

    private

    # Calculate optimal max_tokens based on prompt length and model capabilities
    def calculate_optimal_max_tokens(messages, model_id)
      specs = MODEL_SPECS[model_id]
      return 16000 unless specs # Fallback for unknown models - more generous
      
      # Estimate token count for messages (rough approximation: 1 token ≈ 3.5 characters for better accuracy)
      prompt_chars = messages.sum { |msg| msg[:content].to_s.length }
      estimated_prompt_tokens = (prompt_chars / 3.5).ceil
      
      # Calculate available space in context window
      safety_margin = 1000  # Larger safety margin for system messages, etc.
      available_tokens = specs[:context] - estimated_prompt_tokens - safety_margin
      
      # For app generation, prioritize maximum output space
      # Use 90% of available context or full max_output, whichever is smaller
      max_possible_output = [available_tokens, specs[:max_output]].min
      desired_output = (max_possible_output * 0.9).to_i
      
      # For very short prompts, ensure we get substantial output
      if estimated_prompt_tokens < 1000
        desired_output = [desired_output, specs[:max_output] * 0.8].max.to_i
      end
      
      # Ensure minimum viable output for app generation
      optimal_tokens = [desired_output, 4000].max
      
      Rails.logger.info "[AI] Token allocation for #{model_id}: prompt ~#{estimated_prompt_tokens}, available #{available_tokens}, output #{optimal_tokens}/#{specs[:max_output]} max" if ENV["VERBOSE_AI_LOGGING"] == "true"
      
      optimal_tokens
    end
    
    # Generate a consistent hash for request caching
    def generate_request_hash(messages, model_id, temperature)
      content = "#{messages.to_json}:#{model_id}:#{temperature}"
      Digest::SHA256.hexdigest(content)
    end
    
    # Get AI standards content for prompt caching
    def get_ai_standards_content
      @ai_standards ||= begin
        ::File.read(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) rescue ""
      end
    end
    
  end
end
