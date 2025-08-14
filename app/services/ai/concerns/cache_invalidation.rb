module Ai
  module Concerns
    # Cache invalidation hooks for file modification tools
    # Ensures cache is busted whenever AI modifies files
    module CacheInvalidation
      extend ActiveSupport::Concern
      
      included do
        # Setup alias method chains when included
        # These need to be set up at the instance level, not class level
        if method_defined?(:write_file)
          alias_method :write_file_without_cache_invalidation, :write_file
          alias_method :write_file, :write_file_with_cache_invalidation
        end
        
        if method_defined?(:replace_file_content)
          alias_method :replace_file_content_without_cache_invalidation, :replace_file_content
          alias_method :replace_file_content, :replace_file_content_with_cache_invalidation
        end
        
        if method_defined?(:delete_file)
          alias_method :delete_file_without_cache_invalidation, :delete_file
          alias_method :delete_file, :delete_file_with_cache_invalidation
        end
        
        if method_defined?(:rename_file)
          alias_method :rename_file_without_cache_invalidation, :rename_file
          alias_method :rename_file, :rename_file_with_cache_invalidation
        end
      end
      
      private
      
      def setup_file_tracker
        @file_tracker ||= FileChangeTracker.new(@app.id) if @app
      end
      
      # Hook into write_file to track changes
      def write_file_with_cache_invalidation(file_path, content)
        result = write_file_without_cache_invalidation(file_path, content)
        
        if result[:success] && @file_tracker
          # Track the file change
          changed = @file_tracker.track_file_change(file_path, content)
          
          if changed
            Rails.logger.info "[CACHE_INVALIDATION] File modified via os-write: #{file_path}"
            invalidate_prompt_caches_for_file(file_path)
          end
        end
        
        result
      end
      
      # Hook into replace_file_content to track changes
      def replace_file_content_with_cache_invalidation(args)
        result = replace_file_content_without_cache_invalidation(args)
        
        if result[:success] && @file_tracker
          file_path = args['file_path'] || args[:file_path]
          file = @app.app_files.find_by(path: file_path)
          
          if file
            changed = @file_tracker.track_file_change(file_path, file.content)
            
            if changed
              Rails.logger.info "[CACHE_INVALIDATION] File modified via os-line-replace: #{file_path}"
              invalidate_prompt_caches_for_file(file_path)
            end
          end
        end
        
        result
      end
      
      # Hook into delete_file to track deletions
      def delete_file_with_cache_invalidation(file_path)
        result = delete_file_without_cache_invalidation(file_path)
        
        if result[:success] && @file_tracker
          Rails.logger.info "[CACHE_INVALIDATION] File deleted: #{file_path}"
          invalidate_prompt_caches_for_file(file_path)
          
          # Clear the file hash since it's deleted
          clear_file_tracking(file_path)
        end
        
        result
      end
      
      # Hook into rename_file to track renames
      def rename_file_with_cache_invalidation(old_path, new_path)
        result = rename_file_without_cache_invalidation(old_path, new_path)
        
        if result[:success] && @file_tracker
          Rails.logger.info "[CACHE_INVALIDATION] File renamed: #{old_path} -> #{new_path}"
          
          # Invalidate caches for both paths
          invalidate_prompt_caches_for_file(old_path)
          invalidate_prompt_caches_for_file(new_path)
          
          # Clear tracking for old path
          clear_file_tracking(old_path)
          
          # Track the new file
          file = @app.app_files.find_by(path: new_path)
          if file
            @file_tracker.track_file_change(new_path, file.content)
          end
        end
        
        result
      end
      
      # Invalidate any cached prompts that contain this file
      def invalidate_prompt_caches_for_file(file_path)
        return unless @file_tracker
        
        # Use the file tracker's invalidation
        @file_tracker.invalidate_file_cache(file_path)
        
        # Also clear any app-level context cache
        context_cache = ContextCacheService.new(@app)
        context_cache.clear_app_cache(@app.id) if rand < 0.1  # 10% chance to do full clear
      end
      
      # Clear file tracking data
      def clear_file_tracking(file_path)
        return unless @file_tracker
        
        # Remove the file hash from tracking
        redis = Redis.new(url: Rails.application.config_for(:redis)&.dig(:url) || ENV['REDIS_URL'])
        redis.del("file_hash:#{@app.id}:#{file_path}")
      rescue => e
        Rails.logger.warn "[CACHE_INVALIDATION] Failed to clear tracking for #{file_path}: #{e.message}"
      end
      
      # Check if any tracked files have changed externally
      def detect_external_changes
        return [] unless @file_tracker
        
        changed_files = []
        
        @app.app_files.each do |file|
          current_hash = Digest::SHA256.hexdigest(file.content)
          
          # Check if this differs from tracked hash
          redis = Redis.new(url: Rails.application.config_for(:redis)&.dig(:url) || ENV['REDIS_URL'])
          tracked_hash = redis.get("file_hash:#{@app.id}:#{file.path}")
          
          if tracked_hash && tracked_hash != current_hash
            changed_files << file.path
            # Update tracking
            @file_tracker.track_file_change(file.path, file.content)
          end
        end
        
        if changed_files.any?
          Rails.logger.info "[CACHE_INVALIDATION] Detected external changes to #{changed_files.count} files"
        end
        
        changed_files
      rescue => e
        Rails.logger.warn "[CACHE_INVALIDATION] Failed to detect external changes: #{e.message}"
        []
      end
      
    end
  end
end