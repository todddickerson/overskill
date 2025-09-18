# frozen_string_literal: true

module Ai
  # Centralized service for all AI agent tool implementations
  # This service extracts tool functionality from AppBuilderV5 to maintain cleaner separation of concerns
  # Each tool method returns a standardized response hash with :success and :content/:error keys
  class AiToolService
    attr_reader :app, :logger
    attr_accessor :line_offset_tracker

    def initialize(app, options = {})
      @app = app
      @logger = options[:logger] || Rails.logger
      @user = options[:user] || app&.team&.users&.first

      # Initialize dependent services
      @web_content_service = WebContentExtractionService.new
      @perplexity_service = PerplexityContentService.new
      @image_service = Ai::ImageGenerationService.new(app)  # Pass app context for image generation
      @search_service = Ai::SmartSearchService.new(app)

      # Line offset tracker for handling sequential line replacements
      @line_offset_tracker = nil # Will be set when processing batches of tool calls
    end

    # ========================
    # File Management Tools
    # ========================

    def write_file(file_path, content)
      return {success: false, error: "File path cannot be blank"} if file_path.blank?
      return {success: false, error: "Content cannot be blank"} if content.blank?

      # PREVENTION: Clean up escape sequences that shouldn't be in code
      if content && (content.include?('\\n') || content.include?('\\"'))
        original_content = content
        content = clean_escaped_content(content)
        if content != original_content
          @logger.warn "[AiToolService] Cleaned escape sequences in content for #{file_path}"
        end
      end

      # Handle empty content gracefully
      if content.blank?
        @logger.warn "[AiToolService] Attempting to write empty file: #{file_path}"
        content = "// Empty file\n" if file_path.match?(/\.(ts|tsx|js|jsx)$/i)
        content = "/* Empty file */\n" if file_path.match?(/\.(css|scss|sass)$/i)
        content = "<!-- Empty file -->\n" if file_path.match?(/\.html$/i)
        content = "\n" if content.blank? # Default to single newline
      end

      # Transform content to use R2 asset resolver if needed
      r2_integration = R2AssetIntegrationService.new(@app)
      transformed_content = r2_integration.transform_file_content(content, file_path)

      # Validate and fix code before saving to prevent build failures
      validated_content = transformed_content

      # Apply validation and auto-fixing based on file type
      if file_path.match?(/\.css$/i)
        # CSS validation with auto-fix
        begin
          # First pass: CodeValidator for syntax
          fixed_css = Ai::CodeValidator.validate_and_fix_css(validated_content)

          # Second pass: CssValidatorService for additional fixes
          css_validator = Ai::CssValidatorService.new(@app)
          fixed_css = css_validator.validate_and_fix_css(file_path, fixed_css)

          # Check if we actually fixed anything
          if fixed_css != validated_content
            @logger.info "[AiToolService] Auto-fixed CSS issues in #{file_path}"
            validated_content = fixed_css
          end

          # Final validation check - if still has issues, fail the tool call
          syntax_check = Ai::CodeValidator.fix_css_syntax_issues(validated_content)
          if syntax_check[:fixed]
            @logger.error "[AiToolService] CSS validation failed after auto-fix attempt for #{file_path}: #{syntax_check[:fixes].join(", ")}"
            return {success: false, error: "CSS syntax errors could not be auto-fixed: #{syntax_check[:fixes].join(", ")}"}
          end
        rescue => e
          @logger.error "[AiToolService] CSS validation error for #{file_path}: #{e.message}"
          return {success: false, error: "CSS validation failed: #{e.message}"}
        end
      elsif file_path.match?(/\.(ts|tsx|js|jsx)$/i)
        # TypeScript/JavaScript validation
        begin
          # Use TypescriptValidatorService for auto-fixing
          ts_validator = Ai::TypescriptValidatorService.new(@app)
          fixed_ts = ts_validator.validate_and_fix_typescript(file_path, validated_content)

          if fixed_ts != validated_content
            @logger.info "[AiToolService] Auto-fixed TypeScript/JavaScript issues in #{file_path}"
            validated_content = fixed_ts
          end

          # Check TypeScript validation result
          ts_result = Ai::CodeValidator.validate_typescript(validated_content, file_path)
          if !ts_result[:valid]
            @logger.error "[AiToolService] TypeScript validation failed after auto-fix for #{file_path}: #{ts_result[:errors].join(", ")}"
            return {success: false, error: "TypeScript/JavaScript errors could not be auto-fixed: #{ts_result[:errors].join(", ")}"}
          end
        rescue => e
          @logger.error "[AiToolService] TypeScript validation error for #{file_path}: #{e.message}"
          return {success: false, error: "TypeScript/JavaScript validation failed: #{e.message}"}
        end
      else
        # For other file types, use basic validation
        begin
          validated_content = Ai::CodeValidator.validate_file(transformed_content, file_path)
        rescue => e
          @logger.error "[AiToolService] Code validation failed for #{file_path}: #{e.message}"
          return {success: false, error: "Code validation failed: #{e.message}"}
        end
      end

      app_file = @app.app_files.find_or_initialize_by(path: file_path)
      app_file.team = @app.team  # Ensure team is set for new files

      # Set validated content before saving
      app_file.content = validated_content

      # Determine file type based on extension for new files
      if app_file.new_record?
        app_file.file_type = case ::File.extname(file_path).downcase
        when ".tsx", ".ts" then "typescript"
        when ".jsx", ".js" then "javascript"
        when ".css" then "css"
        when ".html" then "html"
        when ".json" then "json"
        when ".md" then "markdown"
        when ".yml", ".yaml" then "yaml"
        when ".svg" then "svg"
        when ".png", ".jpg", ".jpeg", ".gif" then "image"
        else "text"
        end
        @logger.info "[AiToolService] Creating new file: #{file_path} (type: #{app_file.file_type})"
      end

      if app_file.save
        @logger.info "[AiToolService] File written: #{file_path} (#{content.length} chars)"

        # Log if R2 transformations were applied
        if transformed_content != content
          @logger.info "[AiToolService] Applied R2 asset transformations to #{file_path}"
        end

        {success: true, content: "File #{file_path} written successfully"}
      else
        @logger.error "[AiToolService] Failed to save file #{file_path}: #{app_file.errors.full_messages.join(", ")}"
        @logger.error "[AiToolService] File details - new_record: #{app_file.new_record?}, path: #{app_file.path}, team_id: #{app_file.team_id}, app_id: #{app_file.app_id}, file_type: #{app_file.file_type}, content_length: #{app_file.content&.length}"
        {success: false, error: app_file.errors.full_messages.join(", ")}
      end
    rescue => e
      @logger.error "[AiToolService] Error writing file #{file_path}: #{e.message}"
      @logger.error "[AiToolService] Backtrace: #{e.backtrace.first(5).join("\n")}"
      {success: false, error: e.message}
    end

    def read_file(file_path, lines = nil)
      app_file = @app.app_files.find_by(path: file_path)

      # ON-DEMAND FILE CREATION: Fetch from GitHub template repository
      unless app_file
        @logger.info "[AiToolService] File not found: #{file_path}, fetching from GitHub template repository"

        app_file = create_file_from_github_template(file_path)

        unless app_file
          return {success: false, error: "File not found: #{file_path}"}
        end
      end

      if app_file
        content = app_file.content || ""
        content = apply_line_filter(content, lines) if lines
        {success: true, content: content}
      else
        {success: false, error: "File not found: #{file_path}"}
      end
    rescue => e
      @logger.error "[AiToolService] Error reading file #{file_path}: #{e.message}"
      {success: false, error: e.message}
    end

    def delete_file(file_path)
      app_file = @app.app_files.find_by(path: file_path)

      if app_file
        app_file.destroy
        @logger.info "[AiToolService] File deleted: #{file_path}"
        {success: true, content: "File #{file_path} deleted successfully"}
      else
        {success: false, error: "File not found: #{file_path}"}
      end
    rescue => e
      @logger.error "[AiToolService] Error deleting file #{file_path}: #{e.message}"
      {success: false, error: e.message}
    end

    def rename_file(old_path, new_path)
      app_file = @app.app_files.find_by(path: old_path)

      if app_file
        app_file.path = new_path
        if app_file.save
          @logger.info "[AiToolService] File renamed: #{old_path} -> #{new_path}"
          {success: true, content: "File renamed from #{old_path} to #{new_path}"}
        else
          {success: false, error: app_file.errors.full_messages.join(", ")}
        end
      else
        {success: false, error: "File not found: #{old_path}"}
      end
    rescue => e
      @logger.error "[AiToolService] Error renaming file: #{e.message}"
      {success: false, error: e.message}
    end

    def replace_file_content(args)
      file_path = args["file_path"] || args[:file_path]
      # Handle both naming conventions for search pattern
      search_pattern = args["search_pattern"] || args["search"] || args[:search_pattern] || args[:search]
      # Handle both naming conventions for line numbers
      first_line = args["first_line"] || args["first_replaced_line"] || args[:first_line] || args[:first_replaced_line]
      last_line = args["last_line"] || args["last_replaced_line"] || args[:last_line] || args[:last_replaced_line]
      # Handle both naming conventions for replacement
      replacement = args["replacement"] || args["replace"] || args[:replacement] || args[:replace]

      # PREVENTION: Clean up escape sequences that shouldn't be in code
      # This handles cases where AI might incorrectly escape newlines or quotes
      if replacement && (replacement.include?('\\n') || replacement.include?('\\"'))
        original_replacement = replacement
        replacement = clean_escaped_content(replacement)
        if replacement != original_replacement
          @logger.warn "[AiToolService] Cleaned escape sequences in replacement for #{file_path}"
        end
      end

      # Convert to integers if they're strings
      first_line = first_line.to_i
      last_line = last_line.to_i

      # Find the file, or create it on-demand from template
      file = @app.app_files.find_by(path: file_path)

      unless file
        # ON-DEMAND FILE CREATION: Fetch from GitHub template repository when AI references it
        @logger.info "[AiToolService] File not found: #{file_path}, attempting on-demand creation from GitHub template"

        file = create_file_from_github_template(file_path)

        unless file
          # If file doesn't exist in template and we have replacement content, create the file
          if replacement.present?
            @logger.info "[AiToolService] Creating new file with replacement content: #{file_path}"
            result = write_file(file_path, replacement)
            if result[:success]
              return {success: true, content: "File created: #{file_path}"}
            else
              return result
            end
          else
            @logger.error "[AiToolService] Failed to create file from GitHub template: #{file_path}"
            return {success: false, error: "File not found and could not fetch from template: #{file_path}"}
          end
        end
      end

      # Apply line offset adjustments if tracker is available
      original_first = first_line
      original_last = last_line

      if @line_offset_tracker&.tracking?(file_path)
        adjusted_first, adjusted_last = @line_offset_tracker.adjust_line_range(file_path, first_line, last_line)
        @logger.info "[AiToolService] Line numbers adjusted for #{file_path}: #{first_line}-#{last_line} -> #{adjusted_first}-#{adjusted_last}"
        first_line = adjusted_first
        last_line = adjusted_last
      end

      # Log the operation details for debugging
      @logger.info "[AiToolService] Attempting line-replace on #{file_path} lines #{first_line}-#{last_line}"

      # Use the class method instead of instance
      result = Ai::LineReplaceService.replace_lines(file, search_pattern, first_line, last_line, replacement)

      if result[:success]
        @logger.info "[AiToolService] Successfully replaced lines in #{file_path}"

        # ENHANCEMENT 2: Verify actual success vs false positive
        # Check if the result claims success but actual error occurred
        if result[:already_present] && result[:message]&.include?("already present")
          @logger.info "[AiToolService] Content already present, no changes made"
          return result
        elsif result[:fuzzy_match_used]
          @logger.info "[AiToolService] Used fuzzy matching for replacement"
          return result
        end

        # Record the replacement in the tracker if available
        if @line_offset_tracker
          # Calculate how many lines the replacement has
          replacement_lines = replacement.lines.count
          @line_offset_tracker.record_replacement(file_path, original_first, original_last, replacement_lines)
        end
      else
        @logger.warn "[AiToolService] Line-replace failed for #{file_path}: #{result[:error]}"

        # ENHANCEMENT 2: Detect specific 'unchanged' error and provide better feedback
        if result[:error]&.include?("unchanged") || result[:message]&.include?("unchanged")
          @logger.error "[AiToolService] LineReplaceService reported 'unchanged' - likely duplicate detection blocked a needed syntax fix"
          # Return enhanced error message for AI to understand
          return {
            success: false,
            error: "Line replacement blocked by duplicate detection. This may be a syntax fix that was incorrectly identified as a duplicate. Consider using more surgical targeting.",
            suggestion: "Try targeting a smaller, more specific portion of the code for replacement.",
            original_error: result[:error] || result[:message]
          }
        end

        # Try to recover by finding the pattern in nearby lines
        if result[:error].include?("Search pattern does not match")
          @logger.info "[AiToolService] Attempting to find pattern in nearby lines..."

          # Track failures per file
          @line_replace_failures ||= {}
          @line_replace_failures[file_path] ||= 0
          @line_replace_failures[file_path] += 1

          # After 3 failures on the same file, suggest os-write
          if @line_replace_failures[file_path] >= 3
            @logger.warn "[AiToolService] Multiple line-replace failures (#{@line_replace_failures[file_path]}) on #{file_path}, suggesting os-write"
            return {
              success: false,
              error: "Multiple line-replace failures on this file. The line numbers appear to be incorrect.",
              suggestion: "Use os-write to replace the entire file content instead of line-based replacement.",
              failure_count: @line_replace_failures[file_path]
            }
          end

          recovered_result = attempt_fuzzy_line_replacement(file, search_pattern, first_line, last_line, replacement)
          if recovered_result[:success]
            @logger.info "[AiToolService] Successfully recovered using fuzzy matching"
            # Reset failure count on success
            @line_replace_failures[file_path] = 0
            return recovered_result
          end
        end
      end

      result
    rescue => e
      @logger.error "[AiToolService] Error in line replace for #{file_path}: #{e.message}"
      @logger.error e.backtrace.first(5).join("\n")
      {success: false, error: e.message}
    end

    def attempt_fuzzy_line_replacement(file, search_pattern, original_first_line, original_last_line, replacement)
      # Try to find the pattern within a window around the specified lines
      window_size = 10
      file_lines = file.content.lines

      # Normalize the search pattern for comparison
      normalized_search = search_pattern.strip.downcase.gsub(/\s+/, " ")

      # IMPROVEMENT 1: First try window-based search
      start_search = [original_first_line - window_size, 1].max
      end_search = [original_last_line + window_size, file_lines.size].min

      best_match = nil
      best_score = 0

      (start_search..end_search).each do |start_line|
        (start_line..end_search).each do |end_line|
          next if end_line - start_line > original_last_line - original_first_line + 5 # Don't search too large ranges

          # Extract content for this range
          test_content = file_lines[(start_line - 1)..(end_line - 1)].join
          normalized_test = test_content.strip.downcase.gsub(/\s+/, " ")

          # Calculate similarity score
          score = calculate_similarity(normalized_search, normalized_test)

          if score > best_score && score > 0.7 # Require at least 70% similarity
            best_match = {start: start_line, end: end_line, content: test_content}
            best_score = score
          end
        end
      end

      # IMPROVEMENT 2: If window-based search fails, try content-based search across entire file
      if !best_match && search_pattern.length > 20
        @logger.info "[AiToolService] Window-based search failed, attempting content-based search across entire file"

        # Try to find exact or near-exact match anywhere in the file
        search_lines = search_pattern.lines
        if search_lines.any?
          first_search_line = search_lines.first.strip

          file_lines.each_with_index do |line, idx|
            if line.strip.include?(first_search_line) || calculate_similarity(line.strip.downcase, first_search_line.downcase) > 0.8
              # Found potential start, check if rest matches
              expected_lines = search_lines.length
              actual_content = file_lines[idx, expected_lines].join

              score = calculate_similarity(normalized_search, actual_content.strip.downcase.gsub(/\s+/, " "))

              if score > 0.65 # Lower threshold for content-based search
                best_match = {start: idx + 1, end: idx + expected_lines, content: actual_content}
                best_score = score
                @logger.info "[AiToolService] Found content-based match at lines #{best_match[:start]}-#{best_match[:end]} with #{(best_score * 100).round}% similarity"
                break
              end
            end
          end
        end
      end

      if best_match
        @logger.info "[AiToolService] Found fuzzy match at lines #{best_match[:start]}-#{best_match[:end]} with #{(best_score * 100).round}% similarity"

        # Try the replacement with the found lines
        result = Ai::LineReplaceService.replace_lines(file, best_match[:content], best_match[:start], best_match[:end], replacement)

        if result[:success] && @line_offset_tracker
          # Record the replacement with original line numbers for tracking
          replacement_lines = replacement.lines.count
          @line_offset_tracker.record_replacement(file.path, original_first_line, original_last_line, replacement_lines)
        end

        result[:fuzzy_match_used] = true if result[:success]
        result
      else
        # IMPROVEMENT 3: Provide helpful context about what's actually at those lines
        actual_content = file_lines[(original_first_line - 1)..[original_last_line - 1, file_lines.size - 1].min].join
        actual_preview = begin
          actual_content.lines.first(3).join.strip[0..100]
        rescue
          ""
        end

        @logger.warn "[AiToolService] Could not find fuzzy match for pattern"
        @logger.warn "[AiToolService] Actual content at lines #{original_first_line}-#{original_last_line}: #{actual_preview}..."

        {
          success: false,
          error: "Could not find pattern in file. The content at lines #{original_first_line}-#{original_last_line} is different from expected.",
          actual_content_preview: actual_preview,
          suggestion: "Consider using os-view to check the file content first, or use os-write to replace the entire file."
        }
      end
    end

    def calculate_similarity(str1, str2)
      # Simple Jaccard similarity for words
      words1 = str1.split(/\s+/).to_set
      words2 = str2.split(/\s+/).to_set

      return 0.0 if words1.empty? || words2.empty?

      intersection = words1 & words2
      union = words1 | words2

      intersection.size.to_f / union.size
    end

    # ========================
    # Search Tools
    # ========================

    def search_files(args)
      query = args["query"] || args[:query]
      include_pattern = args["include_pattern"] || args[:include_pattern] || "**/*"
      exclude_pattern = args["exclude_pattern"] || args[:exclude_pattern]
      case_sensitive = args["case_sensitive"] || args[:case_sensitive] || false

      results = @search_service.search_with_regex(
        query,
        include_pattern: include_pattern,
        exclude_pattern: exclude_pattern,
        case_sensitive: case_sensitive
      )

      formatted_results = results.map do |result|
        "#{result[:file]}: Line #{result[:line_number]}: #{result[:content]}"
      end.join("\n")

      {success: true, content: formatted_results}
    rescue => e
      @logger.error "[AiToolService] Error searching files: #{e.message}"
      {success: false, error: e.message}
    end

    # ========================
    # Web Research Tools
    # ========================

    def web_search(args)
      query = args["query"] || args[:query]
      num_results = args["numResults"] || args[:numResults] || 5
      category = args["category"] || args[:category]

      return {success: false, error: "Query is required"} if query.blank?

      # Use SerpAPI for web search
      api_key = ENV["SERPAPI_API_KEY"] || Rails.application.credentials.dig(:serpapi, :api_key)
      return {success: false, error: "SerpAPI key not configured"} unless api_key

      client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)

      # Add category filter if specified
      if category.present?
        case category
        when "news"
          client = GoogleSearch.new(q: query, api_key: api_key, tbm: "nws", num: num_results)
        when "github"
          query = "site:github.com #{query}"
          client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)
        when "pdf"
          query = "filetype:pdf #{query}"
          client = GoogleSearch.new(q: query, api_key: api_key, num: num_results)
        end
      end

      results = client.get_hash

      formatted_results = format_search_results(results)

      {success: true, content: formatted_results}
    rescue => e
      @logger.error "[AiToolService] Error in web search: #{e.message}"
      {success: false, error: e.message}
    end

    def fetch_webpage(url, use_cache = true)
      result = @web_content_service.extract_for_llm(url, use_cache: use_cache)

      if result[:error]
        {success: false, error: result[:error]}
      else
        content = format_webpage_content(result)
        {success: true, content: content}
      end
    rescue => e
      @logger.error "[AiToolService] Error fetching webpage: #{e.message}"
      {success: false, error: e.message}
    end

    def perplexity_research(args)
      query = args["query"] || args[:query]
      mode = args["mode"] || args[:mode] || "quick"
      max_tokens = args["max_tokens"] || args[:max_tokens] || 2000
      use_cache = args.fetch("use_cache", true)

      return {success: false, error: "Query is required"} if query.blank?

      # Map mode to appropriate method and model
      result = case mode
      when "fact_check"
        @perplexity_service.fact_check(query)
      when "deep"
        @perplexity_service.deep_research(query)
      when "research"
        @perplexity_service.extract_content_for_llm(
          query,
          model: PerplexityContentService::MODELS[:sonar_pro],
          max_tokens: max_tokens,
          use_cache: use_cache
        )
      else # 'quick'
        @perplexity_service.extract_content_for_llm(
          query,
          model: PerplexityContentService::MODELS[:sonar],
          max_tokens: max_tokens,
          use_cache: use_cache
        )
      end

      if result[:error]
        {success: false, error: result[:error]}
      else
        content = format_perplexity_response(result, mode)
        {success: true, content: content}
      end
    rescue => e
      @logger.error "[AiToolService] Error in Perplexity research: #{e.message}"
      {success: false, error: e.message}
    end

    # ========================
    # Package Management Tools
    # ========================

    def add_dependency(package)
      package_json = @app.app_files.find_or_initialize_by(path: "package.json")

      begin
        json = package_json.content.present? ? JSON.parse(package_json.content) : {}
        json["dependencies"] ||= {}

        # Parse package name and version
        if package.include?("@")
          # Use rpartition to split on the last '@' (for scoped packages like @types/node)
          name, _, version = package.rpartition("@")
          version = version.presence || "latest"
        else
          name = package
          version = "latest"
        end

        json["dependencies"][name] = version
        package_json.content = JSON.pretty_generate(json)
        package_json.save!

        @logger.info "[AiToolService] Added dependency: #{name}@#{version}"
        {success: true, content: "Added dependency: #{name}@#{version}"}
      rescue => e
        @logger.error "[AiToolService] Error adding dependency: #{e.message}"
        {success: false, error: e.message}
      end
    end

    def remove_dependency(package)
      package_json = @app.app_files.find_by(path: "package.json")
      return {success: false, error: "package.json not found"} unless package_json

      begin
        json = JSON.parse(package_json.content)

        if json["dependencies"]&.key?(package)
          json["dependencies"].delete(package)
          package_json.content = JSON.pretty_generate(json)
          package_json.save!

          @logger.info "[AiToolService] Removed dependency: #{package}"
          {success: true, content: "Removed dependency: #{package}"}
        else
          {success: false, error: "Package #{package} not found in dependencies"}
        end
      rescue => e
        @logger.error "[AiToolService] Error removing dependency: #{e.message}"
        {success: false, error: e.message}
      end
    end

    # ========================
    # Image Generation Tools
    # ========================

    def generate_image(args)
      prompt = args["prompt"] || args[:prompt]
      target_path = args["target_path"] || args[:target_path]
      width = args["width"] || args[:width] || 1024
      height = args["height"] || args[:height] || 1024
      model = args["model"] || args[:model] || "flux.schnell"

      return {success: false, error: "Prompt is required"} if prompt.blank?
      return {success: false, error: "Target path is required"} if target_path.blank?

      # Note: generate_and_save_image now returns R2 URLs
      result = @image_service.generate_and_save_image(
        prompt: prompt,
        target_path: target_path,
        width: width,
        height: height,
        model: model
      )

      if result[:success]
        @logger.info "[AiToolService] Image generated and uploaded to R2: #{target_path} -> #{result[:url]}"

        # Provide clear usage instructions with the actual R2 URL
        response = <<~MSG
          Image generated successfully!
          
          R2 URL: #{result[:url]}
          
          To use this image in your components:
          
          1. Direct img tag (simplest):
          ```tsx
          <img src="#{result[:url]}" alt="Description" />
          ```
          
          2. With LazyImage component (recommended for performance):
          ```tsx
          import LazyImage from '@/LazyImage';
          <LazyImage src="#{result[:url]}" alt="Description" className="w-full h-auto" />
          ```
          
          3. As CSS background:
          ```css
          background-image: url('#{result[:url]}');
          ```
          
          4. Using imageUrls (auto-generated after image creation):
          ```tsx
          import { imageUrls } from '@/imageUrls';
          <img src={imageUrls['#{::File.basename(target_path)}']} alt="Description" />
          ```
          
          Note: The imageUrls.js file is automatically created with all generated image URLs.
        MSG

        {
          success: true,
          content: response,
          url: result[:url],
          path: target_path,
          storage_method: "r2"
        }
      else
        {success: false, error: result[:error]}
      end
    rescue => e
      @logger.error "[AiToolService] Error generating image: #{e.message}"
      {success: false, error: e.message}
    end

    def edit_image(args)
      image_paths = args["image_paths"] || args[:image_paths]
      prompt = args["prompt"] || args[:prompt]
      target_path = args["target_path"] || args[:target_path]
      strength = args["strength"] || args[:strength] || 0.8

      return {success: false, error: "Image paths are required"} if image_paths.blank?
      return {success: false, error: "Prompt is required"} if prompt.blank?
      return {success: false, error: "Target path is required"} if target_path.blank?

      # Load source images
      source_images = image_paths.map do |path|
        file = @app.app_files.find_by(path: path)
        return {success: false, error: "Image not found: #{path}"} unless file
        file.content
      end

      result = @image_service.edit_image(
        images: source_images,
        prompt: prompt,
        target_path: target_path,
        strength: strength,
        app: @app
      )

      if result[:success]
        @logger.info "[AiToolService] Image edited: #{target_path}"
        {success: true, content: "Image edited and saved to #{target_path}"}
      else
        {success: false, error: result[:error]}
      end
    rescue => e
      @logger.error "[AiToolService] Error editing image: #{e.message}"
      {success: false, error: e.message}
    end

    # ========================
    # Utility Tools
    # ========================

    def download_to_repo(source_url, target_path)
      return {success: false, error: "Source URL is required"} if source_url.blank?
      return {success: false, error: "Target path is required"} if target_path.blank?

      require "open-uri"
      require "net/http"

      begin
        uri = URI(source_url)
        # Add timeout to prevent hanging
        response = Net::HTTP.start(uri.host, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 10,
          read_timeout: 30) do |http|
          request = Net::HTTP::Get.new(uri)
          http.request(request)
        end

        if response.is_a?(Net::HTTPSuccess)
          content = response.body.force_encoding("UTF-8")

          app_file = @app.app_files.find_or_initialize_by(path: target_path)
          app_file.content = content
          app_file.save!

          @logger.info "[AiToolService] Downloaded #{source_url} to #{target_path}"
          {success: true, content: "File downloaded to #{target_path}"}
        else
          {success: false, error: "Failed to download: HTTP #{response.code}"}
        end
      rescue => e
        @logger.error "[AiToolService] Error downloading file: #{e.message}"
        {success: false, error: e.message}
      end
    end

    def fetch_website(url, formats = "markdown")
      # This is a placeholder - would need proper implementation
      # For now, delegate to webpage fetching
      fetch_webpage(url, true)
    end

    # TODO: Implement client side console log reading for preview frame
    def read_console_logs(search = nil)
      # Placeholder - would need integration with actual console logs
      {success: true, content: "Console logs not available in this context"}
    end

    def read_network_requests(search = nil)
      # Placeholder - would need integration with actual network monitoring
      {success: true, content: "Network requests not available in this context"}
    end

    def read_project_analytics(args)
      # Placeholder - would need integration with analytics service
      {success: true, content: "Analytics feature coming soon"}
    end

    def apply_line_filter(content, lines)
      return content if lines.blank?

      line_array = content.lines
      ranges = parse_line_ranges(lines)

      selected_lines = []
      ranges.each do |range|
        start_line = [range[:start] - 1, 0].max
        end_line = [range[:end], line_array.length].min
        selected_lines.concat(line_array[start_line...end_line])
      end

      selected_lines.join
    end

    def parse_line_ranges(lines_str)
      ranges = []
      lines_str.split(",").each do |range_str|
        range_str = range_str.strip
        if range_str.include?("-")
          start_line, end_line = range_str.split("-").map(&:to_i)
          ranges << {start: start_line, end: end_line}
        else
          line_num = range_str.to_i
          ranges << {start: line_num, end: line_num}
        end
      end
      ranges
    end

    def format_search_results(results)
      return "No results found" if results["organic_results"].blank?

      formatted = []
      results["organic_results"].each_with_index do |result, i|
        formatted << "#{i + 1}. #{result["title"]}"
        formatted << "   URL: #{result["link"]}"
        formatted << "   #{result["snippet"]}"
        formatted << ""
      end

      formatted.join("\n")
    end

    def format_webpage_content(result)
      lines = []
      lines << "=== Webpage Content Extracted ==="
      lines << "URL: #{result[:url]}"
      lines << "Title: #{result[:title]}" if result[:title].present?
      lines << "Word Count: #{result[:word_count]}"
      lines << "Character Count: #{result[:char_count]}"
      lines << "Extracted At: #{result[:extracted_at]}"
      lines << "⚠️ Content was truncated due to length" if result[:truncated]
      lines << ""
      lines << "=== Content ==="
      lines << result[:content]

      lines.join("\n")
    end

    def format_perplexity_response(result, mode)
      lines = []
      lines << "=== Perplexity Research Result ==="
      lines << "Query: #{result[:source] || result[:topic]}"
      lines << "Mode: #{mode}"
      lines << "Model: #{result[:model]}" if result[:model]
      lines << "Word Count: #{result[:word_count]}"
      lines << "Has Citations: #{result[:has_citations] ? "Yes" : "No"}"
      lines << "Estimated Cost: $#{result[:estimated_cost]}" if result[:estimated_cost]
      lines << "Timestamp: #{result[:extracted_at] || result[:researched_at]}"
      lines << ""
      lines << "=== Content ==="
      lines << (result[:content] || result[:research_report])

      lines.join("\n")
    end

    # ========================
    # App Management Tools
    # ========================

    def rename_app(args)
      @logger.info "[AiToolService] Renaming app with args: #{args.inspect}"

      new_name = args["name"] || args[:name]
      custom_subdomain = args["subdomain"] || args[:subdomain]

      return {success: false, error: "Name is required"} if new_name.blank?

      begin
        old_name = @app.name
        old_subdomain = @app.subdomain

        # Update the app name
        @app.update!(name: new_name)

        # Use existing App model method to handle subdomain generation
        if custom_subdomain.present?
          # If custom subdomain provided, use update_subdomain! method
          result = @app.update_subdomain!(custom_subdomain)
          unless result[:success]
            # return { success: false, error: "Failed to update subdomain: #{result[:error]}" } # don't return error, just note the subdomain stayed the same
            final_subdomain = @app.subdomain
          end
          final_subdomain = result[:subdomain] || custom_subdomain
        else
          # Otherwise regenerate from name using existing model method
          result = @app.regenerate_subdomain_from_name!(redeploy_if_published: false)
          unless result[:success]
            return {success: false, error: "Failed to generate subdomain: #{result[:error]}"}
          end
          final_subdomain = result[:subdomain]
        end

        @logger.info "[AiToolService] App renamed from '#{old_name}' to '#{new_name}' (subdomain: #{old_subdomain} -> #{final_subdomain})"

        {
          success: true,
          content: "App successfully renamed to '#{new_name}' with subdomain '#{final_subdomain}'",
          old_name: old_name,
          new_name: new_name,
          old_subdomain: old_subdomain,
          new_subdomain: final_subdomain,
          preview_url: "https://preview--#{final_subdomain}.overskill.com",
          production_url: "https://#{final_subdomain}.overskill.com"
        }
      rescue => e
        @logger.error "[AiToolService] Failed to rename app: #{e.message} #{e.backtrace.join("\n")}"
        {success: false, error: "Failed to rename app: #{e.message}"}
      end
    end

    def generate_app_logo(args)
      style = args["style"] || args[:style] || "modern"
      colors = args["colors"] || args[:colors]

      begin
        # Build a custom prompt if style or colors are specified
        if style != "modern" || colors.present?
          # Build custom logo prompt
          prompt_parts = [
            "Create a #{style} app icon logo",
            "for #{@app.name}",
            "transparent background",
            "no text",
            "simple geometric shapes",
            "high contrast"
          ]

          # Add color preference if specified
          prompt_parts << colors if colors.present?

          # Add style-specific elements
          case style
          when "minimalist"
            prompt_parts << "ultra simple" << "clean lines"
          when "playful"
            prompt_parts << "fun" << "rounded shapes" << "bright colors"
          when "professional"
            prompt_parts << "corporate" << "serious" << "trustworthy"
          when "bold"
            prompt_parts << "strong" << "impactful" << "thick lines"
          when "elegant"
            prompt_parts << "sophisticated" << "refined" << "premium feel"
          else # modern
            prompt_parts << "contemporary" << "tech-forward" << "innovative"
          end

          custom_prompt = prompt_parts.join(", ")
        else
          custom_prompt = nil
        end

        # Use the existing LogoGeneratorService
        logo_service = Ai::LogoGeneratorService.new(@app)

        result = if custom_prompt
          # Regenerate with custom prompt
          logo_service.regenerate_logo(custom_prompt)
        else
          # Generate with default behavior
          logo_service.generate_logo
        end

        if result[:success]
          # Mark logo as generated
          @app.update!(logo_generated_at: Time.current)

          @logger.info "[AiToolService] Logo generated for app '#{@app.name}'"

          # Broadcast navigation update to refresh logo in UI
          Turbo::StreamsChannel.broadcast_replace_to(
            "app_#{@app.id}",
            target: "app_navigation_#{@app.id}",
            partial: "account/app_editors/app_navigation",
            locals: {app: @app}
          )

          {
            success: true,
            content: "Logo successfully generated for '#{@app.name}'",
            style: style,
            prompt_used: custom_prompt || "Default logo generation"
          }
        else
          {success: false, error: result[:error]}
        end
      rescue => e
        @logger.error "[AiToolService] Failed to generate logo: #{e.message}"
        {success: false, error: "Failed to generate logo: #{e.message}"}
      end
    end

    private

    def create_file_from_github_template(file_path)
      # Authenticate with GitHub App
      authenticator = Deployment::GithubAppAuthenticator.new
      token = authenticator.get_installation_token("Overskill-apps")

      unless token
        @logger.error "[AiToolService] Failed to get GitHub installation token"
        return nil
      end

      # Fetch file from GitHub template repository with timeout
      response = HTTParty.get(
        "https://api.github.com/repos/Overskill-apps/overskill-vite-template/contents/#{file_path}",
        headers: {
          "Authorization" => "Bearer #{token}",
          "Accept" => "application/vnd.github.v3+json"
        },
        timeout: 15
      )

      if response.code == 200
        # Decode base64 content from GitHub
        content = Base64.decode64(response["content"])

        # Determine file type based on extension
        file_type = case ::File.extname(file_path).downcase
        when ".tsx", ".ts" then "typescript"
        when ".jsx", ".js" then "javascript"
        when ".css" then "css"
        when ".html" then "html"
        when ".json" then "json"
        when ".md" then "markdown"
        when ".yml", ".yaml" then "yaml"
        when ".svg" then "svg"
        when ".png", ".jpg", ".jpeg", ".gif" then "image"
        else "text"
        end

        # Create the AppFile
        # Build without content first to establish associations
        app_file = @app.app_files.build(
          path: file_path,
          team: @app.team,
          file_type: file_type
        )

        # Save to establish associations
        app_file.save!

        # Now set content after associations are established
        app_file.content = content
        app_file.save!

        @logger.info "[AiToolService] ✅ Created file on-demand from GitHub: #{file_path} (#{content.length} chars)"
        app_file
      elsif response.code == 404
        @logger.warn "[AiToolService] File not found in GitHub template: #{file_path}"
        nil
      else
        @logger.error "[AiToolService] GitHub API error: #{response.code} - #{response.message}"
        nil
      end
    rescue => e
      @logger.error "[AiToolService] Error fetching from GitHub: #{e.message}"
      @logger.error e.backtrace.first(5).join("\n")
      nil
    end

    def clean_escaped_content(content)
      # This method cleans up improperly escaped content that can break code
      # Common issue: AI responses that include literal \n or \" in code

      # Don't clean if it looks like intentional JSON or string content
      return content if content.include?('"\\n"') || content.include?("'\\n'")

      # Check if this looks like code with imports/requires
      is_code = content.match?(/^(import |export |const |let |var |function |class |interface |type |from |require\()/m)

      if is_code
        # For code files, literal \n should be actual newlines
        # But we need to be careful not to break intentional escape sequences in strings

        # Split by lines to process each separately
        lines = content.split(/(?<!\\)\\n/)

        # Process each line
        processed_lines = lines.map do |line|
          # Fix escaped quotes that aren't inside strings
          # This regex looks for \" that aren't preceded by a quote start
          line.gsub(/(?<!["'])\\"/, '"')
        end

        # Join with actual newlines
        processed_lines.join("\n")
      else
        # For non-code content, be more conservative
        content
      end
    end
  end
end
