# frozen_string_literal: true

require 'httparty'
require 'nokogiri'
require 'readability'
require 'html_to_plain_text'

class WebContentExtractionService
  include HTTParty
  include ActiveSupport::Benchmarkable
  
  # Maximum content length to prevent memory issues
  MAX_CONTENT_LENGTH = 100_000
  MAX_RESPONSE_SIZE = 5_000_000 # 5MB
  
  # User agent to identify as a legitimate bot
  USER_AGENT = 'Mozilla/5.0 (compatible; OverskillBot/1.0; AI Content Extraction)'
  
  # HTTParty configuration
  default_timeout 20
  headers('User-Agent' => USER_AGENT)
  
  def initialize
    @logger = Rails.logger
    @security_filter = Security::PromptInjectionFilter.new if defined?(Security::PromptInjectionFilter)
  end
  
  # ActiveSupport::Benchmarkable expects a logger method
  def logger
    @logger
  end

  # Main method to extract content for LLM consumption
  def extract_for_llm(url, options = {})
    benchmark("Content extraction for #{url}") do
      # Validate URL
      return { error: "Invalid URL format" } unless valid_url?(url)
      
      # Security check for malicious URLs
      return { error: "URL blocked for security reasons" } if blocked_url?(url)
      
      # Check cache first
      if options[:use_cache] != false
        cached = fetch_from_cache(url)
        return cached if cached
      end
      
      # Fetch HTML content
      html_content = fetch_page_content(url)
      return { error: "Failed to fetch content" } unless html_content
      
      # Extract readable content
      readable_content = extract_readable_text(html_content, url)
      
      # Prepare for LLM consumption
      llm_ready_text = clean_for_llm(readable_content)
      
      # Truncate if too long
      if llm_ready_text.length > MAX_CONTENT_LENGTH
        llm_ready_text = truncate_content(llm_ready_text, MAX_CONTENT_LENGTH)
      end
      
      # Security check on extracted content
      if @security_filter && !@security_filter.validate_output(llm_ready_text)
        @logger.warn "[WebContent] Suspicious content detected from #{url}"
        llm_ready_text = @security_filter.filter_response(llm_ready_text)
      end
      
      result = {
        url: url,
        title: extract_title(html_content),
        content: llm_ready_text,
        word_count: llm_ready_text.split.length,
        char_count: llm_ready_text.length,
        extracted_at: Time.current,
        truncated: llm_ready_text.length >= MAX_CONTENT_LENGTH
      }
      
      # Cache the result
      cache_result(url, result) if options[:use_cache] != false
      
      result
    end
  rescue StandardError => e
    @logger.error "[WebContent] Extraction failed for #{url}: #{e.message}"
    @logger.error e.backtrace.first(5).join("\n") if Rails.env.development?
    { error: e.message, url: url }
  end

  # Extract content from multiple URLs in parallel
  def extract_multiple(urls, options = {})
    urls.map do |url|
      Thread.new { extract_for_llm(url, options) }
    end.map(&:value)
  end

  private

  def fetch_page_content(url)
    # HTTParty GET with retry logic
    attempts = 0
    max_attempts = 3
    
    begin
      attempts += 1
      
      response = self.class.get(url, {
        headers: {
          'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language' => 'en-US,en;q=0.9',
          'Accept-Encoding' => 'gzip, deflate',
          'DNT' => '1'
        },
        timeout: 20
      })
      
      return nil unless response.success?
      
      # Check response size
      if response.body && response.body.bytesize > MAX_RESPONSE_SIZE
        @logger.warn "[WebContent] Response too large: #{response.body.bytesize} bytes (max: #{MAX_RESPONSE_SIZE})"
        return nil
      end
      
      # Check content type
      content_type = response.headers['content-type'] || ''
      unless content_type.include?('text/html') || content_type.include?('application/xhtml')
        @logger.warn "[WebContent] Non-HTML content type: #{content_type} for #{url}"
        return nil
      end
      
      response.body
      
    rescue HTTParty::Error, Net::TimeoutError, SocketError => e
      if attempts < max_attempts
        sleep_time = 0.5 * (2 ** (attempts - 1)) # Exponential backoff
        @logger.info "[WebContent] Retrying #{url} in #{sleep_time}s (attempt #{attempts}/#{max_attempts})"
        sleep(sleep_time)
        retry
      else
        @logger.error "[WebContent] Failed to fetch #{url} after #{max_attempts} attempts: #{e.message}"
        return nil
      end
    end
  end

  def extract_readable_text(html_content, url)
    # Try ruby-readability for main content extraction
    begin
      document = Readability::Document.new(
        html_content,
        tags: %w[div p article section main h1 h2 h3 h4 h5 h6 ul ol li blockquote pre code],
        remove_empty_nodes: true,
        remove_unlikely_candidates: true,
        weight_classes: true
      )
      
      article_html = document.content
      
      # If readability returns minimal content, fall back to basic extraction
      if article_html.nil? || article_html.strip.length < 100
        article_html = fallback_extraction(html_content)
      end
      
      article_html
    rescue => e
      @logger.warn "[WebContent] Readability failed for #{url}: #{e.message}"
      fallback_extraction(html_content)
    end
  end

  def fallback_extraction(html_content)
    doc = Nokogiri::HTML(html_content)
    
    # Remove problematic elements
    doc.css('script, style, nav, footer, header, aside, iframe, noscript').remove
    doc.css('[role="navigation"]').remove
    doc.css('[role="banner"]').remove
    doc.css('[role="complementary"]').remove
    doc.css('.ad, .ads, .advertisement, .promo, .social-share').remove
    
    # Try to find main content areas
    main_content = doc.css('main, article, [role="main"], .content, .post, #content').first
    main_content ||= doc.css('.article-body, .entry-content, .post-content').first
    main_content ||= doc.css('body').first
    
    main_content&.to_html || ""
  end

  def clean_for_llm(html_content)
    return "" if html_content.nil? || html_content.empty?
    
    # Convert to plain text with structure preservation
    begin
      plain_text = HtmlToPlainText.plain_text(html_content)
    rescue => e
      # Fallback to Nokogiri text extraction
      @logger.warn "[WebContent] HtmlToPlainText failed: #{e.message}"
      doc = Nokogiri::HTML(html_content)
      plain_text = doc.text
    end
    
    # Clean up for LLM consumption
    cleaned = plain_text
      .gsub(/\n{4,}/, "\n\n\n")     # Max 3 line breaks
      .gsub(/\t+/, " ")              # Replace tabs with space
      .gsub(/[ ]{3,}/, "  ")         # Max 2 consecutive spaces
      .gsub(/\r/, "")                # Remove carriage returns
      .gsub(/^\s+|\s+$/, '')         # Trim each line
      .strip
    
    # Remove any potentially harmful content
    cleaned.gsub!(/\b(api[_\s]?key|secret|password|token)\s*[:=]\s*[\w\-]+/i, '[REDACTED]')
    
    cleaned
  end

  def extract_title(html_content)
    doc = Nokogiri::HTML(html_content)
    
    # Try multiple title sources
    title = doc.css('title').first&.text&.strip
    title ||= doc.css('h1').first&.text&.strip
    title ||= doc.css('meta[property="og:title"]').first&.attr('content')
    title ||= doc.css('meta[name="twitter:title"]').first&.attr('content')
    
    title&.slice(0, 200) || "Untitled"
  end

  def truncate_content(text, max_length)
    return text if text.length <= max_length
    
    # Try to truncate at a sentence boundary
    truncated = text[0...max_length]
    last_period = truncated.rindex(/[.!?]\s/)
    
    if last_period && last_period > max_length * 0.8
      truncated = truncated[0..last_period]
    end
    
    "#{truncated.strip}... [Content truncated for length]"
  end

  def valid_url?(url)
    uri = URI.parse(url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def blocked_url?(url)
    # Block potentially dangerous URLs
    blocked_patterns = [
      /^file:/i,
      /^javascript:/i,
      /^data:/i,
      /localhost/i,
      /127\.0\.0\.1/,
      /192\.168\./,
      /10\.\d+\.\d+\.\d+/,
      /172\.(1[6-9]|2\d|3[01])\./,
      /\.local$/i
    ]
    
    blocked_patterns.any? { |pattern| url.match?(pattern) }
  end

  def fetch_from_cache(url)
    return nil unless defined?(Rails.cache)
    
    cache_key = "web_content:#{Digest::SHA256.hexdigest(url)}"
    Rails.cache.fetch(cache_key)
  end

  def cache_result(url, result)
    return unless defined?(Rails.cache)
    
    cache_key = "web_content:#{Digest::SHA256.hexdigest(url)}"
    # Cache for 1 hour by default
    Rails.cache.write(cache_key, result, expires_in: 1.hour)
  end
end

