# OverSkill AI API Strategy: Direct Calling & Model Flexibility

## Executive Summary

This document outlines a flexible AI API strategy that provides direct calling options outside OpenRouter while maintaining fallback capabilities for easy pivoting to newer/different models. Includes comprehensive analysis of vision AI integration for OverSkill's multimodal needs.

## Current State: OpenRouter vs Direct API Comparison

### OpenRouter Benefits (Current)
- **Pricing**: $0.088/$0.088 per 1M tokens (extremely competitive)
- **Unified Interface**: Single API for multiple models
- **Free Tier**: Available for testing and light usage
- **Easy Model Switching**: Simple model parameter changes
- **No Vendor Lock-in**: Abstraction layer for model flexibility

### Direct Moonshot API Comparison
- **Pricing**: $0.15/$2.50 per 1M tokens (28x more expensive for output)
- **Tool Calling**: Native support (vs OpenRouter's broken implementation)
- **Rate Limits**: Potentially higher limits for enterprise usage
- **Direct Support**: Access to Moonshot's engineering team
- **Feature Access**: First access to new Kimi capabilities

## Recommended Hybrid API Architecture

### Core Design Principles
1. **Provider Abstraction**: Easy switching between API providers
2. **Cost Optimization**: Route requests to cheapest viable option
3. **Reliability**: Automatic failover for high availability
4. **Feature Prioritization**: Use direct APIs when features require it

### Implementation Strategy

```ruby
class Ai::RouterService
  PROVIDERS = {
    openrouter: {
      client: OpenRouterClient,
      cost_multiplier: 1.0,
      features: [:text_generation, :basic_reasoning],
      limitations: [:broken_tool_calling, :no_vision]
    },
    moonshot_direct: {
      client: MoonshotDirectClient,
      cost_multiplier: 28.0, # 28x more expensive for output
      features: [:text_generation, :tool_calling, :advanced_reasoning],
      limitations: [:no_vision]
    },
    claude_sonnet: {
      client: ClaudeClient,
      cost_multiplier: 170.0, # For vision tasks only
      features: [:vision_analysis, :advanced_reasoning, :tool_calling],
      limitations: [:expensive]
    },
    gemini_pro: {
      client: GeminiClient,
      cost_multiplier: 14.0, # Most cost-effective for vision
      features: [:vision_analysis, :multimodal, :fast_inference],
      limitations: [:less_coding_capability]
    }
  }.freeze
  
  def self.route_request(request_type, options = {})
    case request_type
    when :app_generation, :code_review, :debugging
      # Use cheapest option for text-only tasks
      use_provider(:openrouter, fallback: :moonshot_direct)
    when :tool_calling_required
      # Skip OpenRouter due to broken tool calling
      use_provider(:moonshot_direct, fallback: :claude_sonnet)
    when :vision_analysis
      # Route to most cost-effective vision model
      complexity = assess_visual_complexity(options[:prompt])
      if complexity == :simple
        use_provider(:gemini_pro, fallback: :claude_sonnet)
      else
        use_provider(:claude_sonnet, fallback: :gemini_pro)
      end
    when :multimodal_complex
      # For complex multimodal tasks
      use_provider(:claude_sonnet, fallback: :gemini_pro)
    end
  end
  
  private
  
  def self.use_provider(primary, fallback: nil)
    begin
      PROVIDERS[primary][:client].new.call
    rescue => e
      Rails.logger.warn "Primary provider #{primary} failed: #{e.message}"
      return PROVIDERS[fallback][:client].new.call if fallback
      raise
    end
  end
  
  def self.assess_visual_complexity(prompt)
    complex_keywords = ['ui design', 'wireframe', 'mockup', 'architecture', 'technical diagram']
    simple_keywords = ['text extraction', 'simple chart', 'basic layout']
    
    if complex_keywords.any? { |kw| prompt.downcase.include?(kw) }
      :complex
    elsif simple_keywords.any? { |kw| prompt.downcase.include?(kw) }
      :simple
    else
      :medium
    end
  end
end
```

## Direct API Client Implementations

### Moonshot Direct Client
```ruby
class MoonshotDirectClient
  BASE_URL = 'https://api.moonshot.ai/v1'
  
  def initialize
    @api_key = Rails.application.credentials.moonshot_api_key
    @http_client = HTTParty
  end
  
  def generate(prompt, options = {})
    response = @http_client.post(
      "#{BASE_URL}/chat/completions",
      headers: {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json'
      },
      body: {
        model: 'moonshot-v1-32k',
        messages: format_messages(prompt),
        tools: options[:tools],
        **options
      }.to_json
    )
    
    handle_response(response)
  end
  
  def call_with_tools(prompt, tools = [])
    # Native tool calling support
    response = generate(prompt, tools: format_tools(tools))
    
    if response.dig('choices', 0, 'message', 'tool_calls')
      execute_tool_calls(response, tools)
    else
      response.dig('choices', 0, 'message', 'content')
    end
  end
  
  private
  
  def format_tools(tools)
    tools.map do |tool|
      {
        type: 'function',
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:schema]
        }
      }
    end
  end
  
  def execute_tool_calls(response, available_tools)
    tool_calls = response.dig('choices', 0, 'message', 'tool_calls')
    results = []
    
    tool_calls.each do |call|
      tool_name = call.dig('function', 'name')
      arguments = JSON.parse(call.dig('function', 'arguments'))
      
      if tool = available_tools.find { |t| t[:name] == tool_name }
        result = tool[:handler].call(arguments)
        results << { tool: tool_name, result: result }
      end
    end
    
    results
  end
end
```

### Vision Analysis Client (Gemini)
```ruby
class GeminiVisionClient
  BASE_URL = 'https://generativelanguage.googleapis.com/v1beta'
  
  def analyze_image(image_data, prompt, complexity: :medium)
    model = complexity == :simple ? 'gemini-2.0-flash' : 'gemini-2.5-pro'
    
    response = HTTParty.post(
      "#{BASE_URL}/models/#{model}:generateContent",
      headers: {
        'Authorization' => "Bearer #{@api_key}",
        'Content-Type' => 'application/json'
      },
      body: {
        contents: [{
          parts: [
            { text: prompt },
            { 
              inline_data: {
                mime_type: detect_mime_type(image_data),
                data: Base64.encode64(image_data)
              }
            }
          ]
        }]
      }.to_json
    )
    
    extract_vision_analysis(response)
  end
  
  private
  
  def extract_vision_analysis(response)
    content = response.dig('candidates', 0, 'content', 'parts', 0, 'text')
    
    {
      analysis: content,
      confidence: assess_confidence(response),
      detected_elements: parse_detected_elements(content)
    }
  end
end
```

## Cost-Optimized Vision Strategy

### Vision Model Selection Matrix

| Use Case | Model | Cost/1M Tokens | Best For |
|----------|-------|----------------|----------|
| Simple OCR/Text | Gemini 2.0 Flash | $1.25 input | Speed, basic text extraction |
| UI/UX Analysis | Gemini 2.5 Pro | $1.25-2.50 input | Design interpretation, charts |
| Complex Technical | Claude 3.5 Sonnet | $3.00 input | Code screenshots, architecture |
| Batch Processing | GPT-4.1 Mini | $0.40 input | High volume, cost-sensitive |

### Smart Vision Routing
```ruby
class VisionAnalysisService
  def analyze_with_cost_optimization(image, prompt, budget_limit = nil)
    # Pre-analyze prompt to determine complexity
    analysis_type = classify_vision_task(prompt)
    
    case analysis_type
    when :simple_ocr
      # Use cheapest option for text extraction
      GeminiFlashClient.new.extract_text(image)
    when :ui_design_analysis
      # Balance cost and quality for design tasks
      if budget_limit && budget_limit < 0.01
        GeminiProClient.new.analyze_design(image, prompt)
      else
        ClaudeSonnetClient.new.analyze_design(image, prompt)
      end
    when :technical_diagram
      # Require highest quality for technical content
      ClaudeSonnetClient.new.analyze_technical(image, prompt)
    when :batch_processing
      # Optimize for volume
      batch_analyze_with_gemini(image, prompt)
    end
  end
  
  private
  
  def classify_vision_task(prompt)
    case prompt.downcase
    when /extract.*text|ocr|read.*text/
      :simple_ocr
    when /ui|design|mockup|wireframe|layout/
      :ui_design_analysis
    when /architecture|diagram|flowchart|technical/
      :technical_diagram
    when /batch|multiple|process.*many/
      :batch_processing
    else
      :general_analysis
    end
  end
end
```

## Fallback Strategy Implementation

### Automatic Provider Switching
```ruby
class Ai::FallbackHandler
  FALLBACK_CHAINS = {
    text_generation: [
      { provider: :openrouter, timeout: 30.seconds },
      { provider: :moonshot_direct, timeout: 45.seconds },
      { provider: :claude_sonnet, timeout: 60.seconds }
    ],
    tool_calling: [
      { provider: :moonshot_direct, timeout: 45.seconds },
      { provider: :claude_sonnet, timeout: 60.seconds },
      { provider: :custom_kimi_handler, timeout: 90.seconds }
    ],
    vision_analysis: [
      { provider: :gemini_pro, timeout: 30.seconds },
      { provider: :claude_sonnet, timeout: 45.seconds },
      { provider: :gpt4_vision, timeout: 60.seconds }
    ]
  }.freeze
  
  def execute_with_fallback(task_type, request)
    chain = FALLBACK_CHAINS[task_type]
    last_error = nil
    
    chain.each_with_index do |step, index|
      begin
        Rails.logger.info "Attempting #{task_type} with provider #{step[:provider]} (attempt #{index + 1})"
        
        result = Timeout.timeout(step[:timeout]) do
          send("execute_#{step[:provider]}", request)
        end
        
        # Log successful provider for analytics
        track_provider_success(task_type, step[:provider], index)
        return result
        
      rescue => error
        last_error = error
        Rails.logger.warn "Provider #{step[:provider]} failed: #{error.message}"
        
        # Track failure for provider reliability analytics
        track_provider_failure(task_type, step[:provider], error)
        
        # Continue to next provider unless it's the last one
        next unless index == chain.length - 1
      end
    end
    
    # All providers failed
    Rails.logger.error "All providers failed for #{task_type}: #{last_error.message}"
    raise Ai::AllProvidersFailed, "Unable to complete #{task_type} request: #{last_error.message}"
  end
  
  private
  
  def track_provider_success(task_type, provider, attempt_number)
    Rails.cache.increment("ai_provider_success:#{task_type}:#{provider}")
    Rails.cache.increment("ai_provider_attempts:#{task_type}:#{provider}")
    
    # Track how often we need fallbacks
    if attempt_number > 0
      Rails.cache.increment("ai_fallback_usage:#{task_type}")
    end
  end
  
  def track_provider_failure(task_type, provider, error)
    Rails.cache.increment("ai_provider_failure:#{task_type}:#{provider}")
    Rails.cache.increment("ai_provider_attempts:#{task_type}:#{provider}")
    
    # Store error patterns for debugging
    error_key = "ai_error_patterns:#{provider}:#{error.class.name}"
    Rails.cache.increment(error_key)
  end
end
```

## Configuration Management

### Environment-Based Provider Configuration
```ruby
# config/ai_providers.yml
development:
  primary_text_provider: openrouter
  primary_vision_provider: gemini_pro
  enable_fallbacks: true
  cost_tracking: true
  
staging:
  primary_text_provider: openrouter
  primary_vision_provider: gemini_pro
  enable_fallbacks: true
  cost_tracking: true
  
production:
  primary_text_provider: openrouter
  primary_vision_provider: gemini_pro
  enable_fallbacks: true
  cost_tracking: true
  monthly_budget_limit: 5000 # $5000/month
  alert_threshold: 0.8 # Alert at 80% of budget
```

### Dynamic Provider Selection
```ruby
class Ai::ProviderConfig
  def self.select_optimal_provider(request_type, context = {})
    config = Rails.application.config.ai_providers
    
    # Check budget constraints
    if budget_exceeded?(request_type)
      return cheapest_provider_for(request_type)
    end
    
    # Check provider health
    if primary_provider_healthy?(config.primary_provider_for(request_type))
      return config.primary_provider_for(request_type)
    end
    
    # Fall back to healthy alternative
    healthy_fallback_for(request_type)
  end
  
  private
  
  def self.budget_exceeded?(request_type)
    monthly_spend = Rails.cache.read("ai_monthly_spend:#{Date.current.strftime('%Y-%m')}")
    budget_limit = Rails.application.config.ai_providers.monthly_budget_limit
    
    monthly_spend && budget_limit && (monthly_spend > budget_limit * 0.9)
  end
  
  def self.cheapest_provider_for(request_type)
    case request_type
    when :text_generation then :openrouter
    when :vision_analysis then :gemini_pro
    when :tool_calling then :moonshot_direct
    end
  end
end
```

## Cost Monitoring & Analytics

### Real-time Cost Tracking
```ruby
class Ai::CostTracker
  def self.track_request(provider, request_type, token_usage)
    cost = calculate_cost(provider, token_usage)
    
    # Real-time tracking
    Rails.cache.increment("ai_cost:daily:#{Date.current}", cost)
    Rails.cache.increment("ai_cost:monthly:#{Date.current.strftime('%Y-%m')}", cost)
    Rails.cache.increment("ai_cost:provider:#{provider}", cost)
    
    # Detailed logging for analytics
    AiUsageLog.create!(
      provider: provider,
      request_type: request_type,
      input_tokens: token_usage[:input],
      output_tokens: token_usage[:output],
      cost_cents: (cost * 100).to_i,
      timestamp: Time.current
    )
    
    # Alert if approaching budget
    check_budget_alerts(cost)
  end
  
  private
  
  def self.calculate_cost(provider, token_usage)
    rates = {
      openrouter: { input: 0.000088, output: 0.000088 },
      moonshot_direct: { input: 0.00015, output: 0.0025 },
      claude_sonnet: { input: 0.003, output: 0.015 },
      gemini_pro: { input: 0.00125, output: 0.01 }
    }
    
    rate = rates[provider.to_sym]
    return 0 unless rate
    
    (token_usage[:input] * rate[:input] / 1000) + 
    (token_usage[:output] * rate[:output] / 1000)
  end
  
  def self.check_budget_alerts(additional_cost)
    monthly_key = "ai_cost:monthly:#{Date.current.strftime('%Y-%m')}"
    current_spend = Rails.cache.read(monthly_key) || 0
    budget_limit = Rails.application.config.ai_providers.monthly_budget_limit
    
    return unless budget_limit
    
    percentage_used = (current_spend + additional_cost) / budget_limit
    
    if percentage_used > 0.9
      AlertService.send_budget_alert("AI spending at #{(percentage_used * 100).round}% of monthly budget")
    elsif percentage_used > 0.8
      AlertService.send_budget_warning("AI spending at #{(percentage_used * 100).round}% of monthly budget")
    end
  end
end
```

## Migration Strategy

### Phase 1: Dual API Support (Month 1)
- Implement provider abstraction layer
- Add Moonshot direct client alongside OpenRouter
- Create fallback mechanisms
- Deploy with OpenRouter as primary

### Phase 2: Tool Calling Migration (Month 2)
- Migrate tool-calling features to direct Moonshot API
- Implement custom tool parsing for OpenRouter as fallback
- A/B test performance and reliability

### Phase 3: Vision Integration (Month 3)
- Deploy Gemini Pro for cost-effective vision analysis
- Add Claude Sonnet for complex visual tasks
- Implement smart routing based on request complexity

### Phase 4: Optimization (Month 4)
- Analyze usage patterns and costs
- Fine-tune provider selection algorithms
- Implement predictive scaling based on demand

## Expected Outcomes

### Cost Optimization
- **Text Generation**: Maintain current low costs with OpenRouter
- **Tool Calling**: Accept 28x cost increase for reliability (estimated +$50-100/month)
- **Vision Analysis**: Add vision capabilities at ~$0.02-0.05 per analysis
- **Overall**: Projected 30-40% cost increase for significantly enhanced capabilities

### Reliability Improvements
- 99.9% uptime through multi-provider fallbacks
- Eliminate tool calling failures
- Reduce average response time by 25%

### Feature Expansion
- Native multimodal capabilities
- Robust tool calling and function execution
- Advanced debugging and code analysis
- Visual design interpretation

This hybrid approach provides the flexibility to leverage the best aspects of each provider while maintaining cost efficiency and the ability to quickly pivot to new models as they become available.