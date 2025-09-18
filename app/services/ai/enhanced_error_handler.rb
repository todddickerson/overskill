require "net/http"

module Ai
  # Enhanced error handling and retry mechanisms for AI operations
  class EnhancedErrorHandler
    MAX_RETRIES = 3
    RETRY_DELAYS = [1, 2, 5].freeze # Exponential backoff in seconds

    # Retriable error types
    RETRIABLE_ERRORS = [
      Timeout::Error,
      Net::ReadTimeout,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      JSON::ParserError,
      HTTParty::Error
    ].freeze

    # Error categories for better handling
    ERROR_CATEGORIES = {
      network: [Timeout::Error, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED],
      parsing: [JSON::ParserError],
      api: [HTTParty::Error],
      validation: [ArgumentError, StandardError]
    }.freeze

    def self.with_retry(operation_name, max_retries: MAX_RETRIES, &block)
      new.execute_with_retry(operation_name, max_retries: max_retries, &block)
    end

    def initialize
      @retry_stats = {}
    end

    def execute_with_retry(operation_name, max_retries: MAX_RETRIES)
      attempt = 0
      start_time = Time.current

      begin
        attempt += 1
        Rails.logger.info "[EnhancedErrorHandler] Executing #{operation_name} (attempt #{attempt}/#{max_retries + 1})"

        result = yield(attempt)

        # Track success
        track_operation_success(operation_name, attempt, Time.current - start_time)

        {success: true, result: result, attempt: attempt}
      rescue => error
        error_category = categorize_error(error)
        duration = Time.current - start_time

        Rails.logger.warn "[EnhancedErrorHandler] #{operation_name} failed (attempt #{attempt}): #{error.class.name} - #{error.message}"

        # Track failure
        track_operation_failure(operation_name, attempt, error, duration)

        # Check if we should retry
        if should_retry?(error, attempt, max_retries)
          delay = calculate_retry_delay(attempt, error_category)
          Rails.logger.info "[EnhancedErrorHandler] Retrying #{operation_name} in #{delay} seconds..."

          sleep(delay)
          retry
        else
          Rails.logger.error "[EnhancedErrorHandler] #{operation_name} failed permanently after #{attempt} attempts"

          {
            success: false,
            error: error.message,
            error_class: error.class.name,
            error_category: error_category,
            attempt: attempt,
            duration: duration,
            suggestion: generate_error_suggestion(error, error_category)
          }
        end
      end
    end

    # Execute multiple operations with coordinated retry logic
    def execute_batch_with_retry(operations, max_retries: MAX_RETRIES)
      results = {}
      overall_success = true

      operations.each do |name, operation|
        result = execute_with_retry(name, max_retries: max_retries, &operation)
        results[name] = result
        overall_success = false unless result[:success]
      end

      {
        success: overall_success,
        results: results,
        summary: generate_batch_summary(results)
      }
    end

    # Rollback mechanism for failed operations
    def execute_with_rollback(operation_name, rollback_actions: [], &block)
      result = execute_with_retry(operation_name, &block)

      unless result[:success]
        Rails.logger.info "[EnhancedErrorHandler] Executing rollback for #{operation_name}"

        rollback_results = []
        rollback_actions.reverse.each_with_index do |action, index|
          Rails.logger.info "[EnhancedErrorHandler] Rollback step #{index + 1}: #{action[:description]}"
          action[:block].call
          rollback_results << {step: action[:description], success: true}
        rescue => rollback_error
          Rails.logger.error "[EnhancedErrorHandler] Rollback step failed: #{rollback_error.message}"
          rollback_results << {
            step: action[:description],
            success: false,
            error: rollback_error.message
          }
        end

        result[:rollback_results] = rollback_results
      end

      result
    end

    # Circuit breaker pattern for frequent failures
    def with_circuit_breaker(operation_name, failure_threshold: 5, timeout: 60, &block)
      circuit_key = "circuit_breaker:#{operation_name}"

      # Check if circuit is open
      if circuit_open?(circuit_key)
        return {
          success: false,
          error: "Circuit breaker is open for #{operation_name}",
          circuit_breaker_status: :open
        }
      end

      result = execute_with_retry(operation_name, &block)

      if result[:success]
        reset_circuit_breaker(circuit_key)
      else
        increment_circuit_breaker_failures(circuit_key, failure_threshold, timeout)
      end

      result.merge(circuit_breaker_status: get_circuit_status(circuit_key))
    end

    # Get retry statistics for monitoring
    def get_retry_stats
      @retry_stats
    end

    # Get error recommendations based on patterns
    def analyze_error_patterns(time_window: 1.hour)
      recent_failures = @retry_stats.select do |_, stats|
        stats[:last_failure] && stats[:last_failure] > time_window.ago
      end

      {
        total_operations: @retry_stats.count,
        failed_operations: recent_failures.count,
        most_problematic: recent_failures.max_by { |_, stats| stats[:failure_count] }&.first,
        recommendations: generate_pattern_recommendations(recent_failures)
      }
    end

    private

    def should_retry?(error, attempt, max_retries)
      return false if attempt > max_retries

      # Check if error type is retriable
      RETRIABLE_ERRORS.any? { |retriable_error| error.is_a?(retriable_error) }
    end

    def categorize_error(error)
      ERROR_CATEGORIES.each do |category, error_types|
        return category if error_types.any? { |type| error.is_a?(type) }
      end
      :unknown
    end

    def calculate_retry_delay(attempt, error_category)
      base_delay = RETRY_DELAYS[attempt - 1] || RETRY_DELAYS.last

      # Adjust delay based on error category
      multiplier = case error_category
      when :network
        2.0 # Network issues need more time
      when :parsing
        1.0 # Parsing errors are usually quick to resolve
      when :api
        1.5 # API errors might need moderate delay
      else
        1.0
      end

      (base_delay * multiplier).to_i
    end

    def track_operation_success(operation_name, attempt, duration)
      @retry_stats[operation_name] ||= {
        success_count: 0,
        failure_count: 0,
        total_attempts: 0,
        avg_duration: 0,
        last_success: nil,
        last_failure: nil
      }

      stats = @retry_stats[operation_name]
      stats[:success_count] += 1
      stats[:total_attempts] += attempt
      stats[:last_success] = Time.current

      # Update average duration
      stats[:avg_duration] = (stats[:avg_duration] * (stats[:success_count] - 1) + duration) / stats[:success_count]
    end

    def track_operation_failure(operation_name, attempt, error, duration)
      @retry_stats[operation_name] ||= {
        success_count: 0,
        failure_count: 0,
        total_attempts: 0,
        avg_duration: 0,
        last_success: nil,
        last_failure: nil,
        recent_errors: []
      }

      stats = @retry_stats[operation_name]
      stats[:failure_count] += 1
      stats[:total_attempts] += attempt
      stats[:last_failure] = Time.current

      # Track recent errors (keep last 5)
      stats[:recent_errors] ||= []
      stats[:recent_errors] << {
        error_class: error.class.name,
        message: error.message,
        timestamp: Time.current,
        attempt: attempt
      }
      stats[:recent_errors] = stats[:recent_errors].last(5)
    end

    def generate_error_suggestion(error, category)
      case category
      when :network
        "Network connectivity issue. Check internet connection and OpenRouter service status."
      when :parsing
        "JSON parsing failed. This might be due to truncated responses or invalid JSON. Consider increasing max_tokens."
      when :api
        "API error occurred. Check API key, rate limits, and service availability."
      when :validation
        "Validation error. Review input parameters and data formats."
      else
        "Unknown error type. Check logs for more details and consider contacting support."
      end
    end

    def generate_batch_summary(results)
      total = results.count
      successful = results.count { |_, result| result[:success] }
      failed = total - successful

      {
        total: total,
        successful: successful,
        failed: failed,
        success_rate: (successful.to_f / total * 100).round(1)
      }
    end

    def generate_pattern_recommendations(recent_failures)
      recommendations = []

      if recent_failures.any?
        error_types = recent_failures.values.flat_map { |stats| stats[:recent_errors]&.map { |e| e[:error_class] } || [] }
        most_common_error = error_types.tally.max_by { |_, count| count }&.first

        if most_common_error
          recommendations << "Most common recent error: #{most_common_error}"
          recommendations << case most_common_error
          when "Timeout::Error"
            "Consider increasing timeout values or checking network stability"
          when "JSON::ParserError"
            "Increase max_tokens or improve response validation"
          else
            "Monitor this error pattern for further analysis"
          end
        end
      end

      recommendations
    end

    # Circuit breaker implementation
    def circuit_open?(circuit_key)
      Rails.cache.read("#{circuit_key}:state") == "open"
    end

    def reset_circuit_breaker(circuit_key)
      Rails.cache.delete("#{circuit_key}:state")
      Rails.cache.delete("#{circuit_key}:failures")
    end

    def increment_circuit_breaker_failures(circuit_key, threshold, timeout)
      failures_key = "#{circuit_key}:failures"
      current_failures = Rails.cache.read(failures_key) || 0
      new_failures = current_failures + 1

      Rails.cache.write(failures_key, new_failures, expires_in: timeout)

      if new_failures >= threshold
        Rails.cache.write("#{circuit_key}:state", "open", expires_in: timeout)
        Rails.logger.warn "[EnhancedErrorHandler] Circuit breaker opened for #{circuit_key} after #{new_failures} failures"
      end
    end

    def get_circuit_status(circuit_key)
      if circuit_open?(circuit_key)
        :open
      elsif Rails.cache.read("#{circuit_key}:failures")
        :half_open
      else
        :closed
      end
    end
  end
end
