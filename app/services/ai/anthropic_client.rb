require 'net/http'

module Ai
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
        supports_extended_thinking: true,
        supports_interleaved_thinking: true,
        recommended_thinking_budget: 16_000  # 16k+ tokens for complex tasks
      },
      "claude-opus-4-1-20250805" => { 
        context: 200_000, 
        max_output: 4_096,
        cost_per_1k_input: 15.00,
        cost_per_1k_output: 75.00,
        cache_write_multiplier: 1.25,
        cache_read_multiplier: 0.10
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
      
      # Build base headers
      @base_headers = {
        "x-api-key" => @api_key,
        "content-type" => "application/json",
        "anthropic-version" => "2023-06-01",
        "anthropic-beta" => "prompt-caching-2024-07-31,interleaved-thinking-2025-05-14,context-1m-2025-08-07"
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
        headers: headers,
        timeout: 300  # 5 minute timeout for complex generations
      }
    end

    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_cache: true, cache_breakpoints: [], helicone_session: nil, extended_thinking: false, thinking_budget: nil)
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

      # Separate system message from other messages for Anthropic API
      system_message = nil
      api_messages = []
      
      messages.each do |msg|
        if msg[:role] == "system"
          # Support both string and array format for system prompts (for caching)
          system_message = msg[:content]
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

      Rails.logger.info "[AI] Calling Anthropic API with model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      # Prepare request options with optional Helicone session tracking
      request_options = build_request_options.merge(body: body.to_json)
      helicone_key = ENV['HELICONE_API_KEY']
      if helicone_key.present? && helicone_session.present?
        request_options[:headers] = request_options[:headers].merge({
          "Helicone-Session-Id" => helicone_session,
          "Helicone-Session-Name" => "OverSkill-App-Generation"
        })
      end

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("anthropic_chat_#{model_id}") do |attempt|
        response = self.class.post("/v1/messages", request_options)
        
        unless response.success?
          error_message = response.parsed_response["error"]&.dig("message") || "HTTP #{response.code}"
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
      usage = result.dig("usage")

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
        content: result.dig("content", 0, "text"),
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

    def chat_with_tools(messages, tools, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, use_cache: true, cache_breakpoints: [], helicone_session: nil, extended_thinking: true, thinking_budget: nil)
      model_id = MODELS[model] || model
      
      # Calculate optimal max_tokens if not provided
      if max_tokens.nil?
        max_tokens = calculate_optimal_max_tokens(messages, model_id)
      end

      # Apply cache breakpoints to messages if caching enabled
      if use_cache && cache_breakpoints.any?
        messages = apply_cache_breakpoints(messages, cache_breakpoints)
      end

      # Separate system message from other messages for Anthropic API
      system_message = nil
      api_messages = []
      
      messages.each do |msg|
        if msg[:role] == "system"
          # Support both string and array format for system prompts (for caching)
          system_message = msg[:content]
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
        
        Rails.logger.info "[AI] Extended thinking enabled with budget: #{thinking_tokens} tokens" if ENV["VERBOSE_AI_LOGGING"] == "true"
      end

      Rails.logger.info "[AI] Calling Anthropic API with tools, model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      # Prepare request options with optional Helicone session tracking
      request_options = build_request_options.merge(body: body.to_json)
      helicone_key = ENV['HELICONE_API_KEY']
      if helicone_key.present? && helicone_session.present?
        request_options[:headers] = request_options[:headers].merge({
          "Helicone-Session-Id" => helicone_session,
          "Helicone-Session-Name" => "OverSkill-Tool-Calling"
        })
      end

      # Use enhanced error handling with retry logic
      retry_result = @error_handler.execute_with_retry("anthropic_tools_#{model_id}") do |attempt|
        response = self.class.post("/v1/messages", request_options)
        
        unless response.success?
          error_message = response.parsed_response["error"]&.dig("message") || "HTTP #{response.code}"
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
      usage = result.dig("usage")
      
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

      # Extract tool calls and thinking blocks from Anthropic's response format
      tool_calls = []
      thinking_blocks = []
      content_blocks = result.dig("content") || []
      
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
            "content" => block["content"],
            "signature" => block["signature"]  # Preserve cryptographic signature
          }
        end
      end

      # Extract text content
      text_content = content_blocks
        .select { |block| block["type"] == "text" }
        .map { |block| block["text"] }
        .join("\n")

      {
        success: true,
        content: text_content,
        tool_calls: tool_calls,
        thinking_blocks: thinking_blocks,
        stop_reason: result.dig("stop_reason"),  # CRITICAL: Add stop_reason for proper tool handling
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