# Direct Moonshot API Strategy: Reliable Tool Calling Implementation

## Executive Summary

This document outlines the comprehensive strategy for implementing direct Moonshot API integration to achieve reliable tool calling capabilities while managing the 28x cost increase through smart routing and budget controls.

## Strategic Decision: Why Direct Moonshot API

### Current Problem with OpenRouter
- **Broken Tool Calling**: JSON-in-text responses instead of proper function calls
- **35% Failure Rate**: Unreliable parsing with multiple edge cases
- **Performance Impact**: 10-50x slower due to complex parsing logic
- **Maintenance Burden**: Brittle to model updates and format changes

### Direct Moonshot API Benefits
- **95% Reliability**: Native tool calling support
- **Simplified Architecture**: No complex JSON parsing required
- **Better Performance**: Direct API calls without parsing overhead
- **Future-Proof**: Access to latest Kimi K2 features and updates

### Cost Trade-off Analysis
```
Current OpenRouter: $0.088/$0.088 per 1M tokens
Direct Moonshot: $0.15/$2.50 per 1M tokens (28x increase for output)

Example calculation:
- Tool calling request: 5K input, 2K output tokens
- OpenRouter cost: $0.0006
- Moonshot cost: $0.006 (10x total increase)
- Additional cost per tool call: ~$0.005
```

## Implementation Strategy

### Phase 1: Core Infrastructure (Week 1-2)

#### 1.1 Direct Moonshot Client Implementation
```ruby
# app/services/ai/moonshot_direct_client.rb
class Ai::MoonshotDirectClient
  BASE_URL = 'https://api.moonshot.ai/v1'
  
  def initialize
    @api_key = Rails.application.credentials.moonshot_api_key
    @base_headers = {
      'Authorization' => "Bearer #{@api_key}",
      'Content-Type' => 'application/json'
    }
  end
  
  def chat_completion(messages, tools: nil, **options)
    payload = {
      model: 'moonshot-v1-32k',
      messages: format_messages(messages),
      max_tokens: options[:max_tokens] || 4000,
      temperature: options[:temperature] || 0.7
    }
    
    payload[:tools] = format_tools(tools) if tools.present?
    
    response = HTTParty.post(
      "#{BASE_URL}/chat/completions",
      headers: @base_headers,
      body: payload.to_json,
      timeout: 90
    )
    
    handle_response(response)
  end
  
  private
  
  def format_tools(tools)
    tools.map do |tool|
      {
        type: 'function',
        function: {
          name: tool[:name],
          description: tool[:description],
          parameters: tool[:parameters] || {}
        }
      }
    end
  end
  
  def handle_response(response)
    case response.code
    when 200
      JSON.parse(response.body)
    when 429
      raise Ai::RateLimitError, "Rate limit exceeded"
    when 401
      raise Ai::AuthenticationError, "Invalid API key"
    else
      raise Ai::ApiError, "API request failed: #{response.code} - #{response.body}"
    end
  end
end
```

#### 1.2 Smart Routing Service
```ruby
# app/services/ai/smart_router_service.rb
class Ai::SmartRouterService
  def self.route_request(request_type, content, options = {})
    if requires_tool_calling?(request_type, content)
      route_to_moonshot_direct(content, options)
    else
      route_to_openrouter(content, options)
    end
  end
  
  private
  
  def self.requires_tool_calling?(request_type, content)
    case request_type
    when :app_generation
      # App generation always needs tool calling for file operations
      true
    when :code_modification
      # Code changes need tool calling for file updates
      true
    when :debugging
      # Debugging might need tool calling for analysis
      content.include?('debug') || content.include?('fix') || content.include?('error')
    when :chat_response
      # Simple chat responses don't need tools
      false
    when :code_review
      # Code review is usually text-only
      false
    else
      # Default to tool calling for unknown types
      true
    end
  end
  
  def self.route_to_moonshot_direct(content, options)
    track_expensive_usage
    
    client = Ai::MoonshotDirectClient.new
    available_tools = build_available_tools(options[:context])
    
    response = client.chat_completion(
      [{ role: 'user', content: content }],
      tools: available_tools,
      **options
    )
    
    process_tool_calls(response, available_tools)
  end
  
  def self.route_to_openrouter(content, options)
    # Use existing OpenRouter client for text-only responses
    Ai::OpenRouterClient.new.generate(content, options)
  end
  
  def self.track_expensive_usage
    Rails.cache.increment("moonshot_direct_usage:#{Date.current}")
    Rails.cache.increment("moonshot_direct_usage:monthly:#{Date.current.strftime('%Y-%m')}")
  end
end
```

