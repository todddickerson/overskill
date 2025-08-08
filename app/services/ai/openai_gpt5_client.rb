# OpenAI GPT-5 Client Service
# Implements GPT-5 with advanced reasoning levels and cost optimization
require 'net/http'
require 'json'
require 'uri'

module Ai
  class OpenaiGpt5Client
    include Singleton
    
    BASE_URL = 'https://api.openai.com/v1'
    DEFAULT_MODEL = 'gpt-5'  # GPT-5 released August 7, 2025!
    GPT5_VARIANTS = {
      main: 'gpt-5',        # Full GPT-5 model
      mini: 'gpt-5-mini',   # Smaller, faster variant
      nano: 'gpt-5-nano'    # Smallest variant
    }.freeze
    
    # Reasoning effort levels (GPT-5 exclusive feature)
    REASONING_LEVELS = {
      minimal: 'minimal',   # Fastest, no reasoning tokens
      low: 'low',          # Light reasoning for simple tasks
      medium: 'medium',    # Balanced for most tasks
      high: 'high'         # Deep reasoning for complex tasks
    }.freeze
    
    # Token limits for GPT-5
    MAX_INPUT_TOKENS = 272_000   # GPT-5 input context (272K tokens)
    MAX_OUTPUT_TOKENS = 128_000  # GPT-5 output capacity (128K tokens)
    
    # Pricing per million tokens (GPT-5: 40-45% cheaper than Sonnet-4)
    PRICING = {
      input: 1.25,   # $1.25 per million input tokens
      output: 10.00  # $10.00 per million output tokens
    }.freeze
    
    def initialize
      @api_key = ENV['OPENAI_API_KEY']
      @http_client = build_http_client
      @token_usage = { input: 0, output: 0, cost: 0.0 }
      @cache = {}
    end
    
    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: nil, 
             reasoning_level: :medium, tools: nil, use_cache: true, verbosity: :medium, use_chat_api: true)
      
      # Validate API key
      raise "OpenAI API key not configured" unless @api_key
      
      # Always use Chat Completions API (Responses API not available)
      request_body = prepare_chat_request(
        messages: messages,
        model: model,
        temperature: temperature,
        max_tokens: max_tokens,
        reasoning_level: reasoning_level,
        verbosity: verbosity,
        tools: tools
      )
      endpoint = '/v1/chat/completions'
      
      # Check cache if enabled
      cache_key = generate_cache_key(request_body)
      if use_cache && @cache[cache_key]
        Rails.logger.info "[GPT-5] Cache hit for request"
        return @cache[cache_key]
      end
      
      # Make API request
      response = make_request(endpoint, request_body)
      
      # Process response based on API type
      result = use_chat_api ? process_chat_response(response) : process_responses_response(response)
      
      # Cache result
      @cache[cache_key] = result if use_cache
      
      # Track usage
      track_usage(response)
      
      result
    end
    
    # Stream chat for real-time responses
    def chat_stream(messages, model: DEFAULT_MODEL, temperature: 0.7, 
                    reasoning_level: :medium, tools: nil, &block)
      
      request_body = prepare_request(
        messages: messages,
        model: model,
        temperature: temperature,
        reasoning_level: reasoning_level,
        tools: tools,
        stream: true
      )
      
      make_stream_request('/chat/completions', request_body, &block)
    end
    
    # Tool/Function calling support (GPT-5 Responses API format)
    def chat_with_tools(messages, tools, model: DEFAULT_MODEL, 
                        reasoning_level: :medium, temperature: 0.7, verbosity: :medium)
      
      # Convert tools to GPT-5 format
      gpt5_tools = tools.map do |tool|
        if tool[:type] == "function" && tool[:function]
          # Already in correct format
          tool
        else
          # Convert to GPT-5 function format
          {
            type: "function",
            name: tool[:name] || tool.dig(:function, :name),
            description: tool[:description] || tool.dig(:function, :description),
            parameters: tool[:parameters] || tool.dig(:function, :parameters) || {},
            strict: true  # Enable strict mode for reliability
          }
        end
      end
      
      response = chat(
        messages,
        model: model,
        temperature: temperature,
        reasoning_level: reasoning_level,
        verbosity: verbosity,
        tools: gpt5_tools
      )
      
      # Return response with tool calls if present
      response
    end
    
    # Get current token usage and costs
    def usage_stats
      {
        tokens: @token_usage,
        estimated_cost: calculate_cost(@token_usage),
        model: DEFAULT_MODEL,
        savings_vs_sonnet: calculate_savings
      }
    end
    
    # Reset usage tracking
    def reset_usage
      @token_usage = { input: 0, output: 0, cost: 0.0 }
    end
    
    private
    
    def build_http_client
      uri = URI(BASE_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 120
      http.open_timeout = 10
      http
    end
    
    def prepare_chat_request(messages:, model:, temperature:, max_tokens: nil,
                            reasoning_level: :medium, verbosity: :medium, tools: nil, stream: false)
      
      body = {
        model: model,
        messages: messages,
        temperature: temperature,
        stream: stream
      }
      
      # Add GPT-5 specific parameters if they exist
      # Note: reasoning_effort and verbosity are GPT-5 specific features
      if model.include?('gpt-5')
        body[:reasoning_effort] = reasoning_level.to_s
        body[:verbosity] = verbosity.to_s
      end
      
      # Add max tokens if specified
      body[:max_tokens] = max_tokens if max_tokens
      
      # Add tools if provided (convert custom tools format)
      if tools
        body[:tools] = tools.map do |tool|
          if tool[:type] == 'custom'
            # Custom tool format for Chat Completions
            {
              type: 'custom',
              custom: {
                name: tool[:name],
                description: tool[:description]
              }
            }
          else
            # Regular function tool
            tool
          end
        end
      end
      
      body
    end
    
    def prepare_responses_request(input:, model:, temperature:, max_tokens: nil,
                                  reasoning_level: :medium, verbosity: :medium, tools: nil, stream: false)
      
      body = {
        model: model,
        input: input,
        stream: stream
      }
      
      # Add reasoning configuration for GPT-5
      body[:reasoning] = {
        effort: reasoning_level.to_s
      }
      
      # Add text configuration for verbosity
      body[:text] = {
        verbosity: verbosity.to_s
      }
      
      # Add temperature if not default
      body[:temperature] = temperature if temperature != 0.7
      
      # Add max tokens if specified
      body[:max_output_tokens] = max_tokens if max_tokens
      
      # Add tools if provided
      body[:tools] = tools if tools
      
      body
    end
    
    # Convert chat messages to Responses API input format
    def format_messages_for_responses_api(messages)
      # For Responses API, we concatenate messages into a single input
      formatted = []
      
      messages.each do |msg|
        role = msg[:role] || msg['role']
        content = msg[:content] || msg['content']
        
        case role
        when 'system'
          formatted << "System: #{content}"
        when 'user'
          formatted << "User: #{content}"
        when 'assistant'
          formatted << "Assistant: #{content}"
        end
      end
      
      formatted.join("\n\n")
    end
    
    def make_request(endpoint, body)
      request = Net::HTTP::Post.new(endpoint)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request.body = body.to_json
      
      Rails.logger.info "[GPT-5] Request to #{endpoint}"
      Rails.logger.debug "[GPT-5] Request body: #{body.to_json}" if ENV['VERBOSE_AI_LOGGING']
      
      response = @http_client.request(request)
      
      unless response.code == '200'
        error = JSON.parse(response.body) rescue { error: response.body }
        Rails.logger.error "[GPT-5] API Error: #{error}"
        
        # Don't fallback, let the caller handle it (will use Sonnet-4)
        raise "OpenAI API error: #{error}"
      end
      
      JSON.parse(response.body)
    end
    
    def make_stream_request(endpoint, body, &block)
      request = Net::HTTP::Post.new(endpoint)
      request['Authorization'] = "Bearer #{@api_key}"
      request['Content-Type'] = 'application/json'
      request['Accept'] = 'text/event-stream'
      request.body = body.to_json
      
      @http_client.request(request) do |response|
        response.read_body do |chunk|
          chunk.split("\n").each do |line|
            next unless line.start_with?("data: ")
            
            data = line[6..]
            next if data == "[DONE]"
            
            begin
              parsed = JSON.parse(data)
              content = parsed.dig('choices', 0, 'delta', 'content')
              yield content if content && block_given?
            rescue JSON::ParserError
              # Skip invalid JSON
            end
          end
        end
      end
    end
    
    def process_chat_response(response)
      # Standard Chat Completions API response format
      choice = response['choices']&.first || {}
      message = choice['message'] || {}
      
      result = {
        success: true,
        content: message['content'] || '',
        role: message['role'] || 'assistant',
        finish_reason: choice['finish_reason'] || 'stop',
        usage: response['usage']
      }
      
      # Include tool calls if present
      if message['tool_calls']
        result[:tool_calls] = message['tool_calls']
      end
      
      # Include reasoning tokens if present (GPT-5 feature)
      if response.dig('usage', 'reasoning_tokens')
        result[:reasoning_tokens] = response['usage']['reasoning_tokens']
      end
      
      result
    end
    
    def process_responses_response(response)
      # Responses API has different structure than Chat Completions
      output = response['output'] || []
      
      # Find the text content in the output array
      text_content = nil
      tool_calls = []
      
      output.each do |item|
        case item['type']
        when 'text', 'message'
          text_content = item['content'] || item['text']
        when 'function_call', 'custom_tool_call'
          tool_calls << {
            'id' => item['id'],
            'type' => 'function',
            'function' => {
              'name' => item['name'],
              'arguments' => item['arguments'] || item['input']
            }
          }
        end
      end
      
      # Also check for output_text at top level
      text_content ||= response['output_text']
      
      result = {
        content: text_content || '',
        role: 'assistant',
        finish_reason: response['finish_reason'] || 'stop',
        usage: response['usage']
      }
      
      # Include tool calls if present
      result[:tool_calls] = tool_calls if tool_calls.any?
      
      # Include reasoning tokens if present (GPT-5 feature)
      if response.dig('usage', 'reasoning_tokens')
        result[:reasoning_tokens] = response['usage']['reasoning_tokens']
      end
      
      result
    end
    
    def track_usage(response)
      return unless response['usage']
      
      usage = response['usage']
      @token_usage[:input] += usage['prompt_tokens'] || 0
      @token_usage[:output] += usage['completion_tokens'] || 0
      
      # Track reasoning tokens separately (GPT-5)
      if usage['reasoning_tokens']
        @token_usage[:reasoning] = (@token_usage[:reasoning] || 0) + usage['reasoning_tokens']
      end
      
      # Calculate cost
      input_cost = (@token_usage[:input] / 1_000_000.0) * PRICING[:input]
      output_cost = (@token_usage[:output] / 1_000_000.0) * PRICING[:output]
      @token_usage[:cost] = input_cost + output_cost
      
      Rails.logger.info "[GPT-5] Usage - Input: #{usage['prompt_tokens']}, Output: #{usage['completion_tokens']}, Cost: $#{'%.4f' % @token_usage[:cost]}"
    end
    
    def calculate_cost(usage)
      input_cost = (usage[:input] / 1_000_000.0) * PRICING[:input]
      output_cost = (usage[:output] / 1_000_000.0) * PRICING[:output]
      input_cost + output_cost
    end
    
    def calculate_savings
      # Calculate savings vs Sonnet-4 (40-45% cheaper)
      gpt5_cost = @token_usage[:cost]
      sonnet_cost = calculate_sonnet_cost(@token_usage)
      
      {
        gpt5_cost: gpt5_cost,
        sonnet_cost: sonnet_cost,
        savings: sonnet_cost - gpt5_cost,
        savings_percentage: ((sonnet_cost - gpt5_cost) / sonnet_cost * 100).round(2)
      }
    end
    
    def calculate_sonnet_cost(usage)
      # Sonnet-4 pricing: $3/M input, $15/M output
      input_cost = (usage[:input] / 1_000_000.0) * 3.00
      output_cost = (usage[:output] / 1_000_000.0) * 15.00
      input_cost + output_cost
    end
    
    def validate_token_limits(messages, max_tokens)
      input_tokens = count_tokens(messages)
      
      if input_tokens > MAX_INPUT_TOKENS
        raise "Input exceeds GPT-5 limit of #{MAX_INPUT_TOKENS} tokens (got #{input_tokens})"
      end
      
      if max_tokens && max_tokens > MAX_OUTPUT_TOKENS
        raise "Max tokens exceeds GPT-5 limit of #{MAX_OUTPUT_TOKENS} (got #{max_tokens})"
      end
    end
    
    def count_tokens(messages)
      # Rough estimation: 1 token ≈ 4 characters
      total_chars = messages.map do |msg|
        content = msg[:content] || msg['content'] || ''
        content.length
      end.sum
      
      (total_chars / 4.0).ceil
    end
    
    def generate_cache_key(request_body)
      # Generate cache key from request
      Digest::SHA256.hexdigest(request_body.to_json)
    end
  end
end