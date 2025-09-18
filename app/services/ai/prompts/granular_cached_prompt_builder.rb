# frozen_string_literal: true

module Ai
  module Prompts
    # File-level granular caching for optimal Anthropic API cost savings
    # Extends CachedPromptBuilder to cache individual files instead of monolithic blocks
    # Allows selective cache invalidation when specific files change
    class GranularCachedPromptBuilder < CachedPromptBuilder
      MAX_CACHE_BREAKPOINTS = 4
      MIN_TOKENS_FOR_CACHE = 1024  # Anthropic minimum
      MIN_CHARS_FOR_CACHE = 4096  # ~1024 tokens at 4 chars/token

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

        # Block 1: Base prompt and instructions (1 hour cache)
        # Agent prompt rarely changes during a session
        if @base_prompt.present? && @base_prompt.length > MIN_CHARS_FOR_CACHE
          system_blocks << {
            type: "text",
            text: @base_prompt,
            cache_control: {type: "ephemeral", ttl: "1h"}
          }
          block_metadata << {type: "base_prompt", cached: true, ttl: "1h"}
        end

        # Block 2: Essential files (30 min cache)
        # Core files like index.css, App.tsx, main.tsx
        essential_files = file_groups[:stable] + file_groups[:semi_stable]
        if essential_files.any? && should_cache_group?(essential_files)
          block = build_cached_file_block(
            essential_files,
            "essential_files",
            cache_ttl: "1h"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "essential")
        end

        # Block 3: Predicted UI components (5 min cache)
        # Components selected based on user request
        component_files = file_groups[:active].select { |f| f.path.include?("components/ui/") }
        if component_files.any? && should_cache_group?(component_files)
          block = build_cached_file_block(
            component_files,
            "predicted_components",
            cache_ttl: "5m"
          )
          system_blocks << block
          block_metadata << extract_block_metadata(block, "components")
        end

        # Block 4: Dynamic context (no cache)
        # Recently changed files and user-specific content
        dynamic_files = file_groups[:volatile] + file_groups[:active].reject { |f| f.path.include?("components/ui/") }
        if dynamic_files.any? || @context_data.any?
          dynamic_content = []

          if dynamic_files.any?
            dynamic_content << format_files_as_context(dynamic_files, "dynamic_files")
          end

          if @context_data.any?
            dynamic_content << build_useful_context
          end

          if dynamic_content.any?
            system_blocks << {
              type: "text",
              text: dynamic_content.join("\n\n")
            }
            block_metadata << extract_block_metadata({text: dynamic_content.join}, "dynamic")
          end
        end

        # Ensure we don't exceed max breakpoints
        if system_blocks.length > MAX_CACHE_BREAKPOINTS
          # Merge the last blocks if we exceed limit
          Rails.logger.warn "[GRANULAR_CACHE] Merging blocks to stay within #{MAX_CACHE_BREAKPOINTS} limit"
          while system_blocks.length > MAX_CACHE_BREAKPOINTS
            last_block = system_blocks.pop
            system_blocks.last[:text] += "\n\n#{last_block[:text]}"
            # Remove cache control from merged block if dynamic content was added
            if last_block[:cache_control].nil?
              system_blocks.last.delete(:cache_control)
            end
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

        # Use character threshold for simpler calculation
        total_size >= MIN_CHARS_FOR_CACHE
      end

      def is_stable_file?(path)
        # Config and core template files that rarely change
        path.match?(/^(package\.json|tailwind\.config\.ts|vite\.config\.ts|tsconfig\.json)$/) ||
          path.match?(/\.(lock|gemspec)$/)
      end

      def is_library_file?(path)
        # Essential files that change occasionally
        path.match?(/^src\/(index\.css|main\.tsx|App\.tsx)$/) ||
          path.match?(/^index\.html$/)
      end

      def is_app_logic?(path)
        # UI components and pages that might be needed
        path.match?(%r{^src/(components/ui/|pages/)}) &&
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
        cache_ratio = (total_tokens > 0) ? (cached_tokens / total_tokens * 100).round(1) : 0

        Rails.logger.info "[GRANULAR_CACHE] Cache efficiency: #{cache_ratio}% of tokens cached"
      end
    end
  end
end