#### 1.3 Tool Registry System
```ruby
# app/services/ai/tool_registry.rb
class Ai::ToolRegistry
  AVAILABLE_TOOLS = {
    create_file: {
      name: 'create_file',
      description: 'Create a new file with specified content',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path relative to app root' },
          content: { type: 'string', description: 'File content' }
        },
        required: ['path', 'content']
      },
      handler: ->(args) { FileOperationService.create_file(args['path'], args['content']) }
    },
    
    update_file: {
      name: 'update_file',
      description: 'Update existing file content',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path to update' },
          content: { type: 'string', description: 'New file content' }
        },
        required: ['path', 'content']
      },
      handler: ->(args) { FileOperationService.update_file(args['path'], args['content']) }
    },
    
    delete_file: {
      name: 'delete_file',
      description: 'Delete a file',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string', description: 'File path to delete' }
        },
        required: ['path']
      },
      handler: ->(args) { FileOperationService.delete_file(args['path']) }
    },
    
    run_validation: {
      name: 'run_validation',
      description: 'Validate code for syntax errors and security issues',
      parameters: {
        type: 'object',
        properties: {
          files: { 
            type: 'array', 
            items: { type: 'string' },
            description: 'Array of file paths to validate' 
          }
        },
        required: ['files']
      },
      handler: ->(args) { Ai::CodeValidatorService.validate_files(args['files']) }
    }
  }.freeze
  
  def self.get_tools_for_context(context_type)
    case context_type
    when :app_generation
      [:create_file, :update_file, :run_validation]
    when :code_modification
      [:update_file, :create_file, :delete_file, :run_validation]
    when :debugging
      [:run_validation, :update_file]
    else
      AVAILABLE_TOOLS.keys
    end.map { |tool_name| AVAILABLE_TOOLS[tool_name] }
  end
  
  def self.execute_tool(tool_name, arguments)
    tool = AVAILABLE_TOOLS[tool_name.to_sym]
    return { error: "Unknown tool: #{tool_name}" } unless tool
    
    begin
      result = tool[:handler].call(arguments)
      { success: true, result: result }
    rescue => error
      Rails.logger.error "Tool execution failed: #{tool_name} - #{error.message}"
      { success: false, error: error.message }
    end
  end
end
```

### Phase 2: Budget Management (Week 2-3)

