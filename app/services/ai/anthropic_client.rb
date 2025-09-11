require 'net/http'

module Ai
  # Custom error for rate limit issues
  class RateLimitError < StandardError; end
  
  # Anthropic API client with optional Helicone.ai integration for observability
  #
  # Helicone Integration:
  # - Set HELICONE_API_KEY in .env.local to enable observability and analytics
  # - Provides request/response logging, cost tracking, session tracking
  # - Enables caching at the API gateway level (in addition to local Redis cache)
  # - View analytics at https://app.helicone.ai/dashboard
  # 
  # Usage:
  #   client = Ai::AnthropicClient.instance
  #   response = client.chat(messages, helicone_session: "session-id")
  #   
  # Check status: rails helicone:status
  class AnthropicClient
    include HTTParty
    include Singleton
    
    # Use Helicone API gateway if key is available, otherwise use direct Anthropic
    def self.base_uri_for_helicone
      if ENV['HELICONE_API_KEY'].present?
        "https://anthropic.helicone.ai"
      else
        "https://api.anthropic.com"
      end
    end
    
    base_uri base_uri_for_helicone
    
    # CRITICAL: Set HTTParty timeout globally for all requests
    # This prevents Net::ReadTimeout errors on long-running tool responses
    default_timeout 500  # 8.3 minutes for complex tool-heavy generations (user confirmed needed)
    
    # Additional timeout settings for better control
    open_timeout 30  # Time to establish connection
    read_timeout 500 # Time to read response (matching default_timeout)

    MODELS = {
      claude_sonnet_4: "claude-sonnet-4-20250514",
      claude_opus_4: "claude-opus-4-1-20250805",
      claude_haiku_3_5: "claude-3-5-haiku-20241022",
    }.freeze

    # Model specifications for Anthropic direct API
    MODEL_SPECS = {
      "claude-sonnet-4-20250514" => { 
        context: 1_000_000,  # 1M context window with beta header
        standard_context: 200_000,  # Standard context window
        max_output: 64_000,  # Updated to API maximum
        cost_per_1k_input: 3.00,
        cost_per_1k_output: 15.00,
        cache_write_multiplier: 1.25,  # 25% more to write to cache
        cache_read_multiplier: 0.10,   # 90% savings on cached reads
        supports_extended_thinking: false,
        supports_interleaved_thinking: false,
        recommended_thinking_budget: 16_000  # 16k+ tokens for complex tasks
      },
      "claude-opus-4-1-20250805" => { 
        context: 200_000, 
        max_output: 4_096,
        cost_per_1k_input: 15.00,
        cost_per_1k_output: 75.00,
        cache_write_multiplier: 1.25,
        cache_read_multiplier: 0.10,
        supports_extended_thinking: false,
        supports_interleaved_thinking: false,
        recommended_thinking_budget: 16_000  # 16k+ tokens for complex tasks
      },
      "claude-3-5-haiku-20241022" => { 
        context: 200_000, 
        max_output: 8_192,
        cost_per_1k_input: 1.00,
        cost_per_1k_output: 5.00,
        cache_write_multiplier: 1.25,
        cache_read_multiplier: 0.10
      }
    }.freeze

    DEFAULT_MODEL = :claude_sonnet_4
    CACHE_BREAKPOINT_TOKEN_MIN = 1024  # Anthropic's minimum for caching

    def initialize(api_key = nil)
      @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY")
      
      # Get the model ID string for checking specs
      default_model_id = MODELS[DEFAULT_MODEL]
      
      # Build base headers
      beta_features = ["prompt-caching-2024-07-31"]
      if MODEL_SPECS[default_model_id] && MODEL_SPECS[default_model_id][:supports_interleaved_thinking]
        beta_features << "interleaved-thinking-2025-05-14"
      end
      beta_features << "context-1m-2025-08-07"
      
      @base_headers = {
        "x-api-key" => @api_key,
        "content-type" => "application/json",
        "anthropic-version" => "2023-06-01",
        "anthropic-beta" => beta_features.join(",")
      }
      
      @context_cache = ContextCacheService.new
      @error_handler = EnhancedErrorHandler.new
    end
    
    # Build options with current environment state
    def build_request_options
      helicone_key = ENV['HELICONE_API_KEY']
      headers = @base_headers.dup
      
      Rails.logger.debug "[AI] Building request options with Helicone key: #{helicone_key.to_s[0..8]}"
      # Add Helicone headers if API key is available
      if helicone_key.present?
        headers["Helicone-Auth"] = "Bearer #{helicone_key}"
        
        # Only enable Helicone caching if explicitly enabled via environment variable
        if ENV['HELICONE_CACHE_ENABLED'] == 'true'
          headers["Helicone-Cache-Enabled"] = "true"
          Rails.logger.info "[AI] Using Helicone API gateway with caching enabled"
        else
          Rails.logger.info "[AI] Using Helicone API gateway (caching disabled)"
        end
      else
        Rails.logger.debug "[AI] Using direct Anthropic API (set HELICONE_API_KEY for observability)"
      end
      
      {
        headers: headers
        # Timeout is now set globally at class level to prevent Net::ReadTimeout
      }
    end

    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_cache: true, cache_breakpoints: [], helicone_session: nil, helicone_path: nil, extended_thinking: false, thinking_budget: nil, stream: false)
      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end

      # Apply cache breakpoints to messages if caching enabled
      if use_cache && cache_breakpoints.any?
        messages = apply_cache_breakpoints(messages, cache_breakpoints)
      end

      # Check our Redis cache first
      if use_cache
        request_hash = generate_request_hash(messages, model_id, temperature)
        cached_response = @context_cache.get_cached_model_response(request_hash)
        if cached_response
          Rails.logger.info "[AI] Using Redis cached response for model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"
          return cached_response
        end
      end

      # Handle system messages - preserve cache optimizations while fixing caching
      system_message = nil
      api_messages = []
      
      messages.each do |msg|
        if msg[:role] == "system"
          if msg[:cache_control]
            # System message has cache_control - keep it in messages array for proper caching
            api_messages << msg
          else
            # Regular system message - use legacy system parameter
            system_message = msg[:content]
          end
        else
          api_messages << msg
        end
      end

      body = {
        model: model_id,
        messages: api_messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      
      # Enable streaming only when explicitly requested
      body[:stream] = true if stream
      
      # Add system message as top-level parameter if present
      # Supports both string and array format for prompt caching
      if system_message
        # If system_message is already an array (for caching), use it directly
        # Otherwise wrap string in array format
        if system_message.is_a?(Array)
          body[:system] = system_message
        else
          body[:system] = system_message
        end
      end

      # Enhanced debugging for API calls
      Rails.logger.info "[AnthropicClient] API Call Details:"
      Rails.logger.info "  Model: #{model_id}"
      Rails.logger.info "  Messages: #{api_messages.size} messages"
      Rails.logger.info "  System prompt: #{system_message.is_a?(Array) ? 'Array format' : (system_message.present? ? 'String format' : 'None')}"
      Rails.logger.info "  Temperature: #{temperature}"
      Rails.logger.info "  Max tokens: #{max_tokens}"
      
      # Debug message structure without content
      if ENV["DEBUG_ANTHROPIC"] == "true"
        api_messages.each_with_index do |msg, idx|
          Rails.logger.info "  Message #{idx}: role=#{msg[:role]}"
          if msg[:content].is_a?(Array)
            msg[:content].each do |block|
              Rails.logger.info "    - Block type: #{block[:type]}"
              if block[:type] == 'thinking'
                Rails.logger.info "      Has thinking: #{block[:thinking].present?}"
                Rails.logger.info "      Has signature: #{block[:signature].present?}"
              end
            end
          else
            Rails.logger.info "    - Content type: String (#{msg[:content].to_s.length} chars)"
          end
        end
      end

      # Prepare request options with optional Helicone session tracking
      request_options = build_request_options.merge(body: body.to_json)
      helicone_key = ENV['HELICONE_API_KEY']
      if helicone_key.present? && helicone_session.present?
        request_options[:headers] = request_options[:headers].merge({
          "Helicone-Session-Id" => helicone_session,
          "Helicone-Session-Path" => helicone_path || "/app-generation",
          "Helicone-Session-Name" => "OverSkill-App-Generation"
        })
      end

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("anthropic_chat_#{model_id}") do |attempt|
        response = self.class.post("/v1/messages", request_options)
        
        unless response.success?
          # Check if response is HTML (like Cloudflare errors)
          response_body = response.body rescue ""
          if response_body.include?('<html') || response_body.include?('<!DOCTYPE') || response_body.include?('Worker exceeded resource limits')
            Rails.logger.error "[AnthropicClient] Received HTML error response: #{response_body[0..500]}"
            
            error_message = if response_body.include?('Worker exceeded resource limits')
              "The AI service temporarily exceeded resource limits. Please try again in a moment."
            elsif response_body.include?('Cloudflare')
              "Service temporarily unavailable. Please try again."
            else
              "An unexpected error occurred (HTTP #{response.code}). Please try again."
            end
            
            error_details = { "message" => error_message }
            error_type = "service_error"
          else
            # Try to parse JSON error response
            error_details = response.parsed_response["error"] rescue {}
            error_details ||= {}
            error_message = error_details["message"] || "HTTP #{response.code}"
            error_type = error_details["type"] || "unknown_error"
          end
          
          Rails.logger.error "[AnthropicClient] API Error Response:"
          Rails.logger.error "  Type: #{error_type}"
          Rails.logger.error "  Message: #{error_message}"
          Rails.logger.error "  HTTP Code: #{response.code}"
          
          # Check for rate limit error
          if error_type == "rate_limit_error" || response.code == 429
            # Extract rate limit details from error message
            if error_message.include?("0 input tokens per minute")
              Rails.logger.error "[AnthropicClient] CRITICAL: API key has 0 token rate limit - API access is disabled"
              raise RateLimitError.new("Your Anthropic API key has no available tokens. Please check your API key status and billing at console.anthropic.com")
            else
              Rails.logger.error "[AnthropicClient] Rate limit exceeded: #{error_message}"
              raise RateLimitError.new("Anthropic API rate limit exceeded. Please wait a moment and try again. Details: #{error_message}")
            end
          end
          
          # Check for overload error and fallback to Opus if using Sonnet
          if error_type == "overloaded_error" && model == :claude_sonnet_4 && attempt == 1
            Rails.logger.info "[AnthropicClient] Sonnet overloaded, falling back to Opus 4.1"
            
            # Update model to Opus for this attempt
            model_id = MODELS[:claude_opus_4]
            body[:model] = model_id
            request_options[:body] = body.to_json
            
            # Retry with Opus immediately
            response = self.class.post("/v1/messages", request_options)
            
            unless response.success?
              error_details = response.parsed_response["error"] || {}
              error_message = error_details["message"] || "HTTP #{response.code}"
              Rails.logger.error "[AnthropicClient] Opus fallback also failed: #{error_message}"
              raise HTTParty::Error.new("Both Sonnet and Opus failed: #{error_message}")
            end
            
            Rails.logger.info "[AnthropicClient] Successfully fell back to Opus 4.1"
            return response  # Return successful Opus response
          end
          
          # Log the full error for debugging if needed
          if ENV["DEBUG_ANTHROPIC"] == "true"
            Rails.logger.error "  Full error: #{error_details.inspect}"
          end
          
          raise HTTParty::Error.new("Anthropic API error: #{error_message}")
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
      usage = result.is_a?(Hash) ? result.dig("usage") : nil

      # Log cache statistics if available
      if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
        cache_creation_tokens = usage["cache_creation_input_tokens"] || 0
        cache_read_tokens = usage["cache_read_input_tokens"] || 0
        regular_input_tokens = usage["input_tokens"] || 0
        output_tokens = usage["output_tokens"] || 0
        
        cost = calculate_cost_with_cache(usage, model_id)
        cache_savings = calculate_cache_savings(usage, model_id)
        
        helicone_status = ENV['HELICONE_API_KEY'].present? ? " [Helicone: ✓]" : ""
        Rails.logger.info "[AI] Anthropic usage#{helicone_status} - Input: #{regular_input_tokens}, Output: #{output_tokens}, Cache Created: #{cache_creation_tokens}, Cache Read: #{cache_read_tokens}, Cost: $#{cost}, Savings: $#{cache_savings}"
      end

      response_data = {
        success: true,
        content: result.is_a?(Hash) ? result.dig("content", 0, "text") : nil,
        usage: usage,
        model: model_id,
        cache_performance: extract_cache_performance(usage)
      }

      # Cache successful response in Redis
      if use_cache
        request_hash = generate_request_hash(messages, model_id, temperature)
        @context_cache.cache_model_response(request_hash, response_data)
      end

      response_data
    end

    # Incremental streaming method that dispatches tools as they arrive
    # Rather than waiting for the complete response
    def stream_chat_with_tools_incremental(messages, tools, callbacks = {}, options = {})
      streamer = IncrementalToolStreamer.new(self)
      streamer.stream_chat_with_tools(messages, tools, callbacks, options)
    end

    def chat_with_tools(messages, tools, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_cache: true, cache_breakpoints: [], helicone_session: nil, helicone_path: nil, extended_thinking: true, thinking_budget: nil, stream: false)
      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end

      # Apply cache breakpoints to messages if caching enabled
      if use_cache && cache_breakpoints.any?
        messages = apply_cache_breakpoints(messages, cache_breakpoints)
      end

      # Handle system messages - preserve cache optimizations while fixing caching  
      system_message = nil
      api_messages = []
      
      messages.each do |msg|
        if msg[:role] == "system"
          if msg[:cache_control]
            # System message has cache_control - keep it in messages array for proper caching
            api_messages << msg
          else
            # Regular system message - use legacy system parameter
            system_message = msg[:content]
          end
        else
          api_messages << msg
        end
      end

      # Format tools for Anthropic API (requires input_schema field)
      formatted_tools = format_tools_for_anthropic(tools)
      
      body = {
        model: model_id,
        messages: api_messages,
        tools: formatted_tools,
        tool_choice: { type: "auto" },
        temperature: temperature,
        max_tokens: max_tokens
      }
      
      # Enable streaming only when explicitly requested for tool execution
      body[:stream] = true if stream
      
      # Add system message as top-level parameter if present
      # Supports both string and array format for prompt caching
      if system_message
        # If system_message is already an array (for caching), use it directly
        # Otherwise use string format
        body[:system] = system_message
      end
      
      # Add extended thinking configuration for Claude 4 models
      if extended_thinking && MODEL_SPECS[model_id]&.dig(:supports_extended_thinking)
        thinking_tokens = thinking_budget || MODEL_SPECS[model_id][:recommended_thinking_budget]
        
        # According to the user's example, this is the correct format
        body[:thinking] = {
          type: "enabled",
          budget_tokens: thinking_tokens
        }
        
        # CRITICAL: Temperature must be 1 when thinking is enabled
        body[:temperature] = 1.0
        
        Rails.logger.info "[AI] Extended thinking enabled with budget: #{thinking_tokens} tokens, temperature set to 1.0" if ENV["VERBOSE_AI_LOGGING"] == "true"
      end

      # Enhanced debugging for tool calls
      Rails.logger.info "[AnthropicClient] Tool API Call Details:"
      Rails.logger.info "  Model: #{model_id}"
      Rails.logger.info "  Messages: #{api_messages.size} messages"
      Rails.logger.info "  Tools: #{formatted_tools.size} tools available"
      Rails.logger.info "  System prompt: #{system_message.present? ? 'Present' : 'None'}"
      Rails.logger.info "  Extended thinking: #{body[:thinking].present? ? 'Enabled' : 'Disabled'}"
      Rails.logger.info "  Temperature: #{temperature}"
      
      # Debug message structure for tool calls
      if ENV["DEBUG_ANTHROPIC"] == "true"
        api_messages.each_with_index do |msg, idx|
          Rails.logger.info "  Message #{idx}: role=#{msg[:role]}"
          if msg[:content].is_a?(Array)
            msg[:content].each do |block|
              Rails.logger.info "    - Block: #{block[:type]}"
              if block[:type] == 'thinking'
                Rails.logger.info "      thinking field: #{block[:thinking].present?}"
                Rails.logger.info "      signature field: #{block[:signature].present?}"
              elsif block[:type] == 'tool_use'
                Rails.logger.info "      tool: #{block[:name]}"
              elsif block[:type] == 'tool_result'
                Rails.logger.info "      tool_use_id: #{block[:tool_use_id]}"
              end
            end
          else
            Rails.logger.info "    - Content: String (#{msg[:content].to_s.length} chars)"
          end
        end
      end

      # Prepare request options with optional Helicone session tracking
      request_options = build_request_options.merge(body: body.to_json)
      helicone_key = ENV['HELICONE_API_KEY']
      if helicone_key.present? && helicone_session.present?
        request_options[:headers] = request_options[:headers].merge({
          "Helicone-Session-Id" => helicone_session,
          "Helicone-Session-Path" => helicone_path || "/tool-calling",
          "Helicone-Session-Name" => "OverSkill-Tool-Calling"
        })
      end

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("anthropic_tools_#{model_id}") do |attempt|
        response = self.class.post("/v1/messages", request_options)
        
        unless response.success?
          # Check if response is HTML (like Cloudflare errors)
          response_body = response.body rescue ""
          if response_body.include?('<html') || response_body.include?('<!DOCTYPE') || response_body.include?('Worker exceeded resource limits')
            Rails.logger.error "[AnthropicClient] Received HTML error response: #{response_body[0..500]}"
            
            error_message = if response_body.include?('Worker exceeded resource limits')
              "The AI service temporarily exceeded resource limits. Please try again in a moment."
            elsif response_body.include?('Cloudflare')
              "Service temporarily unavailable. Please try again."
            else
              "An unexpected error occurred (HTTP #{response.code}). Please try again."
            end
            
            error_details = { "message" => error_message }
            error_type = "service_error"
          else
            # Try to parse JSON error response
            error_details = response.parsed_response["error"] rescue {}
            error_details ||= {}
            error_message = error_details["message"] || "HTTP #{response.code}"
            error_type = error_details["type"] || "unknown_error"
          end
          
          Rails.logger.error "[AnthropicClient] API Error Response:"
          Rails.logger.error "  Type: #{error_type}"
          Rails.logger.error "  Message: #{error_message}"
          Rails.logger.error "  HTTP Code: #{response.code}"
          
          # Check for rate limit error
          if error_type == "rate_limit_error" || response.code == 429
            # Extract rate limit details from error message
            if error_message.include?("0 input tokens per minute")
              Rails.logger.error "[AnthropicClient] CRITICAL: API key has 0 token rate limit - API access is disabled"
              raise RateLimitError.new("Your Anthropic API key has no available tokens. Please check your API key status and billing at console.anthropic.com")
            else
              Rails.logger.error "[AnthropicClient] Rate limit exceeded: #{error_message}"
              raise RateLimitError.new("Anthropic API rate limit exceeded. Please wait a moment and try again. Details: #{error_message}")
            end
          end
          
          # Check for overload error and fallback to Opus if using Sonnet
          if error_type == "overloaded_error" && model == :claude_sonnet_4 && attempt == 1
            Rails.logger.info "[AnthropicClient] Sonnet overloaded during tool call, falling back to Opus 4.1"
            
            # Update model to Opus for this attempt
            model_id = MODELS[:claude_opus_4]
            body[:model] = model_id
            
            # Adjust max_tokens for Opus (it has lower limit)
            body[:max_tokens] = [body[:max_tokens], 4096].min
            
            request_options[:body] = body.to_json
            
            # Retry with Opus immediately
            response = self.class.post("/v1/messages", request_options)
            
            unless response.success?
              error_details = response.parsed_response["error"] || {}
              error_message = error_details["message"] || "HTTP #{response.code}"
              Rails.logger.error "[AnthropicClient] Opus fallback also failed: #{error_message}"
              raise HTTParty::Error.new("Both Sonnet and Opus failed: #{error_message}")
            end
            
            Rails.logger.info "[AnthropicClient] Successfully fell back to Opus 4.1 for tool call"
            return response  # Return successful Opus response
          end
          
          # Log the full error for debugging if needed
          if ENV["DEBUG_ANTHROPIC"] == "true"
            Rails.logger.error "  Full error: #{error_details.inspect}"
          end
          
          raise HTTParty::Error.new("Anthropic API error: #{error_message}")
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
      usage = result.is_a?(Hash) ? result.dig("usage") : nil
      
      if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
        cache_creation_tokens = usage["cache_creation_input_tokens"] || 0
        cache_read_tokens = usage["cache_read_input_tokens"] || 0
        regular_input_tokens = usage["input_tokens"] || 0
        output_tokens = usage["output_tokens"] || 0
        
        cost = calculate_cost_with_cache(usage, model_id)
        cache_savings = calculate_cache_savings(usage, model_id)
        
        helicone_status = ENV['HELICONE_API_KEY'].present? ? " [Helicone: ✓]" : ""
        Rails.logger.info "[AI] Anthropic tools usage#{helicone_status} - Input: #{regular_input_tokens}, Output: #{output_tokens}, Cache Created: #{cache_creation_tokens}, Cache Read: #{cache_read_tokens}, Cost: $#{cost}, Savings: $#{cache_savings}"
      end

      # FIXED: Handle both streaming and non-streaming response formats
      tool_calls = []
      thinking_blocks = []
      text_content = ""
      stop_reason = nil
      
      if stream
        # STREAMING RESPONSE FORMAT: Process streamed response chunks
        Rails.logger.info "[AnthropicClient] Processing streaming response format"
        
        if result.is_a?(String)
          # Streaming responses may come as concatenated JSON lines
          lines = result.split("\n").select { |line| line.strip.start_with?("data:") }
          
          lines.each do |line|
            begin
              json_data = line.sub(/^data:\s*/, "").strip
              next if json_data == "[DONE]" || json_data.empty?
              
              chunk = JSON.parse(json_data)
              
              # Handle different chunk types  
              case chunk["type"]
              when "content_block_start"
                block = chunk.dig("content_block")
                if block&.dig("type") == "tool_use"
                  # Start of a tool use block
                  tool_calls << {
                    "id" => block["id"],
                    "type" => "function", 
                    "function" => {
                      "name" => block["name"],
                      "arguments" => "" # Will be built incrementally
                    },
                    "partial_input" => ""
                  }
                end
              when "content_block_delta"
                delta = chunk.dig("delta")
                if delta&.dig("type") == "input_json_delta" && tool_calls.any?
                  # Add to the partial input of the last tool call
                  tool_calls.last["partial_input"] += delta["partial_json"] || ""
                elsif delta&.dig("type") == "text_delta"
                  text_content += delta["text"] || ""
                end
              when "content_block_stop"
                # Finalize the last tool call if it exists
                if tool_calls.any? && tool_calls.last["partial_input"]
                  begin
                    full_input = JSON.parse(tool_calls.last["partial_input"])
                    tool_calls.last["function"]["arguments"] = full_input.to_json
                    tool_calls.last.delete("partial_input")
                  rescue JSON::ParserError => e
                    Rails.logger.error "[AnthropicClient] Failed to parse tool input: #{e.message}"
                    tool_calls.pop # Remove invalid tool call
                  end
                end
              when "message_stop"
                stop_reason = chunk["stop_reason"] || "stop"
              end
              
            rescue JSON::ParserError => e
              Rails.logger.error "[AnthropicClient] Failed to parse streaming chunk: #{e.message}"
              next
            end
          end
          
        elsif result.is_a?(Hash) && result["content"]
          # Fallback: Treat as regular response format
          content_blocks = result["content"] || []
          stop_reason = result["stop_reason"]
          
          content_blocks.each do |block|
            case block["type"]
            when "tool_use"
              tool_calls << {
                "id" => block["id"],
                "type" => "function",
                "function" => {
                  "name" => block["name"],
                  "arguments" => block["input"].to_json
                }
              }
            when "text"
              text_content += block["text"] || ""
            end
          end
        end
        
        Rails.logger.info "[AnthropicClient] Streaming response parsed: #{tool_calls.size} tools, #{text_content.length} chars content"
        
      else
        # NON-STREAMING RESPONSE FORMAT: Standard processing
        Rails.logger.debug "[AnthropicClient] Processing non-streaming response format" if ENV["VERBOSE_AI_LOGGING"] == "true"
        
        content_blocks = result.is_a?(Hash) ? (result.dig("content") || []) : []
        stop_reason = result.is_a?(Hash) ? result.dig("stop_reason") : nil
        
        content_blocks.each do |block|
          case block["type"]
          when "tool_use"
            tool_calls << {
              "id" => block["id"],
              "type" => "function",
              "function" => {
                "name" => block["name"],
                "arguments" => block["input"].to_json
              }
            }
          when "thinking"
            thinking_blocks << {
              "type" => "thinking",
              "thinking" => block["thinking"],  # CORRECT: Use 'thinking' not 'content'!
              "signature" => block["signature"]  # Preserve cryptographic signature
            }
          when "text"
            text_content += block["text"] || ""
          end
        end
      end

      {
        success: true,
        content: text_content,
        tool_calls: tool_calls,
        thinking_blocks: thinking_blocks,
        stop_reason: stop_reason,
        usage: usage,
        model: model_id,
        cache_performance: extract_cache_performance(usage)
      }
    end

    # Create cache breakpoints for frequently reused context
    def create_cache_breakpoints(ai_standards_content, conversation_history = [])
      breakpoints = []
      
      # AI standards are reused across all generations - perfect for caching
      if ai_standards_content && ai_standards_content.length > CACHE_BREAKPOINT_TOKEN_MIN * 3.5
        breakpoints << {
          type: "ai_standards",
          content: ai_standards_content,
          cache_control: { type: "ephemeral" }
        }
      end
      
      # Long conversation history can be cached
      if conversation_history.any?
        total_chars = conversation_history.sum { |msg| msg[:content].to_s.length }
        if total_chars > CACHE_BREAKPOINT_TOKEN_MIN * 3.5
          breakpoints << {
            type: "conversation_history", 
            messages: conversation_history,
            cache_control: { type: "ephemeral" }
          }
        end
      end
      
      breakpoints
    end

    # Check if Helicone integration is active
    def helicone_enabled?
      ENV['HELICONE_API_KEY'].present?
    end

    # Get Helicone dashboard info
    def helicone_info
      return { enabled: false } unless helicone_enabled?
      
      {
        enabled: true,
        dashboard_url: "https://app.helicone.ai/dashboard",
        api_endpoint: "https://anthropic.helicone.ai",
        features: ["Observability", "Caching", "Session Tracking", "Cost Analytics"]
      }
    end

    # Check if we have access to 1M context window beta
    def has_1m_context_access?
      # Test with a request just over 200K tokens to see if 1M window is available
      # This is determined by making an actual API call since there's no direct way to check
      @has_1m_context_cached ||= test_1m_context_access
    end

    # Get current context window info
    def context_window_info
      {
        standard_window: 200_000,
        beta_window: 1_000_000,
        has_beta_access: has_1m_context_access?,
        beta_activation_threshold: 200_000,
        beta_rate_limits: {
          input_tokens_per_min: 500_000,
          output_tokens_per_min: 100_000
        }
      }
    end

    private
    
    # Format tools from OpenAI format to Anthropic format
    def format_tools_for_anthropic(tools)
      return [] if tools.blank?
      
      tools.map do |tool|
        {
          name: tool["name"] || tool[:name],
          description: tool["description"] || tool[:description],
          input_schema: tool["parameters"] || tool[:parameters] || {
            type: "object",
            properties: {},
            required: []
          }
        }
      end
    end

    # Apply cache breakpoints to messages for Anthropic prompt caching
    def apply_cache_breakpoints(messages, breakpoints)
      return messages if breakpoints.empty?
      
      cached_messages = messages.deep_dup
      
      breakpoints.each do |breakpoint|
        case breakpoint[:type]
        when "ai_standards"
          # Find system message and add cache control
          system_msg = cached_messages.find { |msg| msg[:role] == "system" }
          if system_msg
            system_msg[:cache_control] = breakpoint[:cache_control]
          end
        when "conversation_history"
          # Add cache control to the last message before current user message
          if cached_messages.length > 1
            cached_messages[-2][:cache_control] = breakpoint[:cache_control]
          end
        end
      end
      
      cached_messages
    end

    def calculate_optimal_max_tokens(messages, model_id)
      specs = MODEL_SPECS[model_id]
      return 8000 unless specs # Fallback for unknown models
      
      # Estimate token count for messages
      prompt_chars = messages.sum { |msg| msg[:content].to_s.length }
      estimated_prompt_tokens = (prompt_chars / 3.5).ceil
      
      # Calculate available space in context window
      safety_margin = 1000
      available_tokens = specs[:context] - estimated_prompt_tokens - safety_margin
      
      # Use most of available context or max output, whichever is smaller
      max_possible_output = [available_tokens, specs[:max_output]].min
      optimal_tokens = (max_possible_output * 0.9).to_i
      
      # Ensure minimum viable output for agent operations
      optimal_tokens = [optimal_tokens, 8000].max
      
      Rails.logger.info "[AI] Anthropic token allocation for #{model_id}: prompt ~#{estimated_prompt_tokens}, output #{optimal_tokens}/#{specs[:max_output]} max" if ENV["VERBOSE_AI_LOGGING"] == "true"
      
      optimal_tokens
    end

    def calculate_cost_with_cache(usage, model_id)
      specs = MODEL_SPECS[model_id]
      return 0.0 unless specs
      
      # Regular input tokens (no cache)
      regular_input_cost = ((usage["input_tokens"] || 0) / 1000.0) * specs[:cost_per_1k_input]
      
      # Cache creation tokens (25% more expensive)
      cache_creation_cost = ((usage["cache_creation_input_tokens"] || 0) / 1000.0) * specs[:cost_per_1k_input] * specs[:cache_write_multiplier]
      
      # Cache read tokens (90% savings)
      cache_read_cost = ((usage["cache_read_input_tokens"] || 0) / 1000.0) * specs[:cost_per_1k_input] * specs[:cache_read_multiplier]
      
      # Output tokens (normal price)
      output_cost = ((usage["output_tokens"] || 0) / 1000.0) * specs[:cost_per_1k_output]
      
      total_cost = regular_input_cost + cache_creation_cost + cache_read_cost + output_cost
      total_cost.round(6)
    end

    def calculate_cache_savings(usage, model_id)
      specs = MODEL_SPECS[model_id]
      return 0.0 unless specs
      
      # Calculate what cache read tokens would have cost without caching
      cache_read_tokens = usage["cache_read_input_tokens"] || 0
      full_price_cost = (cache_read_tokens / 1000.0) * specs[:cost_per_1k_input]
      cached_price_cost = (cache_read_tokens / 1000.0) * specs[:cost_per_1k_input] * specs[:cache_read_multiplier]
      
      savings = full_price_cost - cached_price_cost
      savings.round(6)
    end

    def extract_cache_performance(usage)
      return {} unless usage
      
      {
        cache_creation_tokens: usage["cache_creation_input_tokens"] || 0,
        cache_read_tokens: usage["cache_read_input_tokens"] || 0,
        regular_input_tokens: usage["input_tokens"] || 0,
        output_tokens: usage["output_tokens"] || 0,
        cache_hit_rate: calculate_cache_hit_rate(usage)
      }
    end

    def calculate_cache_hit_rate(usage)
      cache_read = usage["cache_read_input_tokens"] || 0
      total_input = (usage["input_tokens"] || 0) + (usage["cache_creation_input_tokens"] || 0) + cache_read
      
      return 0.0 if total_input == 0
      (cache_read.to_f / total_input * 100).round(2)
    end

    def generate_request_hash(messages, model_id, temperature)
      # Include cache breakpoints in hash for proper cache separation
      content = "#{messages.to_json}:#{model_id}:#{temperature}"
      Digest::SHA256.hexdigest(content)
    end

    # Test if we have 1M context window access by attempting a >200K token request
    def test_1m_context_access
      return false # Based on our test, we currently don't have 1M access
      
      # Uncomment and modify this code if you want to test programmatically:
      # begin
      #   # Create a test prompt just over 200K tokens
      #   test_content = "Test content. " * 15000  # Rough approximation
      #   test_messages = [
      #     { role: "user", content: test_content }
      #   ]
      #   
      #   response = chat(test_messages, model: :claude_sonnet_4, max_tokens: 100, use_cache: false)
      #   
      #   # If successful, we have 1M access
      #   return response[:success]
      # rescue => e
      #   # If error mentions token limit > 200K, we don't have 1M access
      #   if e.message.include?("200000 maximum")
      #     return false
      #   else
      #     # Other error - assume no access
      #     return false
      #   end
      # end
    end

    # Add extended thinking configuration when proper API format is available
    def add_extended_thinking_config(body, extended_thinking, thinking_budget, model_id)
      return unless extended_thinking && MODEL_SPECS[model_id]&.dig(:supports_extended_thinking)
      
      thinking_tokens = thinking_budget || MODEL_SPECS[model_id][:recommended_thinking_budget]
      
      # TODO: Update with correct API format once available
      # Current attempts failed with "thinking.enabled.budget_tokens: Field required"
      # body[:thinking] = correct_format_here
      
      Rails.logger.debug "[AI] Extended thinking requested but API format unknown - skipping for now" if ENV["VERBOSE_AI_LOGGING"] == "true"
    end
  end
end