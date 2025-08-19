# frozen_string_literal: true

require 'faraday'
require 'json'

# Service for interacting with Perplexity AI API
# Provides AI-powered web search and content synthesis capabilities
class PerplexityContentService
  include ActiveSupport::Benchmarkable
  
  # Perplexity API models with their characteristics
  MODELS = {
    sonar: 'sonar',                         # Lightweight, fast responses with citations ($3/$15 per M tokens)
    sonar_pro: 'sonar-pro',                  # Enhanced search capabilities and richer context ($3/$15 per M tokens)
    sonar_reasoning: 'sonar-reasoning',      # Chain-of-thought reasoning with live search
    sonar_reasoning_pro: 'sonar-reasoning-pro', # Advanced reasoning powered by DeepSeek-R1
    sonar_deep_research: 'sonar-deep-research'  # Multi-query research for comprehensive reports
  }.freeze
  
  DEFAULT_MODEL = MODELS[:sonar] # Use lightweight model by default for cost control
  MAX_TOKENS = 2000
  CACHE_TTL = 1.hour
  
  def initialize
    @api_key = ENV['PERPLEXITY_API_KEY'] || Rails.application.credentials.dig(:perplexity, :api_key)
    @logger = Rails.logger
    @base_url = 'https://api.perplexity.ai'
    @redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379'))
  end
  
  # Extract content using Perplexity's AI-powered search
  # @param query [String] URL or topic to research
  # @param options [Hash] extraction options
  # @option options [String] :model Perplexity model to use
  # @option options [Integer] :max_tokens Maximum response tokens
  # @option options [Boolean] :use_cache Use cached results if available
  # @option options [Boolean] :deep_research Use deep research mode
  # @return [Hash] Extracted content with metadata
  def extract_content_for_llm(query, options = {})
    return { error: "Perplexity API key not configured" } unless @api_key.present?
    
    # Check cache first
    if options.fetch(:use_cache, true)
      cached = get_cached_content(query, options[:model])
      return cached if cached
    end
    
    benchmark("Perplexity content extraction for #{query}") do
      model = options[:deep_research] ? MODELS[:sonar_deep_research] : (options[:model] || DEFAULT_MODEL)
      messages = build_extraction_messages(query, options[:extraction_prompt])
      
      parameters = {
        model: model,
        messages: messages,
        max_tokens: options[:max_tokens] || MAX_TOKENS,
        temperature: 0.1 # Lower temperature for factual extraction
      }
      
      response = make_api_request(parameters)
      
      if response[:error]
        @logger.error "[Perplexity] API error: #{response[:error]}"
        return response
      end
      
      formatted = format_response_for_llm(response, query, model)
      
      # Cache successful responses
      cache_content(query, model, formatted) if formatted[:success]
      
      formatted
    end
  rescue StandardError => e
    @logger.error "[Perplexity] Extraction failed for #{query}: #{e.message}"
    @logger.error e.backtrace.first(5).join("\n")
    { error: e.message, success: false }
  end
  
  # Perform deep research on a topic using Perplexity's research model
  # @param topic [String] Topic to research comprehensively
  # @param options [Hash] Research options
  # @return [Hash] Comprehensive research report
  def deep_research(topic, options = {})
    return { error: "Perplexity API key not configured" } unless @api_key.present?
    
    benchmark("Perplexity deep research for #{topic}") do
      messages = [
        { 
          role: 'system', 
          content: 'Conduct comprehensive research and provide detailed analysis with citations. Include multiple perspectives and recent developments.' 
        },
        { 
          role: 'user', 
          content: "Research and analyze: #{topic}\n\n#{options[:additional_instructions]}" 
        }
      ]
      
      parameters = {
        model: MODELS[:sonar_deep_research],
        messages: messages,
        max_tokens: 4000 # Larger token limit for comprehensive research
      }
      
      response = make_api_request(parameters)
      
      if response[:error]
        @logger.error "[Perplexity] Deep research error: #{response[:error]}"
        return response
      end
      
      format_research_response(response, topic)
    end
  rescue StandardError => e
    @logger.error "[Perplexity] Deep research failed for #{topic}: #{e.message}"
    { error: e.message, success: false }
  end
  
  # Quick fact check using Perplexity
  # @param statement [String] Statement to verify
  # @return [Hash] Fact check result with citations
  def fact_check(statement)
    extract_content_for_llm(
      statement,
      extraction_prompt: "Fact-check this statement and provide citations: #{statement}",
      model: MODELS[:sonar],
      max_tokens: 1000
    )
  end
  
  private
  
  def make_api_request(parameters)
    connection = Faraday.new(url: @base_url) do |faraday|
      faraday.headers['Authorization'] = "Bearer #{@api_key}"
      faraday.headers['Content-Type'] = 'application/json'
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 30
      faraday.options.open_timeout = 10
    end
    
    response = connection.post('/chat/completions') do |req|
      req.body = parameters.to_json
    end
    
    if response.success?
      JSON.parse(response.body)
    else
      { 
        error: "API request failed: #{response.status} - #{response.body}",
        status: response.status 
      }
    end
  rescue Faraday::TimeoutError => e
    { error: "Request timeout: #{e.message}" }
  rescue StandardError => e
    { error: "Request failed: #{e.message}" }
  end
  
  def build_extraction_messages(query, custom_prompt)
    # Detect if query is a URL or a research topic
    is_url = query.match?(/^https?:\/\//)
    
    system_prompt = if is_url
      "Extract and summarize the main content from the given URL. Focus on the primary article or page content, ignoring navigation, ads, and sidebars. Provide key insights and include source citations with links."
    else
      "Search for current, authoritative information about the given topic and provide a comprehensive summary with citations from reliable sources. Include recent developments and multiple perspectives."
    end
    
    user_prompt = custom_prompt || "Please #{is_url ? 'extract content from' : 'research'}: #{query}"
    
    [
      { role: 'system', content: system_prompt },
      { role: 'user', content: user_prompt }
    ]
  end
  
  def format_response_for_llm(response, source, model)
    content = response.dig('choices', 0, 'message', 'content')
    usage = response['usage']
    
    # Log token usage for cost monitoring
    if usage
      total_cost = calculate_cost(usage, model)
      @logger.info "[Perplexity] Token usage - Input: #{usage['prompt_tokens']}, Output: #{usage['completion_tokens']}, Total: #{usage['total_tokens']}, Est. Cost: $#{total_cost}"
    end
    
    {
      success: true,
      source: source,
      content: content,
      word_count: content&.split&.length || 0,
      char_count: content&.length || 0,
      token_usage: usage,
      estimated_cost: calculate_cost(usage, model),
      extracted_at: Time.current.iso8601,
      method: 'perplexity_api',
      model: model,
      has_citations: content&.include?('[') # Simple check for citation markers
    }
  end
  
  def format_research_response(response, topic)
    content = response.dig('choices', 0, 'message', 'content')
    usage = response['usage']
    
    {
      success: true,
      topic: topic,
      research_report: content,
      word_count: content&.split&.length || 0,
      char_count: content&.length || 0,
      token_usage: usage,
      estimated_cost: calculate_cost(usage, MODELS[:sonar_deep_research]),
      researched_at: Time.current.iso8601,
      method: 'perplexity_deep_research',
      has_citations: content&.include?('[')
    }
  end
  
  def calculate_cost(usage, model)
    return 0 unless usage
    
    # Pricing per million tokens (as of 2025)
    # Note: These are approximate - actual costs include citation tokens
    pricing = {
      'sonar' => { input: 3.0, output: 15.0 },
      'sonar-pro' => { input: 3.0, output: 15.0 },
      'sonar-reasoning' => { input: 5.0, output: 20.0 },
      'sonar-reasoning-pro' => { input: 8.0, output: 30.0 },
      'sonar-deep-research' => { input: 10.0, output: 40.0 }
    }
    
    model_pricing = pricing[model] || pricing['sonar']
    
    input_cost = (usage['prompt_tokens'] / 1_000_000.0) * model_pricing[:input]
    output_cost = (usage['completion_tokens'] / 1_000_000.0) * model_pricing[:output]
    
    (input_cost + output_cost).round(4)
  end
  
  def cache_key(query, model)
    "perplexity:#{Digest::SHA256.hexdigest("#{query}:#{model}")}"
  end
  
  def get_cached_content(query, model)
    cached = @redis.get(cache_key(query, model))
    if cached
      @logger.info "[Perplexity] Cache hit for: #{query}"
      JSON.parse(cached).symbolize_keys
    end
  rescue StandardError => e
    @logger.warn "[Perplexity] Cache read error: #{e.message}"
    nil
  end
  
  def cache_content(query, model, content)
    @redis.setex(cache_key(query, model), CACHE_TTL, content.to_json)
    @logger.info "[Perplexity] Cached content for: #{query}"
  rescue StandardError => e
    @logger.warn "[Perplexity] Cache write error: #{e.message}"
  end
end