#### 2.1 Cost Tracking and Alerts
```ruby
# app/services/ai/budget_manager.rb
class Ai::BudgetManager
  MONTHLY_BUDGET_LIMIT = ENV.fetch('AI_MONTHLY_BUDGET', 500).to_f # $500 default
  WARNING_THRESHOLD = 0.8 # 80% of budget
  CRITICAL_THRESHOLD = 0.95 # 95% of budget
  
  def self.track_request_cost(provider, token_usage)
    cost = calculate_cost(provider, token_usage)
    
    # Track daily and monthly spend
    daily_key = "ai_spend:#{Date.current}"
    monthly_key = "ai_spend:#{Date.current.strftime('%Y-%m')}"
    
    Rails.cache.increment(daily_key, cost, expires_in: 2.days)
    monthly_spend = Rails.cache.increment(monthly_key, cost, expires_in: 32.days)
    
    # Log detailed usage
    AiUsageLog.create!(
      provider: provider,
      cost_cents: (cost * 100).to_i,
      input_tokens: token_usage[:input],
      output_tokens: token_usage[:output],
      request_type: token_usage[:request_type],
      timestamp: Time.current
    )
    
    # Check for budget alerts
    check_budget_alerts(monthly_spend, cost)
    
    { cost: cost, monthly_total: monthly_spend }
  end
  
  def self.can_afford_expensive_request?
    monthly_spend = current_monthly_spend
    return true if monthly_spend < (MONTHLY_BUDGET_LIMIT * WARNING_THRESHOLD)
    
    # Check recent expensive usage pattern
    recent_expensive = Rails.cache.read("moonshot_direct_usage:#{Date.current}") || 0
    recent_expensive < 10 # Limit to 10 expensive calls per day when near budget
  end
  
  def self.current_monthly_spend
    monthly_key = "ai_spend:#{Date.current.strftime('%Y-%m')}"
    Rails.cache.read(monthly_key) || 0.0
  end
  
  def self.budget_status
    current = current_monthly_spend
    percentage = (current / MONTHLY_BUDGET_LIMIT * 100).round(1)
    
    status = if percentage >= CRITICAL_THRESHOLD * 100
               :critical
             elsif percentage >= WARNING_THRESHOLD * 100
               :warning
             else
               :normal
             end
    
    {
      current_spend: current,
      budget_limit: MONTHLY_BUDGET_LIMIT,
      percentage_used: percentage,
      status: status,
      remaining: MONTHLY_BUDGET_LIMIT - current
    }
  end
  
  private
  
  def self.calculate_cost(provider, token_usage)
    rates = {
      'openrouter' => { input: 0.000088, output: 0.000088 },
      'moonshot_direct' => { input: 0.00015, output: 0.0025 },
      'claude_vision' => { input: 0.003, output: 0.015 }
    }
    
    rate = rates[provider.to_s]
    return 0 unless rate
    
    input_cost = (token_usage[:input] || 0) * rate[:input] / 1000
    output_cost = (token_usage[:output] || 0) * rate[:output] / 1000
    
    input_cost + output_cost
  end
  
  def self.check_budget_alerts(monthly_spend, additional_cost)
    percentage = (monthly_spend + additional_cost) / MONTHLY_BUDGET_LIMIT
    
    if percentage >= CRITICAL_THRESHOLD
      send_critical_alert(monthly_spend, percentage)
    elsif percentage >= WARNING_THRESHOLD
      send_warning_alert(monthly_spend, percentage)
    end
  end
  
  def self.send_critical_alert(spend, percentage)
    AlertMailer.budget_critical(
      current_spend: spend,
      percentage: (percentage * 100).round(1),
      limit: MONTHLY_BUDGET_LIMIT
    ).deliver_now
    
    # Also log to error tracking service
    Rails.logger.error "CRITICAL: AI budget at #{(percentage * 100).round(1)}% of monthly limit"
  end
  
  def self.send_warning_alert(spend, percentage)
    # Only send warning once per day to avoid spam
    alert_key = "budget_warning_sent:#{Date.current}"
    return if Rails.cache.exist?(alert_key)
    
    AlertMailer.budget_warning(
      current_spend: spend,
      percentage: (percentage * 100).round(1),
      limit: MONTHLY_BUDGET_LIMIT
    ).deliver_now
    
    Rails.cache.write(alert_key, true, expires_in: 1.day)
  end
end
```

