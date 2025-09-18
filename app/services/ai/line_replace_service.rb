# PHASE 1 ENHANCEMENT: Line-Based Replacement Service
# Provides surgical code edits like Lovable's lov-line-replace tool
# Reduces token usage by 90% for small updates vs full file rewrites

module Ai
  class LineReplaceService
    include Rails.application.routes.url_helpers

    attr_reader :file, :search_lines, :replace_content, :line_range

    def initialize(file, search_pattern, first_line, last_line, replacement)
      @file = file
      @search_pattern = search_pattern
      @first_line = first_line
      @last_line = last_line
      @replacement = replacement
      @original_content = file.content
      @lines = @original_content.lines
    end

    def self.replace_lines(file, search_pattern, first_line, last_line, replacement)
      service = new(file, search_pattern, first_line, last_line, replacement)
      service.execute
    end

    def execute
      Rails.logger.info "[LineReplaceService] Starting line-based replacement in #{file.path}"
      Rails.logger.info "[LineReplaceService] Target lines #{@first_line}-#{@last_line}"
      Rails.logger.info "[LineReplaceService] Search pattern (#{@search_pattern.bytesize} bytes): #{@search_pattern[0..100].inspect}#{"..." if @search_pattern.length > 100}"
      Rails.logger.info "[LineReplaceService] Replacement (#{@replacement.bytesize} bytes): #{@replacement[0..100].inspect}#{"..." if @replacement.length > 100}"

      begin
        # Validate line numbers
        return error_result("Invalid line range") unless valid_line_range?

        # Check if replacement content is already present (prevent duplicates)
        if replacement_already_present?
          Rails.logger.info "[LineReplaceService] Replacement content already exists in file, skipping to prevent duplication"
          return {
            success: true,
            message: "Content already present in file (no changes needed)",
            already_present: true,
            new_content: @original_content
          }
        end

        # Extract content to replace
        target_content = extract_target_content

        # Check if search pattern matches (with ellipsis support)
        unless pattern_matches?(target_content)
          Rails.logger.warn "[LineReplaceService] Pattern mismatch in #{file.path}"
          Rails.logger.warn "[LineReplaceService] Expected pattern (#{@search_pattern.bytesize} bytes): #{@search_pattern[0..200].inspect}"
          Rails.logger.warn "[LineReplaceService] Actual content (#{target_content.bytesize} bytes): #{target_content[0..200].inspect}"

          # Enhanced debug logging for pattern mismatch
          min_len = [@search_pattern.length, target_content.length].min
          first_diff_index = (0...min_len).find { |i| @search_pattern[i] != target_content[i] }
          if first_diff_index
            Rails.logger.warn "[LineReplaceService] First difference at position #{first_diff_index}: expected #{@search_pattern[first_diff_index].inspect}, got #{target_content[first_diff_index].inspect}"
            # Show context around the difference
            context_start = [first_diff_index - 20, 0].max
            context_end = [first_diff_index + 20, min_len].min
            Rails.logger.warn "[LineReplaceService] Context around difference:"
            Rails.logger.warn "[LineReplaceService]   Expected: #{@search_pattern[context_start...context_end].inspect}"
            Rails.logger.warn "[LineReplaceService]   Actual:   #{target_content[context_start...context_end].inspect}"
          elsif @search_pattern.length != target_content.length
            Rails.logger.warn "[LineReplaceService] Length mismatch: pattern is #{@search_pattern.length} chars, content is #{target_content.length} chars"
            # Show what's different at the end
            if @search_pattern.length > target_content.length
              Rails.logger.warn "[LineReplaceService] Pattern has extra: #{@search_pattern[target_content.length..].inspect}"
            else
              Rails.logger.warn "[LineReplaceService] Content has extra: #{target_content[@search_pattern.length..].inspect}"
            end
          end

          # Check if the replacement might already be there
          if content_seems_already_replaced?
            Rails.logger.info "[LineReplaceService] Content appears to already have been replaced, allowing as success"
            return {
              success: true,
              message: "Content appears to already be updated",
              fuzzy_match_used: true,
              new_content: @original_content
            }
          end

          return error_result("Search pattern does not match target lines")
        end

        # Perform the replacement
        new_content = perform_replacement

        # Validate the new content
        validation = validate_replacement(new_content)
        return error_result(validation[:error]) unless validation[:valid]

        # Update the file
        @file.update!(
          content: new_content,
          size_bytes: new_content.bytesize
        )

        # Calculate statistics
        stats = calculate_stats(new_content)

        Rails.logger.info "[LineReplaceService] Successfully replaced lines #{@first_line}-#{@last_line}"
        Rails.logger.info "[LineReplaceService] Token savings: ~#{stats[:token_savings]}% vs full rewrite"

        {
          success: true,
          message: "Lines #{@first_line}-#{@last_line} replaced successfully",
          stats: stats,
          new_content: new_content
        }
      rescue => e
        Rails.logger.error "[LineReplaceService] Replacement failed: #{e.message}"
        error_result("Replacement failed: #{e.message}")
      end
    end

    private

    def valid_line_range?
      @first_line > 0 &&
        @last_line >= @first_line &&
        @first_line <= @lines.size &&
        @last_line <= @lines.size
    end

    def replacement_already_present?
      # Check if key parts of the replacement are already in the file
      # This helps prevent duplicate additions when AI retries
      return false if @replacement.blank?

      # ENHANCEMENT 1: Detect syntax fixes vs true duplicates
      if syntax_fix_detected?
        Rails.logger.info "[LineReplaceService] Syntax fix detected - allowing replacement even if content seems present"
        return false
      end

      # Extract meaningful content from replacement (ignore whitespace-only lines)
      replacement_key_lines = @replacement.lines.map(&:strip).reject(&:blank?)
      return false if replacement_key_lines.empty?

      # Check if at least 80% of key lines are already present
      file_content_normalized = @original_content.downcase.gsub(/\s+/, " ")

      present_count = replacement_key_lines.count do |line|
        normalized_line = line.downcase.gsub(/\s+/, " ")
        # Skip very short lines or common patterns
        next false if normalized_line.length < 10
        file_content_normalized.include?(normalized_line)
      end

      presence_ratio = present_count.to_f / replacement_key_lines.size

      if presence_ratio > 0.8
        Rails.logger.info "[LineReplaceService] #{(presence_ratio * 100).round}% of replacement content already present"
        return true
      end

      false
    end

    def content_seems_already_replaced?
      # Check if the content at the target lines looks like it might already
      # have been replaced (useful when line numbers are off)
      return false if @replacement.blank?

      # Get content around the target area (with some buffer)
      buffer_lines = 5
      start_line = [@first_line - buffer_lines, 1].max
      end_line = [@last_line + buffer_lines, @lines.size].min

      nearby_content = @lines[(start_line - 1)..(end_line - 1)].join.downcase

      # Check for key identifiers from the replacement
      replacement_keywords = extract_key_identifiers(@replacement)

      if replacement_keywords.any? && replacement_keywords.all? { |kw| nearby_content.include?(kw.downcase) }
        Rails.logger.info "[LineReplaceService] Key identifiers from replacement found near target lines"
        return true
      end

      false
    end

    def extract_key_identifiers(content)
      # Extract meaningful identifiers like class names, function names, comments
      identifiers = []

      # CSS class names
      identifiers.concat(content.scan(/\.[\w-]+/).map { |c| c.delete(".") })

      # Variable/function names
      identifiers.concat(content.scan(/\b(?:const|let|var|function|class)\s+(\w+)/).flatten)

      # Distinctive comments
      identifiers.concat(content.scan(/\/\*\s*(.+?)\s*\*\//).flatten)
      identifiers.concat(content.scan(/\/\/\s*(.+)$/).flatten)

      # Keep only reasonably unique identifiers
      identifiers.select { |id| id.length > 5 && !common_identifier?(id) }.uniq
    end

    def common_identifier?(identifier)
      # List of common identifiers to ignore
      common = %w[
        import export default return const let var function class
        if else for while do switch case break continue
        true false null undefined void this super new
        async await promise then catch finally try
        div span button input form label select option
        margin padding border width height display flex
        color background font size weight style position
      ]

      common.include?(identifier.downcase)
    end

    def syntax_fix_detected?
      # ENHANCEMENT 1: Detect when replacement is a syntax fix, not a duplicate
      # These changes should be allowed even if content seems already present

      target_content = extract_target_content

      # Pattern 1: Adding missing closing braces/brackets/parentheses
      target_open_braces = target_content.count("{")
      target_close_braces = target_content.count("}")
      replacement_open_braces = @replacement.count("{")
      replacement_close_braces = @replacement.count("}")

      # If replacement adds closing braces to balance unmatched ones
      if target_open_braces > target_close_braces &&
          replacement_close_braces > replacement_open_braces
        Rails.logger.info "[LineReplaceService] Detected closing brace addition - likely syntax fix"
        return true
      end

      # Pattern 2: Same for parentheses
      target_open_parens = target_content.count("(")
      target_close_parens = target_content.count(")")
      replacement_open_parens = @replacement.count("(")
      replacement_close_parens = @replacement.count(")")

      if target_open_parens > target_close_parens &&
          replacement_close_parens > replacement_open_parens
        Rails.logger.info "[LineReplaceService] Detected closing parenthesis addition - likely syntax fix"
        return true
      end

      # Pattern 3: Adding missing semicolons
      if !target_content.strip.end_with?(";") && @replacement.strip.end_with?(");", "};")
        Rails.logger.info "[LineReplaceService] Detected semicolon addition - likely syntax fix"
        return true
      end

      # Pattern 4: Function call completion (like analytics.trackFormSubmit case)
      # Target has incomplete function call, replacement completes it
      if target_content.include?("(") && !target_content.strip.end_with?(")") &&
          @replacement.include?("});")
        Rails.logger.info "[LineReplaceService] Detected function call completion - likely syntax fix"
        return true
      end

      # Pattern 5: Small additions that are clearly syntax-related
      # If replacement is mostly the same + small syntax additions
      normalized_target = target_content.gsub(/\s+/, " ").strip
      normalized_replacement = @replacement.gsub(/\s+/, " ").strip

      if normalized_replacement.start_with?(normalized_target) &&
          (normalized_replacement.length - normalized_target.length) < 10
        added_content = normalized_replacement[normalized_target.length..]
        if added_content.match?(/^[;\)\}\],\s]*$/)
          Rails.logger.info "[LineReplaceService] Detected small syntax addition: '#{added_content}'"
          return true
        end
      end

      false
    end

    def extract_target_content
      target_lines = @lines[(@first_line - 1)..(@last_line - 1)]
      target_lines.join
    end

    def pattern_matches?(target_content)
      # Support ellipsis (...) in search patterns like Lovable
      if @search_pattern.include?("...")
        ellipsis_pattern_matches?(target_content)
      else
        # Try multiple levels of normalization to handle AI-generated pattern mismatches

        # Level 1: Basic normalization - remove leading/trailing newlines
        normalized_pattern = @search_pattern.gsub(/\A\n+|\n+\z/, "").rstrip
        normalized_target = target_content.gsub(/\A\n+|\n+\z/, "").rstrip

        return true if normalized_pattern == normalized_target

        # Level 2: Normalize all whitespace (spaces, tabs) to single spaces within lines
        # This handles cases where AI uses different indentation than actual file
        space_normalized_pattern = normalized_pattern.gsub(/[ \t]+/, " ").strip
        space_normalized_target = normalized_target.gsub(/[ \t]+/, " ").strip

        if space_normalized_pattern == space_normalized_target
          Rails.logger.info "[LineReplaceService] Pattern matched after normalizing whitespace"
          return true
        end

        # Level 3: Compare line by line with flexible indentation
        pattern_lines = normalized_pattern.lines.map(&:rstrip)
        target_lines = normalized_target.lines.map(&:rstrip)

        if pattern_lines.size == target_lines.size
          all_match = pattern_lines.zip(target_lines).all? do |pattern_line, target_line|
            # Compare lines after stripping all leading/trailing whitespace
            pattern_line.strip == target_line.strip
          end

          if all_match
            Rails.logger.info "[LineReplaceService] Pattern matched after line-by-line normalization"
            return true
          end
        end

        # Level 4: Try comparing without any whitespace at all (last resort)
        # This is aggressive but catches cases where spacing is completely different
        no_space_pattern = normalized_pattern.gsub(/\s+/, "")
        no_space_target = normalized_target.gsub(/\s+/, "")

        if no_space_pattern == no_space_target
          Rails.logger.warn "[LineReplaceService] Pattern matched only after removing ALL whitespace - replacement may alter formatting"
          return true
        end

        # No match found
        false
      end
    end

    def ellipsis_pattern_matches?(target_content)
      # Split pattern by ellipsis
      parts = @search_pattern.split("...")

      return false if parts.size != 2

      prefix = parts[0].strip
      suffix = parts[1].strip

      # Normalize target content
      normalized_target = target_content.strip

      # Try exact match first
      starts_with_prefix = prefix.empty? || normalized_target.start_with?(prefix)
      ends_with_suffix = suffix.empty? || normalized_target.end_with?(suffix)

      if starts_with_prefix && ends_with_suffix
        Rails.logger.info "[LineReplaceService] Ellipsis pattern matched exactly"
        return true
      end

      # Try with whitespace normalization
      # Normalize whitespace in prefix, suffix and target
      norm_prefix = prefix.gsub(/\s+/, " ").strip
      norm_suffix = suffix.gsub(/\s+/, " ").strip
      norm_target = normalized_target.gsub(/\s+/, " ").strip

      starts_with_norm = norm_prefix.empty? || norm_target.start_with?(norm_prefix)
      ends_with_norm = norm_suffix.empty? || norm_target.end_with?(norm_suffix)

      if starts_with_norm && ends_with_norm
        Rails.logger.info "[LineReplaceService] Ellipsis pattern matched after whitespace normalization"
        return true
      end

      Rails.logger.info "[LineReplaceService] Ellipsis match failed: prefix=#{starts_with_norm}, suffix=#{ends_with_norm}"
      false
    end

    def perform_replacement
      new_lines = @lines.dup

      # Replace the target lines
      # Ensure replacement ends with newline if not already present
      replacement_with_newline = @replacement
      replacement_with_newline += "\n" unless replacement_with_newline.end_with?("\n")
      replacement_lines = replacement_with_newline.lines

      # Calculate the correct range for replacement
      start_index = @first_line - 1
      num_lines_to_replace = @last_line - @first_line + 1

      # Remove old lines and insert new ones
      new_lines[start_index, num_lines_to_replace] = replacement_lines

      new_lines.join
    end

    def validate_replacement(new_content)
      # Basic validation - ensure it's not empty and has reasonable structure
      if new_content.blank?
        return {valid: false, error: "Replacement resulted in empty content"}
      end

      # If it's a JavaScript/JSX/TypeScript file, do basic syntax checking
      file_extension = ::File.extname(@file.path).delete(".")
      if file_extension.in?(["js", "jsx", "ts", "tsx", "mjs", "cjs"])
        return validate_javascript_syntax(new_content)
      end

      # Special validation for config files
      if @file.path.include?("config.")
        return validate_config_file_structure(new_content)
      end

      {valid: true}
    end

    def validate_javascript_syntax(content)
      # Basic JavaScript validation - check for common syntax errors
      errors = []

      # Check for unmatched braces/brackets/parens
      brace_count = content.count("{") - content.count("}")
      bracket_count = content.count("[") - content.count("]")
      paren_count = content.count("(") - content.count(")")

      errors << "Unmatched braces" if brace_count != 0
      errors << "Unmatched brackets" if bracket_count != 0
      errors << "Unmatched parentheses" if paren_count != 0

      # Check for common JSX issues
      file_extension = ::File.extname(@file.path).delete(".")
      if file_extension.in?(["jsx", "tsx"])
        # Look for unclosed JSX tags (basic check)
        jsx_tag_pattern = /<(\w+)(?:\s[^>]*)?\s*>/
        jsx_close_pattern = /<\/(\w+)>/

        open_tags = content.scan(jsx_tag_pattern).flatten
        close_tags = content.scan(jsx_close_pattern).flatten

        # This is a simplified check - real JSX validation would be more complex
        if open_tags.count != close_tags.count
          errors << "Potential JSX tag mismatch"
        end
      end

      if errors.any?
        return {valid: false, error: "JavaScript syntax issues: #{errors.join(", ")}"}
      end

      {valid: true}
    end

    def calculate_stats(new_content)
      original_size = @original_content.bytesize
      new_size = new_content.bytesize

      # Estimate token savings compared to full file rewrite
      # Assuming ~4 characters per token (rough estimate)
      original_tokens = original_size / 4
      replaced_tokens = @replacement.bytesize / 4

      # Token savings = (original_tokens - replaced_tokens) / original_tokens * 100
      token_savings = if original_tokens > 0
        ((original_tokens.to_f - replaced_tokens.to_f) / original_tokens.to_f * 100).round(1)
      else
        0
      end

      {
        original_size: original_size,
        new_size: new_size,
        size_change: new_size - original_size,
        estimated_original_tokens: original_tokens,
        estimated_replacement_tokens: replaced_tokens,
        token_savings: [token_savings, 0].max, # Ensure non-negative
        lines_affected: @last_line - @first_line + 1,
        total_lines: @lines.size
      }
    end

    def error_result(message)
      {
        success: false,
        error: message,
        message: message
      }
    end

    def validate_config_file_structure(content)
      # Special validation for config files to prevent structural issues
      # This prevents issues like the tailwind.config.ts problem where
      # properties ended up outside the config object

      errors = []

      # Check for basic brace/bracket balance
      brace_count = content.count("{") - content.count("}")
      bracket_count = content.count("[") - content.count("]")
      paren_count = content.count("(") - content.count(")")

      errors << "Unmatched braces (#{brace_count} extra)" if brace_count != 0
      errors << "Unmatched brackets (#{bracket_count} extra)" if bracket_count != 0
      errors << "Unmatched parentheses (#{paren_count} extra)" if paren_count != 0

      # Check for properties outside of export blocks (common AI error)
      if content.include?("export default") || content.include?("module.exports")
        # Track brace depth after export statement
        export_index = content.index(/export\s+default\s*{|module\.exports\s*=\s*{/)
        if export_index
          after_export = content[export_index..]
          depth = 0
          in_string = false
          quote_char = nil

          after_export.each_char.with_index do |char, i|
            # Handle string literals to ignore braces inside strings
            if char == '"' || char == "'" || char == "`"
              if !in_string
                in_string = true
                quote_char = char
              elsif char == quote_char && after_export[i - 1] != "\\"
                in_string = false
                quote_char = nil
              end
              next
            end

            next if in_string

            case char
            when "{"
              depth += 1
            when "}"
              depth -= 1
              # If we close the export object
              if depth == 0
                # Check if there's significant content after (not just whitespace/semicolons)
                remaining = after_export[i + 1..]
                if remaining && remaining.strip.length > 5 && !remaining.strip.match?(/^(satisfies\s+\w+)?;?\s*$/)
                  # Found properties outside the export block
                  Rails.logger.warn "[LineReplaceService] Found content after export block closure: #{remaining[0..100]}"
                  errors << "Properties found outside export block - likely malformed structure"
                  break
                end
              end
            end
          end
        end
      end

      # Check for common config file patterns that indicate problems
      if @file.path.include?("tailwind.config")
        # Tailwind config should have plugins inside the config object
        if content.include?("plugins:") && content.include?("export default")
          # Simple heuristic: plugins should appear before the final closing brace
          plugins_index = content.index("plugins:")
          last_brace = content.rindex("}")

          if plugins_index && last_brace
            # Count braces between plugins and end
            between = content[plugins_index..last_brace]
            closes_after_plugins = between.count("}")
            if closes_after_plugins > 2  # More than expected for proper nesting
              Rails.logger.warn "[LineReplaceService] Plugins may be outside config object"
              errors << "Tailwind plugins appear to be outside the config object"
            end
          end
        end
      end

      if errors.any?
        Rails.logger.error "[LineReplaceService] Config file validation failed: #{errors.join(", ")}"
        return {valid: false, error: "Config file structural issues: #{errors.join(", ")}"}
      end

      {valid: true}
    end
  end
end
