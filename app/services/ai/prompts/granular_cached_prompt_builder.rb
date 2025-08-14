# frozen_string_literal: true

module Ai
  module Prompts
    # File-level granular caching for optimal Anthropic API cost savings
    # Extends CachedPromptBuilder to cache individual files instead of monolithic blocks
    # Allows selective cache invalidation when specific files change
    class GranularCachedPromptBuilder < CachedPromptBuilder
      MAX_CACHE_BREAKPOINTS = 4
      MIN_TOKENS_FOR_CACHE = 1024  # Anthropic minimum
      
      attr_reader :app_id, :file_tracker
      
      def initialize(base_prompt:, template_files: [], context_data: {}, app_id: nil)
        super(base_prompt: base_prompt, template_files: template_files, context_data: context_data)
        @app_id = app_id
        @file_tracker = FileChangeTracker.new(app_id) if app_id
      end
      
      # Build system prompt with file-level granular caching
      # Returns array format with up to 4 cache breakpoints
      def build_granular_system_prompt
        system_blocks = []
        
        # Track which files go into which blocks for debugging
        block_metadata = []
        
        # Categorize files by stability and size
        file_groups = categorize_files_for_caching(@template_files)
        
        # Log categorization for debugging
        log_file_categorization(file_groups)
        
        # Block 1: Core stable files (1 hour cache)
        # These rarely change - config, templates, shared components
        if file_groups[:stable].any? && should_cache_group?(file_groups[:stable])
          block = build_cached_file_block(
            file_groups[:stable],
            "stable_core_files",
            cache_ttl: "1h"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "stable")
        end
        
        # Block 2: Semi-stable files (30 min cache)  
        # Library files, dependencies that change occasionally
        if file_groups[:semi_stable].any? && should_cache_group?(file_groups[:semi_stable])
          block = build_cached_file_block(
            file_groups[:semi_stable],
            "library_dependencies",
            cache_ttl: "30m"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "semi_stable")
        end
        
        # Block 3: Active development files (5 min cache)
        # App logic that changes frequently but not every request
        if file_groups[:active].any? && should_cache_group?(file_groups[:active])
          block = build_cached_file_block(
            file_groups[:active],
            "app_logic",
            cache_ttl: "5m"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "active")
        end
        
        # Block 4: Recently changed files (no cache)
        # Files that were just modified - always send fresh
        if file_groups[:volatile].any?
          block = build_uncached_file_block(
            file_groups[:volatile],
            "recently_changed"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "volatile")
        end
        
        # Add base prompt if we have room
        if system_blocks.length < MAX_CACHE_BREAKPOINTS && @base_prompt.present?
          system_blocks << {
            type: "text",
            text: @base_prompt,
            cache_control: { type: "ephemeral", ttl: "1h" }
          }
          block_metadata << { type: "base_prompt", cached: true }
        elsif @base_prompt.present?
          # Append to last block if no room for separate breakpoint
          system_blocks.last[:text] += "\n\n#{@base_prompt}"
        end
        
        # Add dynamic context (never cached)
        if @context_data.any?
          context_block = {
            type: "text",
            text: build_useful_context
          }
          
          # Merge with last block if at max breakpoints
          if system_blocks.length >= MAX_CACHE_BREAKPOINTS
            system_blocks.last[:text] += "\n\n#{context_block[:text]}"
          else
            system_blocks << context_block
          end
        end
        
        # Log final structure
        log_cache_structure(system_blocks, block_metadata)
        
        system_blocks
      end
      
      # Fallback to monolithic caching when granular not available
      def build_system_prompt_array
        if @app_id && @file_tracker
          build_granular_system_prompt
        else
          super  # Fall back to parent implementation
        end
      end
      
      private
      
      def categorize_files_for_caching(files)
        return default_categorization(files) unless @file_tracker
        
        # Get stability scores and recent changes
        stability_scores = {}
        recent_changes = @file_tracker.get_changed_files_since(5.minutes.ago)
        
        files.each do |file|
          stability_scores[file.path] = @file_tracker.get_stability_score(file.path)
        end
        
        categorized = {
          stable: [],       # Score >= 8, rarely changes
          semi_stable: [],  # Score 5-7, occasional changes
          active: [],       # Score 2-4, frequent changes
          volatile: []      # Recently changed or score < 2
        }
        
        files.each do |file|
          score = stability_scores[file.path]
          
          # Recently changed files are always volatile
          if recent_changes.include?(file.path)
            categorized[:volatile] << file
          elsif score >= 8
            categorized[:stable] << file
          elsif score >= 5
            categorized[:semi_stable] << file  
          elsif score >= 2
            categorized[:active] << file
          else
            categorized[:volatile] << file
          end
        end
        
        # Sort each group by size (larger first for better cache efficiency)
        categorized.each do |key, group|
          categorized[key] = group.sort_by { |f| -f.content.length }
        end
        
        categorized
      end
      
      def default_categorization(files)
        # Fallback categorization based on file paths
        categorized = {
          stable: [],
          semi_stable: [],
          active: [],
          volatile: []
        }
        
        files.each do |file|
          if is_stable_file?(file.path)
            categorized[:stable] << file
          elsif is_library_file?(file.path)
            categorized[:semi_stable] << file
          elsif is_app_logic?(file.path)
            categorized[:active] << file
          else
            categorized[:volatile] << file
          end
        end
        
        categorized
      end
      
      def build_cached_file_block(files, label, cache_ttl:)
        content = format_files_as_context(files, label)
        
        # Track file changes for cache busting
        if @file_tracker
          files.each do |file|
            @file_tracker.track_file_change(file.path, file.content)
          end
        end
        
        {
          type: "text",
          text: content,
          cache_control: { 
            type: "ephemeral",
            ttl: cache_ttl
          }
        }
      end
      
      def build_uncached_file_block(files, label)
        content = format_files_as_context(files, label)
        
        {
          type: "text",
          text: content
        }
      end
      
      def format_files_as_context(files, label)
        # Each file wrapped individually for granular context
        file_sections = files.map do |file|
          <<~FILE
          <useful-context file="#{file.path}" type="#{detect_file_type(file.path)}">
          ```#{detect_language(file.path)}
          #{file.content}
          ```
          </useful-context>
          FILE
        end
        
        <<~CONTENT
        <!-- #{label}: #{files.count} files -->
        #{file_sections.join("\n")}
        CONTENT
      end
      
      def should_cache_group?(files)
        # Only cache if group is large enough to benefit
        total_size = files.sum { |f| f.content.length }
        
        # Estimate tokens (roughly 3.5 chars per token)
        estimated_tokens = total_size / 3.5
        
        estimated_tokens >= MIN_TOKENS_FOR_CACHE
      end
      
      def is_stable_file?(path)
        # Config, templates, shared components
        path.match?(%r{^(config/|lib/|templates/|shared/|app/templates/)}) ||
        path.match?(/\.(lock|gemspec)$/)
      end
      
      def is_library_file?(path)
        # Dependencies, vendor code
        path.match?(%r{^(node_modules/|vendor/|packages/)}) ||
        path.match?(/package\.json$|Gemfile$/)
      end
      
      def is_app_logic?(path)
        # Application code
        path.match?(%r{^(app/|src/|components/)}) &&
        !path.match?(/\.(test|spec)\./)
      end
      
      def detect_file_type(path)
        case path
        when /\.(ts|tsx)$/ then "typescript"
        when /\.(js|jsx)$/ then "javascript"
        when /\.rb$/ then "ruby"
        when /\.py$/ then "python"
        when /\.(yml|yaml)$/ then "yaml"
        when /\.json$/ then "json"
        when /\.(css|scss|sass)$/ then "styles"
        when /\.(html|erb)$/ then "template"
        else "text"
        end
      end
      
      def extract_block_metadata(block, category)
        {
          category: category,
          cached: block[:cache_control].present?,
          ttl: block.dig(:cache_control, :ttl),
          size: block[:text]&.length || 0,
          estimated_tokens: (block[:text]&.length || 0) / 3.5
        }
      end
      
      def log_file_categorization(file_groups)
        Rails.logger.info "[GRANULAR_CACHE] File categorization for app #{@app_id}:"
        
        file_groups.each do |category, files|
          total_size = files.sum { |f| f.content.length }
          Rails.logger.info "  #{category}: #{files.count} files, #{total_size} chars"
          
          if ENV["DEBUG_CACHE"] == "true"
            files.first(3).each do |file|
              Rails.logger.info "    - #{file.path} (#{file.content.length} chars)"
            end
          end
        end
      end
      
      def log_cache_structure(blocks, metadata)
        Rails.logger.info "[GRANULAR_CACHE] Final cache structure:"
        Rails.logger.info "  Total blocks: #{blocks.count}"
        Rails.logger.info "  Cached blocks: #{blocks.count { |b| b[:cache_control].present? }}"
        
        metadata.each_with_index do |meta, idx|
          cache_status = meta[:cached] ? "CACHED (#{meta[:ttl]})" : "UNCACHED"
          Rails.logger.info "  Block #{idx + 1}: #{meta[:category]} - #{cache_status} - #{meta[:estimated_tokens].to_i} tokens"
        end
        
        # Calculate cache efficiency
        total_tokens = metadata.sum { |m| m[:estimated_tokens] || 0 }
        cached_tokens = metadata.select { |m| m[:cached] }.sum { |m| m[:estimated_tokens] || 0 }
        cache_ratio = total_tokens > 0 ? (cached_tokens / total_tokens * 100).round(1) : 0
        
        Rails.logger.info "[GRANULAR_CACHE] Cache efficiency: #{cache_ratio}% of tokens cached"
      end
    end
  end
end