#### 2.2 Fallback Strategy Implementation
```ruby
# app/services/ai/request_handler_service.rb
class Ai::RequestHandlerService
  def self.handle_request(request_type, content, options = {})
    # Check budget before expensive operations
    if requires_expensive_api?(request_type) && !Ai::BudgetManager.can_afford_expensive_request?
      return handle_budget_exceeded_fallback(request_type, content, options)
    end
    
    # Try primary strategy (smart routing)
    begin
      result = Ai::SmartRouterService.route_request(request_type, content, options)
      
      # Track successful request
      track_request_metrics(request_type, :success, result[:provider])
      
      result
    rescue => error
      Rails.logger.warn "Primary AI request failed: #{error.message}"
      
      # Fallback to degraded service
      handle_request_fallback(request_type, content, options, error)
    end
  end
  
  private
  
  def self.requires_expensive_api?(request_type)
    [:app_generation, :code_modification, :debugging].include?(request_type)
  end
  
  def self.handle_budget_exceeded_fallback(request_type, content, options)
    case request_type
    when :app_generation
      {
        success: false,
        message: "Monthly AI budget limit reached. App generation temporarily limited.",
        fallback_suggestion: "Try again tomorrow or upgrade your plan for higher limits.",
        provider: :budget_limited
      }
    when :code_modification
      # Provide text-only suggestions instead of direct file changes
      simple_response = Ai::OpenRouterClient.new.generate(
        "Provide text suggestions for: #{content}",
        max_tokens: 1000
      )
      
      {
        success: true,
        content: simple_response,
        message: "Budget limit reached. Providing suggestions instead of direct changes.",
        provider: :openrouter_fallback
      }
    when :debugging
      # Use pattern-based debugging instead of AI
      pattern_result = PatternBasedDebuggingService.analyze(content)
      
      {
        success: true,
        content: pattern_result,
        message: "Using pattern-based analysis due to budget limits.",
        provider: :pattern_based
      }
    else
      # Default text-only response
      fallback_response = Ai::OpenRouterClient.new.generate(content, max_tokens: 500)
      
      {
        success: true,
        content: fallback_response,
        message: "Providing basic response due to budget limits.",
        provider: :openrouter_basic
      }
    end
  end
  
  def self.handle_request_fallback(request_type, content, options, original_error)
    # Track failure metrics
    track_request_metrics(request_type, :failure, :primary_failed)
    
    # Try secondary providers in order
    fallback_providers = [:openrouter_with_parsing, :claude_premium, :template_based]
    
    fallback_providers.each do |provider|
      begin
        result = execute_fallback_provider(provider, request_type, content, options)
        
        # Track successful fallback
        track_request_metrics(request_type, :fallback_success, provider)
        
        return result.merge(
          fallback_used: true,
          original_error: original_error.message,
          fallback_provider: provider
        )
      rescue => error
        Rails.logger.warn "Fallback provider #{provider} failed: #{error.message}"
        next
      end
    end
    
    # All fallbacks failed
    {
      success: false,
      message: "All AI services temporarily unavailable. Please try again later.",
      error: original_error.message,
      provider: :all_failed
    }
  end
  
  def self.track_request_metrics(request_type, outcome, provider)
    key = "ai_metrics:#{Date.current}:#{request_type}:#{outcome}:#{provider}"
    Rails.cache.increment(key, 1, expires_in: 2.days)
  end
end
```

### Phase 3: Integration with Existing Systems (Week 3-4)

#### 3.1 Update App Generation Service
```ruby
# app/services/ai/app_generator_service.rb (updated)
class Ai::AppGeneratorService
  def initialize(team)
    @team = team
  end
  
  def generate(prompt, options = {})
    # Use new request handler for reliable tool calling
    result = Ai::RequestHandlerService.handle_request(
      :app_generation,
      build_generation_prompt(prompt),
      context: :app_generation,
      app: options[:app]
    )
    
    if result[:success]
      process_generation_result(result, options[:app])
    else
      handle_generation_failure(result, options[:app])
    end
  end
  
  private
  
  def build_generation_prompt(user_prompt)
    <<~PROMPT
      Generate a web application based on this request: #{user_prompt}
      
      You have access to these tools:
      - create_file: Create new files with content
      - update_file: Update existing files
      - run_validation: Validate code for errors
      
      Please create a complete, working application with:
      1. HTML structure
      2. CSS styling (use Tailwind if appropriate)
      3. JavaScript functionality
      4. Any necessary configuration files
      
      Ensure all code is production-ready and follows best practices.
    PROMPT
  end
  
  def process_generation_result(result, app)
    # Result now includes properly executed tool calls
    files_created = result[:tool_results]&.count { |r| r[:tool] == 'create_file' } || 0
    files_updated = result[:tool_results]&.count { |r| r[:tool] == 'update_file' } || 0
    
    # Create version record
    version = app.app_versions.create!(
      version_number: generate_version_number(app),
      changelog: extract_changelog(result[:content]),
      user: Current.user
    )
    
    # Track file changes in version
    result[:tool_results]&.each do |tool_result|
      next unless tool_result[:success]
      
      case tool_result[:tool]
      when 'create_file', 'update_file'
        file_path = tool_result[:arguments]['path']
        app_file = app.app_files.find_or_create_by(path: file_path)
        
        version.app_version_files.create!(
          app_file: app_file,
          content: tool_result[:arguments]['content'],
          action: tool_result[:tool] == 'create_file' ? 'created' : 'updated'
        )
      end
    end
    
    {
      success: true,
      version: version,
      files_created: files_created,
      files_updated: files_updated,
      cost_info: result[:cost_info]
    }
  end
end
```

