# Model Client Factory - Clean abstraction for AI model selection
# Supports GPT-5 and Claude Sonnet 4 with consistent interface
module Ai
  class ModelClientFactory
    # Supported models for A/B testing
    SUPPORTED_MODELS = {
      "gpt-5" => {
        name: "GPT-5",
        description: "OpenAI GPT-5 - Fast, reliable, cost-effective",
        provider: "openai",
        supports_streaming: true,
        supports_tools: true,
        default_temperature: 1.0,  # GPT-5 only supports default
        max_tokens: 128_000,
        pricing: {input: 1.25, output: 10.00}  # per million tokens
      },
      "claude-sonnet-4" => {
        name: "Claude Sonnet 4",
        description: "Anthropic Claude 3.5 Sonnet - Advanced reasoning, creative",
        provider: "anthropic",
        supports_streaming: true,
        supports_tools: true,
        default_temperature: 0.7,
        max_tokens: 200_000,
        pricing: {input: 3.00, output: 15.00}  # per million tokens
      }
    }.freeze

    class << self
      def create_client(model_preference = "gpt-5")
        Rails.logger.info "[ModelClientFactory] Creating client for model: #{model_preference}"

        case model_preference
        when "gpt-5"
          create_gpt5_client
        when "claude-sonnet-4"
          create_claude_client
        else
          Rails.logger.warn "[ModelClientFactory] Unknown model '#{model_preference}', defaulting to GPT-5"
          create_gpt5_client
        end
      end

      def create_gpt5_client
        # Try direct OpenAI first
        openai_key = ENV["OPENAI_API_KEY"]

        if openai_key.present? && openai_key.length > 20 && !openai_key.include?("dummy")
          Rails.logger.info "[ModelClientFactory] ✅ Using OpenAI direct API with GPT-5"
          {
            client: OpenaiGpt5Client.instance,
            model: "gpt-5",
            provider: "openai_direct",
            supports_streaming: true
          }
        else
          Rails.logger.info "[ModelClientFactory] Using OpenRouter for GPT-5"
          {
            client: OpenRouterClient.new,
            model: :gpt5,  # OpenRouter uses symbol
            provider: "openrouter",
            supports_streaming: true
          }
        end
      rescue => e
        Rails.logger.error "[ModelClientFactory] GPT-5 client creation failed: #{e.message}"
        # Fallback to OpenRouter
        {
          client: OpenRouterClient.new,
          model: :gpt5,
          provider: "openrouter",
          supports_streaming: true
        }
      end

      def create_claude_client
        # Check for Anthropic API key
        anthropic_key = ENV["ANTHROPIC_API_KEY"]

        if anthropic_key.present? && anthropic_key.length > 20
          Rails.logger.info "[ModelClientFactory] ✅ Using Anthropic direct API with Claude Sonnet 4"
          {
            client: AnthropicClient.instance,
            model: "claude-3-5-sonnet-20241022",  # Latest Sonnet 4
            provider: "anthropic_direct",
            supports_streaming: true
          }
        else
          Rails.logger.info "[ModelClientFactory] Using OpenRouter for Claude Sonnet 4"
          {
            client: OpenRouterClient.new,
            model: :sonnet,  # OpenRouter symbol for Claude
            provider: "openrouter",
            supports_streaming: true
          }
        end
      rescue => e
        Rails.logger.error "[ModelClientFactory] Claude client creation failed: #{e.message}"
        # Fallback to OpenRouter
        {
          client: OpenRouterClient.new,
          model: :sonnet,
          provider: "openrouter",
          supports_streaming: true
        }
      end

      def model_info(model_key)
        SUPPORTED_MODELS[model_key] || SUPPORTED_MODELS["gpt-5"]
      end

      def available_models
        SUPPORTED_MODELS.map do |key, info|
          {
            value: key,
            label: info[:name],
            description: info[:description],
            pricing: info[:pricing]
          }
        end
      end

      # Unified interface for making chat requests regardless of model
      def chat_with_model(model_preference, messages, options = {})
        client_info = create_client(model_preference)
        client = client_info[:client]
        model = client_info[:model]
        provider = client_info[:provider]

        Rails.logger.info "[ModelClientFactory] Calling #{provider} with model #{model}"

        # Adjust parameters based on model capabilities
        adjusted_options = adjust_options_for_model(model_preference, options)

        # Make the actual call with appropriate method
        if provider.include?("direct")
          # Direct API calls
        else
          # OpenRouter calls
        end
        response = client.chat(
          messages,
          model: model,
          **adjusted_options
        )

        # Normalize response format
        normalize_response(response, provider)
      end

      # Unified interface for streaming with tools
      def stream_with_tools(model_preference, messages, tools, options = {})
        client_info = create_client(model_preference)
        client = client_info[:client]
        model = client_info[:model]

        # Adjust tools format if needed for different models
        adjusted_tools = adjust_tools_for_model(model_preference, tools)

        # Stream with tools
        if client.respond_to?(:chat_with_tools)
          client.chat_with_tools(messages, adjusted_tools, model: model, **options)
        else
          # Fallback for clients without tool support
          client.chat(messages, model: model, tools: adjusted_tools, **options)
        end
      end

      private

      def adjust_options_for_model(model_preference, options)
        SUPPORTED_MODELS[model_preference]
        adjusted = options.dup

        # GPT-5 specific adjustments
        if model_preference == "gpt-5"
          # GPT-5 only supports default temperature
          adjusted.delete(:temperature)
          adjusted[:reasoning_level] = options[:reasoning_level] || :medium
        end

        # Claude specific adjustments
        if model_preference == "claude-sonnet-4"
          adjusted[:temperature] = options[:temperature] || 0.7
          adjusted[:max_tokens] = [options[:max_tokens] || 8192, 200_000].min
        end

        adjusted
      end

      def adjust_tools_for_model(model_preference, tools)
        # Both models support similar tool formats, but might need slight adjustments
        case model_preference
        when "claude-sonnet-4"
          # Claude prefers slightly different tool format
          tools.map do |tool|
            if tool[:type] == "function" && tool[:function]
              tool  # Already in correct format
            else
              # Convert to expected format
              {
                type: "function",
                function: {
                  name: tool[:name],
                  description: tool[:description],
                  parameters: tool[:parameters]
                }
              }
            end
          end
        else
          tools  # GPT-5 format is standard
        end
      end

      def normalize_response(response, provider)
        # Ensure consistent response format across providers
        if response.is_a?(Hash)
          {
            success: response[:success] != false,
            content: response[:content] || response["content"] || "",
            role: response[:role] || "assistant",
            tool_calls: response[:tool_calls] || response["tool_calls"],
            usage: response[:usage] || response["usage"],
            provider: provider
          }
        else
          {
            success: false,
            content: "",
            error: "Invalid response format from #{provider}",
            provider: provider
          }
        end
      end
    end
  end
end
