# frozen_string_literal: true

module Ai
  # Service to track and analyze cache performance metrics
  # Helps monitor the effectiveness of prompt caching optimization
  class CacheMetricsService
    include Singleton
    
    attr_reader :metrics
    
    def initialize
      reset_metrics
    end
    
    def reset_metrics
      @metrics = {
        total_requests: 0,
        cache_hits: 0,
        cache_misses: 0,
        total_input_tokens: 0,
        cached_tokens_read: 0,
        cached_tokens_written: 0,
        uncached_tokens: 0,
        total_cost_saved: 0.0,
        context_sizes: [],
        cache_hit_rates_by_block: Hash.new { |h, k| h[k] = { hits: 0, total: 0 } },
        timestamp: Time.current
      }
    end
    
    # Log a Claude API response with cache metrics
    def log_api_response(response, prompt_size_chars = nil)
      return unless response.is_a?(Hash)
      
      @metrics[:total_requests] += 1
      
      # Extract usage metrics
      usage = response['usage'] || response[:usage] || {}
      
      input_tokens = usage['input_tokens'] || usage[:input_tokens] || 0
      cache_read = usage['cache_read_input_tokens'] || usage[:cache_read_input_tokens] || 0
      cache_write = usage['cache_creation_input_tokens'] || usage[:cache_creation_input_tokens] || 0
      
      @metrics[:total_input_tokens] += input_tokens
      @metrics[:cached_tokens_read] += cache_read
      @metrics[:cached_tokens_written] += cache_write
      @metrics[:uncached_tokens] += (input_tokens - cache_read - cache_write)
      
      # Track cache hit/miss
      if cache_read > 0
        @metrics[:cache_hits] += 1
      else
        @metrics[:cache_misses] += 1
      end
      
      # Track context size if provided
      if prompt_size_chars
        @metrics[:context_sizes] << prompt_size_chars
      end
      
      # Calculate cost savings
      cost_saved = calculate_cost_savings(cache_read, cache_write, input_tokens)
      @metrics[:total_cost_saved] += cost_saved
      
      # Log current metrics
      log_current_metrics(cache_read, cache_write, input_tokens, cost_saved)
    end
    
    # Track cache performance by block type
    def log_cache_block(block_type, cache_hit)
      @metrics[:cache_hit_rates_by_block][block_type][:total] += 1
      @metrics[:cache_hit_rates_by_block][block_type][:hits] += 1 if cache_hit
    end
    
    # Get current cache hit rate
    def cache_hit_rate
      return 0.0 if @metrics[:total_requests] == 0
      (@metrics[:cache_hits].to_f / @metrics[:total_requests] * 100).round(2)
    end
    
    # Get cache efficiency (% of tokens served from cache)
    def cache_efficiency
      total = @metrics[:total_input_tokens]
      return 0.0 if total == 0
      (@metrics[:cached_tokens_read].to_f / total * 100).round(2)
    end
    
    # Get average context size
    def average_context_size
      return 0 if @metrics[:context_sizes].empty?
      @metrics[:context_sizes].sum / @metrics[:context_sizes].size
    end
    
    # Get detailed report
    def generate_report
      report = []
      report << "=== Cache Performance Report ==="
      report << "Period: #{@metrics[:timestamp].strftime('%Y-%m-%d %H:%M')} - #{Time.current.strftime('%H:%M')}"
      report << ""
      report << "Overview:"
      report << "  Total Requests: #{@metrics[:total_requests]}"
      report << "  Cache Hit Rate: #{cache_hit_rate}%"
      report << "  Cache Efficiency: #{cache_efficiency}%"
      report << ""
      report << "Token Usage:"
      report << "  Total Input: #{format_number(@metrics[:total_input_tokens])}"
      report << "  Cached (Read): #{format_number(@metrics[:cached_tokens_read])}"
      report << "  Cached (Write): #{format_number(@metrics[:cached_tokens_written])}"
      report << "  Uncached: #{format_number(@metrics[:uncached_tokens])}"
      report << ""
      report << "Cost Analysis:"
      report << "  Total Saved: $#{@metrics[:total_cost_saved].round(2)}"
      report << "  Avg Save/Request: $#{(@metrics[:total_cost_saved] / [@metrics[:total_requests], 1].max).round(3)}"
      report << ""
      report << "Context Optimization:"
      report << "  Avg Context Size: #{format_number(average_context_size)} chars"
      report << "  Target: <30,000 chars"
      report << "  Status: #{average_context_size <= 30_000 ? '✅ Optimized' : '⚠️ Above Target'}"
      
      if @metrics[:cache_hit_rates_by_block].any?
        report << ""
        report << "Cache Performance by Block:"
        @metrics[:cache_hit_rates_by_block].each do |block_type, stats|
          hit_rate = stats[:total] > 0 ? (stats[:hits].to_f / stats[:total] * 100).round(1) : 0
          report << "  #{block_type}: #{hit_rate}% (#{stats[:hits]}/#{stats[:total]})"
        end
      end
      
      report.join("\n")
    end
    
    # Store metrics in Redis for dashboard
    def persist_to_redis
      return unless defined?(Redis) && Redis.current
      
      redis_key = "cache_metrics:#{Date.current}"
      
      Redis.current.hmset(
        redis_key,
        'requests', @metrics[:total_requests],
        'cache_hits', @metrics[:cache_hits],
        'cache_efficiency', cache_efficiency,
        'cost_saved', @metrics[:total_cost_saved],
        'avg_context_size', average_context_size,
        'updated_at', Time.current.to_i
      )
      
      # Expire after 7 days
      Redis.current.expire(redis_key, 7.days.to_i)
    rescue => e
      Rails.logger.error "[CacheMetrics] Failed to persist to Redis: #{e.message}"
    end
    
    private
    
    def calculate_cost_savings(cache_read, cache_write, total_input)
      # Pricing per million tokens (Claude-3 Opus)
      standard_price = 15.0  # $15 per million input tokens
      cache_read_price = 1.5  # $1.50 per million cached read tokens (90% discount)
      cache_write_price = 18.75  # $18.75 per million cache write tokens (25% premium)
      
      # What we actually paid
      actual_cost = (cache_read * cache_read_price + 
                    cache_write * cache_write_price + 
                    (total_input - cache_read - cache_write) * standard_price) / 1_000_000
      
      # What we would have paid without caching
      no_cache_cost = (total_input * standard_price) / 1_000_000
      
      # Return savings
      [no_cache_cost - actual_cost, 0].max
    end
    
    def log_current_metrics(cache_read, cache_write, input_tokens, cost_saved)
      hit_rate = cache_hit_rate
      efficiency = cache_efficiency
      
      if cache_read > 0
        Rails.logger.info "[CACHE_METRICS] ✅ Cache HIT: #{cache_read} tokens read (#{efficiency}% efficiency)"
      else
        Rails.logger.info "[CACHE_METRICS] ❌ Cache MISS: #{input_tokens} tokens processed"
      end
      
      Rails.logger.info "[CACHE_METRICS] Overall: #{hit_rate}% hit rate | $#{cost_saved.round(3)} saved this request"
      
      # Warn if context is getting too large
      if @metrics[:context_sizes].last && @metrics[:context_sizes].last > 50_000
        Rails.logger.warn "[CACHE_METRICS] ⚠️ Context size (#{@metrics[:context_sizes].last} chars) exceeds target!"
      end
    end
    
    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
    
    class << self
      def instance
        @instance ||= new
      end
      
      delegate :log_api_response, :log_cache_block, :cache_hit_rate, 
               :cache_efficiency, :generate_report, :persist_to_redis,
               :reset_metrics, to: :instance
    end
  end
end