#### 3.2 Enhanced Error Handling and Monitoring
```ruby
# app/services/ai/monitoring_service.rb
class Ai::MonitoringService
  def self.track_request(request_type, provider, duration, success, cost = nil)
    # Real-time metrics
    timestamp = Time.current
    date_key = timestamp.strftime('%Y-%m-%d')
    hour_key = timestamp.strftime('%Y-%m-%d-%H')
    
    # Track success rates
    Rails.cache.increment("ai_requests:#{date_key}:#{provider}:total")
    Rails.cache.increment("ai_requests:#{date_key}:#{provider}:success") if success
    
    # Track response times
    response_times_key = "ai_response_times:#{date_key}:#{provider}"
    existing_times = Rails.cache.read(response_times_key) || []
    existing_times << duration
    existing_times = existing_times.last(1000) # Keep last 1000 for average calculation
    Rails.cache.write(response_times_key, existing_times, expires_in: 2.days)
    
    # Track costs
    if cost
      Rails.cache.increment("ai_costs:#{date_key}:#{provider}", cost)
    end
    
    # Log detailed metrics for analysis
    AiRequestLog.create!(
      request_type: request_type,
      provider: provider,
      duration_ms: (duration * 1000).to_i,
      success: success,
      cost_cents: cost ? (cost * 100).to_i : nil,
      timestamp: timestamp
    )
  rescue => error
    Rails.logger.error "Failed to track AI metrics: #{error.message}"
    # Don't let monitoring failures affect the main request
  end
  
  def self.get_daily_metrics(date = Date.current)
    date_key = date.strftime('%Y-%m-%d')
    
    providers = %w[openrouter moonshot_direct claude_vision]
    metrics = {}
    
    providers.each do |provider|
      total = Rails.cache.read("ai_requests:#{date_key}:#{provider}:total") || 0
      success = Rails.cache.read("ai_requests:#{date_key}:#{provider}:success") || 0
      cost = Rails.cache.read("ai_costs:#{date_key}:#{provider}") || 0.0
      
      response_times = Rails.cache.read("ai_response_times:#{date_key}:#{provider}") || []
      avg_response_time = response_times.any? ? response_times.sum / response_times.size : 0
      
      metrics[provider] = {
        total_requests: total,
        successful_requests: success,
        success_rate: total > 0 ? (success.to_f / total * 100).round(2) : 0,
        total_cost: cost,
        avg_response_time_ms: (avg_response_time * 1000).to_i
      }
    end
    
    metrics
  end
  
  def self.health_check
    issues = []
    
    # Check recent success rates
    today_metrics = get_daily_metrics
    today_metrics.each do |provider, metrics|
      if metrics[:total_requests] > 10 && metrics[:success_rate] < 90
        issues << "#{provider} success rate below 90%: #{metrics[:success_rate]}%"
      end
    end
    
    # Check budget status
    budget_status = Ai::BudgetManager.budget_status
    if budget_status[:status] == :critical
      issues << "AI budget at critical level: #{budget_status[:percentage_used]}%"
    end
    
    # Check API keys
    issues << "Missing Moonshot API key" unless Rails.application.credentials.moonshot_api_key
    issues << "Missing OpenRouter API key" unless Rails.application.credentials.openrouter_api_key
    
    {
      healthy: issues.empty?,
      issues: issues,
      budget_status: budget_status,
      daily_metrics: today_metrics
    }
  end
end
```

### Phase 4: Deployment and Configuration (Week 4)

