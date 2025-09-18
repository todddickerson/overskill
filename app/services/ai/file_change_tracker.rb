module Ai
  # Tracks file changes for intelligent cache invalidation
  # Part of the file-level granular caching strategy to optimize Anthropic API costs
  class FileChangeTracker
    HASH_TTL = 1.hour
    CHANGE_LOG_TTL = 24.hours
    CHANGE_LOG_MAX_SIZE = 1000

    def initialize(app_id)
      @app_id = app_id
      @redis = Redis.new(url: Rails.application.config_for(:redis)&.dig(:url) || ENV["REDIS_URL"] || "redis://localhost:6379/1")
    rescue => e
      Rails.logger.warn "[FileChangeTracker] Redis not available: #{e.message}"
      @redis = nil
    end

    # Track a file change and return whether it actually changed
    def track_file_change(file_path, content)
      return false unless @redis

      begin
        new_hash = Digest::SHA256.hexdigest(content)
        cache_key = file_hash_key(file_path)

        # Get old hash and check if changed
        old_hash = @redis.get(cache_key)
        changed = (old_hash != new_hash)

        # Only update if value actually changed
        if changed
          # setex is atomic - no need for transaction for single operation
          @redis.setex(cache_key, HASH_TTL, new_hash)

          # Add to file index for fast lookups (replaces Redis.keys)
          add_to_file_index(file_path)

          # Log the change
          log_change(file_path, old_hash, new_hash)

          # Invalidate any cached prompts containing this file
          invalidate_file_cache(file_path)

          Rails.logger.info "[FileChangeTracker] File changed: #{file_path} (app: #{@app_id})"
        elsif old_hash.nil?
          # New file - track it
          @redis.setex(cache_key, HASH_TTL, new_hash)
          add_to_file_index(file_path)
        end

        changed
      rescue Redis::BaseError => e
        Rails.logger.error "[FileChangeTracker] Redis error tracking file change: #{e.message}"
        false  # Return false on error to avoid breaking the flow
      end
    end

    # Track multiple file changes and return list of changed files
    def track_multiple_changes(file_changes)
      return [] unless @redis

      changed_files = []

      file_changes.each do |file_path, content|
        if track_file_change(file_path, content)
          changed_files << file_path
        end
      end

      changed_files
    end

    # Get list of files changed since a given timestamp
    def get_changed_files_since(timestamp)
      return [] unless @redis

      begin
        change_log_key = change_log_key()

        # Get changes from sorted set (scored by timestamp)
        min_score = timestamp.to_f
        max_score = "+inf"

        changes = @redis.zrangebyscore(change_log_key, min_score, max_score, with_scores: true)

        # Parse and return unique file paths
        changes.map do |entry, _score|
          JSON.parse(entry)["file_path"]
        rescue
          nil
        end.compact.uniq
      rescue Redis::BaseError => e
        Rails.logger.error "[FileChangeTracker] Redis error getting changed files: #{e.message}"
        []
      end
    end

    # Get change frequency for a file (changes per hour over last 24h)
    def get_change_frequency(file_path)
      return 0.0 unless @redis

      begin
        change_log_key = change_log_key()

        # Count changes in last 24 hours
        min_score = 24.hours.ago.to_f
        max_score = Time.current.to_f

        changes = @redis.zrangebyscore(change_log_key, min_score, max_score)

        file_changes = changes.count do |entry|
          parsed = begin
            JSON.parse(entry)
          rescue
            {}
          end
          parsed["file_path"] == file_path
        end

        # Return changes per hour
        file_changes / 24.0
      rescue Redis::BaseError => e
        Rails.logger.error "[FileChangeTracker] Redis error getting change frequency: #{e.message}"
        0.0
      end
    end

    # Check if a file has been recently modified (within threshold)
    def recently_changed?(file_path, threshold = 5.minutes)
      changed_files = get_changed_files_since(threshold.ago)
      changed_files.include?(file_path)
    end

    # Get stability score for a file (0-10, higher = more stable)
    def get_stability_score(file_path)
      frequency = get_change_frequency(file_path)

      # Convert frequency to stability score
      # 0 changes/hour = 10 (most stable)
      # 10+ changes/hour = 0 (least stable)
      score = [10 - frequency, 0].max
      score.round(1)
    end

    # Categorize files by their change patterns
    def categorize_files_by_stability(file_paths)
      return {stable: [], active: [], volatile: []} unless @redis

      categorized = {
        stable: [],    # Rarely changes (score >= 8)
        active: [],    # Moderate changes (score 4-7)
        volatile: []   # Frequent changes (score < 4)
      }

      file_paths.each do |file_path|
        score = get_stability_score(file_path)

        if score >= 8
          categorized[:stable] << file_path
        elsif score >= 4
          categorized[:active] << file_path
        else
          categorized[:volatile] << file_path
        end
      end

      categorized
    end

    # Invalidate cached prompts that contain this file
    def invalidate_file_cache(file_path)
      return unless @redis

      begin
        # Mark file as invalidated
        invalidation_key = "cache_invalid:#{@app_id}:#{file_path}"
        @redis.setex(invalidation_key, 5.minutes, Time.current.to_i)
        add_to_invalidation_index(file_path)

        # Get prompt cache keys from index (avoids Redis.keys scan)
        prompt_cache_index_key = "prompt_cache_index:#{@app_id}"
        cache_keys = @redis.zrange(prompt_cache_index_key, 0, -1)

        invalidated_count = 0
        cache_keys.each do |key|
          # Check if this cache entry contains the changed file
          cache_data = @redis.get(key)
          if cache_data&.include?(file_path)
            @redis.del(key)
            @redis.zrem(prompt_cache_index_key, key)  # Remove from index
            invalidated_count += 1
          end
        end

        Rails.logger.info "[FileChangeTracker] Invalidated #{invalidated_count} cached prompts containing #{file_path}" if invalidated_count > 0
      rescue Redis::BaseError => e
        Rails.logger.error "[FileChangeTracker] Redis error invalidating cache: #{e.message}"
      end
    end

    # Check if a file's cache is still valid
    def cache_valid?(file_path)
      return true unless @redis

      invalidation_key = "cache_invalid:#{@app_id}:#{file_path}"
      !@redis.exists?(invalidation_key)
    end

    # Get cache validity for multiple files
    def get_cache_validity(file_paths)
      return {} unless @redis

      validity = {}

      file_paths.each do |file_path|
        validity[file_path] = cache_valid?(file_path)
      end

      validity
    end

    # Clear all tracking data for an app
    def clear_all_tracking
      return unless @redis

      # Clear using indexes instead of Redis.keys
      file_index_key = "file_index:#{@app_id}"
      invalidation_index_key = "invalidation_index:#{@app_id}"
      prompt_cache_index_key = "prompt_cache_index:#{@app_id}"

      # Get all tracked files from index
      tracked_files = @redis.zrange(file_index_key, 0, -1)
      tracked_files.each do |file_path|
        @redis.del(file_hash_key(file_path))
      end

      # Get all invalidation keys from index
      invalidations = @redis.zrange(invalidation_index_key, 0, -1)
      invalidations.each do |file_path|
        @redis.del("cache_invalid:#{@app_id}:#{file_path}")
      end

      # Clear indexes themselves
      @redis.del(file_index_key, invalidation_index_key, prompt_cache_index_key)
      @redis.del(change_log_key)

      Rails.logger.info "[FileChangeTracker] Cleared all tracking data for app #{@app_id}"
    end

    # Get statistics about file changes
    def get_stats
      return {} unless @redis

      begin
        # Use indexes instead of Redis.keys for performance
        file_index_key = "file_index:#{@app_id}"
        invalidation_index_key = "invalidation_index:#{@app_id}"

        stats = {
          total_tracked_files: @redis.zcard(file_index_key),
          recent_changes_1h: get_changed_files_since(1.hour.ago).count,
          recent_changes_5m: get_changed_files_since(5.minutes.ago).count,
          invalidated_caches: @redis.zcard(invalidation_index_key)
        }

        # Add stability distribution
        all_files = @redis.zrange(file_index_key, 0, -1)
        categorized = categorize_files_by_stability(all_files)

        stats[:stability_distribution] = {
          stable: categorized[:stable].count,
          active: categorized[:active].count,
          volatile: categorized[:volatile].count
        }

        stats
      rescue Redis::BaseError => e
        Rails.logger.error "[FileChangeTracker] Redis error getting stats: #{e.message}"
        {}  # Return empty stats on error
      end
    end

    private

    def file_hash_key(file_path)
      "file_hash:#{@app_id}:#{file_path}"
    end

    def change_log_key
      "file_change_log:#{@app_id}"
    end

    def add_to_file_index(file_path)
      return unless @redis

      file_index_key = "file_index:#{@app_id}"
      # Add with current timestamp as score for ordering
      @redis.zadd(file_index_key, Time.current.to_f, file_path)

      # Set TTL on index
      @redis.expire(file_index_key, CHANGE_LOG_TTL)
    end

    def add_to_invalidation_index(file_path)
      return unless @redis

      invalidation_index_key = "invalidation_index:#{@app_id}"
      # Add with current timestamp as score
      @redis.zadd(invalidation_index_key, Time.current.to_f, file_path)

      # Clean up old entries (older than 5 minutes)
      min_score = 5.minutes.ago.to_f
      @redis.zremrangebyscore(invalidation_index_key, "-inf", min_score)

      # Set TTL
      @redis.expire(invalidation_index_key, 1.hour)
    end

    def add_to_prompt_cache_index(cache_key)
      return unless @redis

      prompt_cache_index_key = "prompt_cache_index:#{@app_id}"
      @redis.zadd(prompt_cache_index_key, Time.current.to_f, cache_key)

      # Limit size and set TTL
      @redis.zremrangebyrank(prompt_cache_index_key, 0, -1001)  # Keep last 1000
      @redis.expire(prompt_cache_index_key, CHANGE_LOG_TTL)
    end

    def log_change(file_path, old_hash, new_hash)
      return unless @redis

      change_log_key = change_log_key()

      # Add to sorted set with timestamp as score
      change_entry = {
        file_path: file_path,
        old_hash: old_hash,
        new_hash: new_hash,
        timestamp: Time.current.iso8601
      }.to_json

      score = Time.current.to_f
      @redis.zadd(change_log_key, score, change_entry)

      # Trim old entries to prevent unbounded growth
      @redis.zremrangebyrank(change_log_key, 0, -CHANGE_LOG_MAX_SIZE - 1)

      # Set TTL on the log
      @redis.expire(change_log_key, CHANGE_LOG_TTL)
    end
  end
end
