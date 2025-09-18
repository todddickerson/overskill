# Enhanced request handler that uses provider selection and feature flags
class Ai::SmartRequestHandler
  def self.handle_request(request_type, content, options = {})
    # Select the best provider for this request
    provider = Ai::ProviderSelectorService.select_provider_for_request(request_type, options)

    # Execute request with selected provider
    execute_with_provider(provider, request_type, content, options)
  end

  def self.handle_tool_calling_request(content, tools, options = {})
    provider = Ai::ProviderSelectorService.select_provider_for_request(:tool_calling_required, options)

    case provider
    when :openrouter_kimi
      handle_openrouter_tool_calling(content, tools, options)
    when :moonshot_direct
      handle_moonshot_tool_calling(content, tools, options)
    else
      raise "Unknown provider for tool calling: #{provider}"
    end
  end

  private

  def self.execute_with_provider(provider, request_type, content, options)
    start_time = Time.current

    begin
      result = case provider
      when :openrouter_kimi
        execute_openrouter_request(request_type, content, options)
      when :moonshot_direct
        execute_moonshot_request(request_type, content, options)
      when :claude_sonnet
        execute_claude_request(request_type, content, options)
      when :gemini_pro
        execute_gemini_request(request_type, content, options)
      else
        raise "Unknown provider: #{provider}"
      end

      # Track successful request
      duration = Time.current - start_time
      track_request_metrics(request_type, provider, duration, true, result[:cost])

      result.merge(provider_used: provider, duration: duration)
    rescue => error
      duration = Time.current - start_time
      track_request_metrics(request_type, provider, duration, false)

      Rails.logger.error "[AI] Request failed with #{provider}: #{error.message}"

      # Try fallback if available
      fallback_result = try_fallback_provider(provider, request_type, content, options)
      return fallback_result if fallback_result

      # No fallback worked
      {
        success: false,
        error: error.message,
        provider_used: provider,
        duration: duration
      }
    end
  end

  def self.handle_openrouter_tool_calling(content, tools, options)
    client = Ai::OpenRouterClient.new

    messages = [{role: "user", content: content}]

    # Format tools for OpenRouter
    formatted_tools = tools.map do |tool|
      {
        type: "function",
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:parameters] || {}
        }
      }
    end

    response = client.chat(
      messages,
      model: :kimi_k2,
      tools: formatted_tools,
      max_tokens: options[:max_tokens] || 4000
    )

    # Check if proper tool calls were returned
    tool_calls = response.dig("choices", 0, "message", "tool_calls")

    if tool_calls&.any?
      # Success! Proper tool calling is working
      {
        success: true,
        tool_calls: tool_calls,
        content: response.dig("choices", 0, "message", "content"),
        provider_used: :openrouter_kimi,
        cost: calculate_openrouter_cost(response)
      }
    else
      # Fall back to JSON-in-text parsing
      content = response.dig("choices", 0, "message", "content")
      parsed_tools = parse_json_from_text(content)

      if parsed_tools
        {
          success: true,
          tool_calls: parsed_tools,
          content: content,
          provider_used: :openrouter_kimi,
          method: :json_parsing_fallback,
          cost: calculate_openrouter_cost(response)
        }
      else
        raise "No tool calls detected in response"
      end
    end
  end

  def self.handle_moonshot_tool_calling(content, tools, options)
    # This would use the direct Moonshot API client
    # Implementation would go here when we build the direct client

    # For now, raise an error to indicate it's not implemented
    raise NotImplementedError, "Direct Moonshot API client not yet implemented"
  end

  def self.parse_json_from_text(content)
    return nil unless content

    # Try to extract JSON from common patterns
    json_patterns = [
      /```json\s*(\{.*?\})\s*```/m,
      /```\s*(\{.*?\})\s*```/m,
      /(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\})/m
    ]

    json_patterns.each do |pattern|
      match = content.match(pattern)
      next unless match

      begin
        parsed = JSON.parse(match[1])

        # Convert to tool_calls format if it looks like a tool call
        if parsed.is_a?(Hash) && parsed["tool_call"]
          return [{
            type: "function",
            function: {
              name: parsed.dig("tool_call", "name"),
              arguments: parsed.dig("tool_call", "arguments")&.to_json || "{}"
            }
          }]
        end
      rescue JSON::ParserError
        next
      end
    end

    nil
  end

  def self.try_fallback_provider(failed_provider, request_type, content, options)
    fallback_chain = {
      openrouter_kimi: :moonshot_direct,
      moonshot_direct: :claude_sonnet,
      gemini_pro: :claude_sonnet
    }

    fallback = fallback_chain[failed_provider]
    return nil unless fallback

    Rails.logger.info "[AI] Trying fallback provider: #{fallback}"

    begin
      execute_with_provider(fallback, request_type, content, options.merge(is_fallback: true))
    rescue => error
      Rails.logger.error "[AI] Fallback provider #{fallback} also failed: #{error.message}"
      nil
    end
  end

  def self.track_request_metrics(request_type, provider, duration, success, cost = nil)
    # Use the existing monitoring service if available
    if defined?(Ai::MonitoringService)
      Ai::MonitoringService.track_request(request_type, provider, duration, success, cost)
    end

    # Also log for immediate visibility
    status = success ? "SUCCESS" : "FAILED"
    cost_info = cost ? " (cost: $#{cost.round(4)})" : ""

    Rails.logger.info "[AI Metrics] #{status} #{request_type} via #{provider} in #{(duration * 1000).round}ms#{cost_info}"
  end

  def self.calculate_openrouter_cost(response)
    # Estimate cost based on token usage if available
    usage = response.dig("usage")
    return 0 unless usage

    input_tokens = usage["prompt_tokens"] || 0
    output_tokens = usage["completion_tokens"] || 0

    # OpenRouter Kimi K2 rates
    input_cost = (input_tokens * 0.000088) / 1000
    output_cost = (output_tokens * 0.000088) / 1000

    input_cost + output_cost
  end

  # Placeholder methods for other providers
  def self.execute_openrouter_request(request_type, content, options)
    client = Ai::OpenRouterClient.new
    response = client.chat([{role: "user", content: content}], **options)

    {
      success: true,
      content: response.dig("choices", 0, "message", "content"),
      cost: calculate_openrouter_cost(response)
    }
  end

  def self.execute_moonshot_request(request_type, content, options)
    raise NotImplementedError, "Direct Moonshot API not yet implemented"
  end

  def self.execute_claude_request(request_type, content, options)
    raise NotImplementedError, "Claude client not yet implemented"
  end

  def self.execute_gemini_request(request_type, content, options)
    raise NotImplementedError, "Gemini client not yet implemented"
  end
end