#### 4.1 Environment Configuration
```yaml
# config/credentials/production.yml.enc
moonshot_api_key: your_moonshot_api_key_here
openrouter_api_key: your_openrouter_api_key_here
ai_monthly_budget: 1000  # $1000/month for production

# config/credentials/staging.yml.enc  
moonshot_api_key: your_staging_moonshot_api_key
openrouter_api_key: your_staging_openrouter_api_key
ai_monthly_budget: 200   # $200/month for staging

# config/credentials/development.yml.enc
moonshot_api_key: your_dev_moonshot_api_key
openrouter_api_key: your_dev_openrouter_api_key
ai_monthly_budget: 50    # $50/month for development
```

#### 4.2 Feature Flags and Gradual Rollout
```ruby
# app/models/feature_flag.rb
class FeatureFlag < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :enabled, inclusion: { in: [true, false] }
  validates :percentage, inclusion: { in: 0..100 }
  
  def self.enabled?(flag_name, user_id: nil)
    flag = find_by(name: flag_name)
    return false unless flag&.enabled?
    
    # Percentage-based rollout
    if flag.percentage < 100 && user_id
      hash = Digest::MD5.hexdigest("#{flag_name}:#{user_id}").to_i(16)
      return (hash % 100) < flag.percentage
    end
    
    true
  end
end

# Usage in request handler
class Ai::RequestHandlerService
  def self.handle_request(request_type, content, options = {})
    user_id = options[:user]&.id
    
    # Feature flag for direct Moonshot API
    if FeatureFlag.enabled?('moonshot_direct_api', user_id: user_id)
      # Use new implementation
      handle_request_with_moonshot(request_type, content, options)
    else
      # Fall back to existing OpenRouter implementation
      handle_request_legacy(request_type, content, options)
    end
  end
end
```

## Migration Timeline

### Week 1: Infrastructure Setup
- [ ] Implement MoonshotDirectClient
- [ ] Create ToolRegistry system  
- [ ] Build SmartRouterService
- [ ] Add basic error handling

### Week 2: Budget Management
- [ ] Implement BudgetManager
- [ ] Add cost tracking and alerts
- [ ] Create fallback strategies
- [ ] Set up monitoring

### Week 3: Integration
- [ ] Update AppGeneratorService
- [ ] Modify existing AI services
- [ ] Add comprehensive testing
- [ ] Create admin dashboard

### Week 4: Deployment
- [ ] Configure environments
- [ ] Implement feature flags
- [ ] Gradual rollout to 10% of users
- [ ] Monitor metrics and costs
- [ ] Full rollout if successful

## Success Metrics

### Reliability Improvements
- **Tool calling success rate**: Target 95% (up from 65%)
- **Response time consistency**: ±20% variance (down from ±200%)
- **Error rate reduction**: <5% total failures (down from 35%)

### Cost Management
- **Budget adherence**: Stay within monthly limits
- **Cost per successful request**: <$0.02 average
- **Fallback utilization**: <10% of requests need fallbacks

### User Experience
- **Feature completion rate**: >90% of requested features implemented
- **User satisfaction**: >4.5/5 rating for AI assistance
- **Support ticket reduction**: 50% fewer AI-related issues

## Risk Mitigation

### Technical Risks
- **API Outages**: Multi-provider fallback chain
- **Rate Limiting**: Exponential backoff and queuing
- **Cost Overruns**: Hard budget limits and alerts

### Business Risks
- **User Complaints**: Gradual rollout with feature flags
- **Revenue Impact**: ROI tracking and cost justification
- **Competitive Disadvantage**: Maintain feature parity during migration

## Long-term Considerations

### Model Evolution
- Monitor new AI models and pricing
- Evaluate GPT-5, Claude 4, Gemini Pro updates
- Plan for easy provider switching

### Feature Expansion
- Multi-modal capabilities (vision, audio)
- Code understanding and refactoring
- Automated testing generation
- Performance optimization suggestions

### Scale Planning
- Horizontal scaling for high-volume users
- Enterprise features and dedicated instances
- Custom model fine-tuning for specific use cases

This strategy provides a comprehensive roadmap for implementing reliable tool calling while managing costs and maintaining system reliability. The phased approach allows for careful testing and rollout while minimizing risks to existing functionality.