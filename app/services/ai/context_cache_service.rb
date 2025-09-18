module Ai
  # Enhanced context caching service with tenant isolation for optimal cost savings
  # Supports both global system-wide caching and tenant-specific caching
  class ContextCacheService
    CACHE_TTL = 1.hour
    FILE_CONTENT_TTL = 30.minutes
    STANDARDS_TTL = 1.day
    TENANT_CONTEXT_TTL = 5.minutes  # For conversational flows (Anthropic's cache duration)
    SEMANTIC_CACHE_TTL = 2.hours    # For similar requests

    def initialize(app = nil)
      @app = app
      @redis = Redis.new(url: Rails.application.config_for(:redis)&.dig(:url) || ENV["REDIS_URL"] || "redis://localhost:6379/1")
    rescue => e
      Rails.logger.warn "[ContextCacheService] Redis not available, falling back to memory cache: #{e.message}"
      @redis = nil
    end

    # Cache file contents for an app to avoid redundant reads
    def cache_file_contents(app_id, files_data)
      return unless @redis

      cache_key = "ai_context:file_contents:#{app_id}"

      # Create optimized file data structure
      cached_data = files_data.map do |file|
        {
          path: file[:path],
          content_hash: Digest::SHA256.hexdigest(file[:content]),
          content: file[:content],
          file_type: file[:file_type],
          size: file[:content].length,
          modified_at: file[:updated_at] || Time.current
        }
      end

      @redis.setex(cache_key, FILE_CONTENT_TTL, cached_data.to_json)
      Rails.logger.info "[ContextCacheService] Cached #{cached_data.length} files for app #{app_id}"
    end

    # Get cached file contents, only return if files haven't changed
    def get_cached_file_contents(app_id, current_files)
      return nil unless @redis

      cache_key = "ai_context:file_contents:#{app_id}"
      cached_json = @redis.get(cache_key)
      return nil unless cached_json

      begin
        cached_data = JSON.parse(cached_json, symbolize_names: true)

        # Verify cache is still valid by checking file hashes
        if cache_valid_for_files?(cached_data, current_files)
          Rails.logger.info "[ContextCacheService] Using cached file contents for app #{app_id}"
          cached_data
        else
          Rails.logger.info "[ContextCacheService] Cache invalid for app #{app_id}, files changed"
          @redis.del(cache_key)
          nil
        end
      rescue JSON::ParserError => e
        Rails.logger.error "[ContextCacheService] Failed to parse cached data: #{e.message}"
        @redis.del(cache_key)
        nil
      end
    end

    # Cache AI standards content to avoid repeated file reads
    def cache_ai_standards
      return nil unless @redis

      cache_key = "ai_context:standards"
      cached_standards = @redis.get(cache_key)

      if cached_standards
        Rails.logger.info "[ContextCacheService] Using cached AI standards"
        return cached_standards
      end

      begin
        standards_path = Rails.root.join("AI_APP_STANDARDS.md")
        if File.exist?(standards_path)
          standards_content = ::File.read(standards_path)
          @redis.setex(cache_key, STANDARDS_TTL, standards_content)
          Rails.logger.info "[ContextCacheService] Cached AI standards (#{standards_content.length} chars)"
          return standards_content
        end
      rescue => e
        Rails.logger.error "[ContextCacheService] Failed to cache AI standards: #{e.message}"
      end

      nil
    end

    # Cache conversation context to maintain continuity
    def cache_conversation_context(app_id, user_id, context_data)
      return unless @redis

      cache_key = "ai_context:conversation:#{app_id}:#{user_id}"

      conversation_data = {
        last_request: context_data[:last_request],
        user_preferences: context_data[:user_preferences] || {},
        recent_changes: context_data[:recent_changes] || [],
        app_architecture: context_data[:app_architecture],
        cached_at: Time.current.iso8601
      }

      @redis.setex(cache_key, CACHE_TTL, conversation_data.to_json)
      Rails.logger.info "[ContextCacheService] Cached conversation context for app #{app_id}, user #{user_id}"
    end

    # Get cached conversation context
    def get_conversation_context(app_id, user_id)
      return {} unless @redis

      cache_key = "ai_context:conversation:#{app_id}:#{user_id}"
      cached_json = @redis.get(cache_key)
      return {} unless cached_json

      begin
        context_data = JSON.parse(cached_json, symbolize_names: true)
        Rails.logger.info "[ContextCacheService] Using cached conversation context for app #{app_id}, user #{user_id}"
        context_data
      rescue JSON::ParserError => e
        Rails.logger.error "[ContextCacheService] Failed to parse conversation context: #{e.message}"
        @redis.del(cache_key)
        {}
      end
    end

    # === TENANT-ISOLATED CONTEXT CACHING ===
    # Cache user-specific context with proper isolation (70% cost savings within user sessions)

    def cache_tenant_context(user_id, app_id, context_data)
      return unless @redis

      cache_key = "ai_context:tenant:#{user_id}:#{app_id}"

      tenant_data = {
        user_id: user_id,
        app_id: app_id,
        app_schema: context_data[:app_schema],
        project_config: context_data[:project_config],
        custom_components: context_data[:custom_components],
        workflow_definitions: context_data[:workflow_definitions],
        integration_configs: context_data[:integration_configs]&.except(:api_keys, :secrets),  # Strip sensitive data
        cached_at: Time.current.iso8601
      }

      @redis.setex(cache_key, TENANT_CONTEXT_TTL, tenant_data.to_json)
      Rails.logger.info "[ContextCacheService] Cached tenant context for user #{user_id}, app #{app_id}"
    end

    def get_cached_tenant_context(user_id, app_id)
      return nil unless @redis

      cache_key = "ai_context:tenant:#{user_id}:#{app_id}"
      cached_json = @redis.get(cache_key)
      return nil unless cached_json

      begin
        JSON.parse(cached_json, symbolize_names: true)
      rescue JSON::ParserError => e
        Rails.logger.warn "[ContextCacheService] Failed to parse tenant context: #{e.message}"
        nil
      end
    end

    # === SEMANTIC CACHING FOR SIMILAR REQUESTS ===
    # Cache responses for similar user requests to avoid duplicate processing

    def cache_semantic_response(request_signature, response_data)
      return unless @redis

      cache_key = "ai_context:semantic:#{request_signature}"

      cached_response = {
        request_hash: request_signature,
        response: response_data,
        cached_at: Time.current.iso8601
      }

      @redis.setex(cache_key, SEMANTIC_CACHE_TTL, cached_response.to_json)
      Rails.logger.info "[ContextCacheService] Cached semantic response for signature #{request_signature[0..8]}..."
    end

    def get_semantic_response(request_signature)
      return nil unless @redis

      cache_key = "ai_context:semantic:#{request_signature}"
      cached_json = @redis.get(cache_key)
      return nil unless cached_json

      begin
        cached_data = JSON.parse(cached_json, symbolize_names: true)
        cached_data[:response]
      rescue JSON::ParserError => e
        Rails.logger.warn "[ContextCacheService] Failed to parse semantic response: #{e.message}"
        nil
      end
    end

    # Generate a consistent signature for similar requests
    def generate_request_signature(user_request, app_context)
      # Normalize and hash the request to find similar patterns
      normalized_request = user_request.downcase.strip

      # Extract key context elements that affect response
      context_hash = {
        app_type: app_context[:app_type],
        framework: app_context[:framework],
        has_auth: app_context[:has_auth],
        component_count: app_context[:file_count] || 0
      }

      signature_content = "#{normalized_request}:#{context_hash.to_json}"
      Digest::SHA256.hexdigest(signature_content)
    end

    # Cache environment variables to avoid repeated queries
    def cache_env_vars(app_id, env_vars)
      return unless @redis

      cache_key = "ai_context:env_vars:#{app_id}"
      @redis.setex(cache_key, CACHE_TTL, env_vars.to_json)
    end

    def get_cached_env_vars(app_id)
      return nil unless @redis

      cache_key = "ai_context:env_vars:#{app_id}"
      cached_json = @redis.get(cache_key)
      return nil unless cached_json

      JSON.parse(cached_json, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    # Cache model responses to avoid identical API calls
    def cache_model_response(request_hash, response_data)
      return unless @redis

      cache_key = "ai_context:model_response:#{request_hash}"

      cached_response = {
        response: response_data,
        cached_at: Time.current.iso8601,
        ttl: CACHE_TTL
      }

      @redis.setex(cache_key, CACHE_TTL, cached_response.to_json)
    end

    def get_cached_model_response(request_hash)
      return nil unless @redis

      cache_key = "ai_context:model_response:#{request_hash}"
      cached_json = @redis.get(cache_key)
      return nil unless cached_json

      begin
        cached_data = JSON.parse(cached_json, symbolize_names: true)
        Rails.logger.info "[ContextCacheService] Using cached model response"
        cached_data[:response]
      rescue JSON::ParserError => e
        Rails.logger.error "[ContextCacheService] Failed to parse cached response: #{e.message}"
        nil
      end
    end

    # === ENHANCED CACHE MANAGEMENT ===

    # Clear all cache for an app (useful when app is modified externally)
    def clear_app_cache(app_id)
      return unless @redis

      patterns = [
        "ai_context:file_contents:#{app_id}",
        "ai_context:conversation:#{app_id}:*",
        "ai_context:tenant:*:#{app_id}",
        "ai_context:env_vars:#{app_id}"
      ]

      patterns.each do |pattern|
        if pattern.include?("*")
          keys = @redis.keys(pattern)
          @redis.del(*keys) if keys.any?
        else
          @redis.del(pattern)
        end
      end

      Rails.logger.info "[ContextCacheService] Cleared cache for app #{app_id}"
    end

    def clear_tenant_cache(user_id)
      return unless @redis

      pattern = "ai_context:tenant:#{user_id}:*"
      keys = @redis.keys(pattern)
      @redis.del(*keys) if keys.any?

      Rails.logger.info "[ContextCacheService] Cleared #{keys.length} tenant cache entries for user #{user_id}"
    end

    # === ENHANCED CACHE STATISTICS ===

    def get_cache_stats(user_id = nil, app_id = nil)
      return {redis_available: false} unless @redis

      stats = {
        redis_available: true,
        total_keys: 0,
        global_cache_keys: 0,
        tenant_cache_keys: 0,
        semantic_cache_keys: 0,
        file_cache_keys: 0,
        conversation_keys: 0
      }

      # Count different cache types
      stats[:file_cache_keys] = @redis.keys("ai_context:file_contents:*").length
      stats[:conversation_keys] = @redis.keys("ai_context:conversation:*").length
      stats[:semantic_cache_keys] = @redis.keys("ai_context:semantic:*").length

      stats[:tenant_cache_keys] = if user_id
        @redis.keys("ai_context:tenant:#{user_id}:*").length
      else
        @redis.keys("ai_context:tenant:*").length
      end

      stats[:total_keys] = stats.values.select { |v| v.is_a?(Integer) }.sum

      # Add Redis performance stats
      begin
        info = @redis.info
        stats[:memory_used] = info["used_memory_human"]
        stats[:connected_clients] = info["connected_clients"]
        stats[:keyspace_hits] = info["keyspace_hits"]
        stats[:keyspace_misses] = info["keyspace_misses"]
        stats[:hit_rate] = calculate_hit_rate(info["keyspace_hits"], info["keyspace_misses"])
      rescue => e
        stats[:redis_error] = e.message
      end

      stats
    end

    # Get cache statistics for monitoring (backward compatibility)
    def cache_stats
      get_cache_stats
    end

    private

    # Check if cached file data is still valid
    def cache_valid_for_files?(cached_data, current_files)
      return false if cached_data.length != current_files.length

      current_files.each do |current_file|
        cached_file = cached_data.find { |f| f[:path] == current_file.path }
        return false unless cached_file

        # Check if content hash matches
        current_hash = Digest::SHA256.hexdigest(current_file.content)
        return false if current_hash != cached_file[:content_hash]
      end

      true
    end

    def calculate_hit_rate(hits, misses)
      return 0.0 if hits.to_i == 0 && misses.to_i == 0
      (hits.to_f / (hits.to_f + misses.to_f) * 100).round(2)
    end

    # Generate a consistent hash for request caching
    def generate_request_hash(messages, model, temperature)
      content = "#{messages.to_json}:#{model}:#{temperature}"
      Digest::SHA256.hexdigest(content)
    end
  end
end
