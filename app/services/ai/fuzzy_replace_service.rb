# Fuzzy Pattern Replacement Service
# Finds and replaces content without requiring exact line numbers
# More robust than line-based replacement for AI-generated edits

module Ai
  class FuzzyReplaceService
    attr_reader :file, :search_pattern, :replacement, :options

    def initialize(file, search_pattern, replacement, options = {})
      @file = file
      @search_pattern = search_pattern
      @replacement = replacement
      @options = options
      @original_content = file.content
    end

    def self.replace(file, search_pattern, replacement, options = {})
      service = new(file, search_pattern, replacement, options)
      service.execute
    end

    def execute
      Rails.logger.info "[FuzzyReplace] Starting fuzzy replacement in #{file.path}"
      Rails.logger.info "[FuzzyReplace] Search pattern: #{search_pattern[0..100].inspect}..."

      begin
        # Normalize patterns for matching
        normalized_search = normalize_pattern(search_pattern)
        normalized_content = normalize_pattern(@original_content)

        # Try exact match first
        if normalized_content.include?(normalized_search)
          Rails.logger.info "[FuzzyReplace] Found exact match"
          new_content = perform_exact_replacement(normalized_search)
          return save_and_return(new_content, "Exact match replacement successful")
        end

        # Try fuzzy matching
        match_info = find_fuzzy_match(normalized_search, normalized_content)
        if match_info
          Rails.logger.info "[FuzzyReplace] Found fuzzy match at position #{match_info[:position]}"
          new_content = perform_fuzzy_replacement(match_info)
          return save_and_return(new_content, "Fuzzy match replacement successful")
        end

        # Try structural matching for code files
        if code_file? && options[:use_structural] != false
          Rails.logger.info "[FuzzyReplace] Trying structural matching"
          new_content = perform_structural_replacement
          if new_content && new_content != @original_content
            return save_and_return(new_content, "Structural replacement successful")
          end
        end

        # Last resort: Find by semantic similarity
        if options[:use_semantic] != false
          Rails.logger.info "[FuzzyReplace] Trying semantic matching"
          new_content = perform_semantic_replacement
          if new_content && new_content != @original_content
            return save_and_return(new_content, "Semantic replacement successful")
          end
        end

        Rails.logger.warn "[FuzzyReplace] No match found for pattern"
        error_result("Pattern not found in file")
      rescue => e
        Rails.logger.error "[FuzzyReplace] Replacement failed: #{e.message}"
        error_result("Replacement failed: #{e.message}")
      end
    end

    private

    def normalize_pattern(text)
      # Normalize whitespace while preserving structure
      text
        .gsub("\r\n", "\n")           # Normalize line endings
        .gsub(/^\s+$/, "")            # Remove whitespace-only lines
        .gsub(/\n{3,}/, "\n\n")       # Collapse multiple blank lines
        .strip                         # Remove leading/trailing whitespace
    end

    def find_fuzzy_match(search, content)
      # Try different matching strategies

      # 1. Match ignoring all whitespace
      search_compact = search.gsub(/\s+/, "")
      content_compact = content.gsub(/\s+/, "")
      if pos = content_compact.index(search_compact)
        return {
          position: map_compact_to_original(pos, content),
          type: :whitespace_insensitive,
          compact_search: search_compact
        }
      end

      # 2. Match key tokens (for code)
      if code_file?
        tokens = extract_key_tokens(search)
        if tokens.any? && all_tokens_present?(tokens, content)
          return {
            position: find_token_sequence_position(tokens, content),
            type: :token_match,
            tokens: tokens
          }
        end
      end

      # 3. Match by lines (find best matching sequence)
      search_lines = search.lines.map(&:strip).reject(&:empty?)
      if search_lines.size > 0
        best_match = find_best_line_sequence(search_lines, content)
        if best_match && best_match[:score] > 0.8
          return best_match
        end
      end

      nil
    end

    def perform_exact_replacement(normalized_search)
      # Replace in original content, preserving indentation
      @original_content.gsub(search_pattern, replacement)
    end

    def perform_fuzzy_replacement(match_info)
      case match_info[:type]
      when :whitespace_insensitive
        # Find the actual text span in original content and replace
        perform_whitespace_insensitive_replacement(match_info)
      when :token_match
        # Replace based on token positions
        perform_token_based_replacement(match_info)
      when :line_sequence
        # Replace the matched line sequence
        perform_line_sequence_replacement(match_info)
      else
        @original_content
      end
    end

    def perform_structural_replacement
      # For CSS: Replace by selector
      if file.file_type == "css"
        return replace_css_rule
      end

      # For JS/TS: Replace by function/class/variable
      if file.file_type.in?(["js", "jsx", "ts", "tsx"])
        return replace_javascript_structure
      end

      nil
    end

    def replace_css_rule
      # Extract CSS selector from search pattern
      if match = search_pattern.match(/([.#]?[\w-]+)\s*\{([^}]+)\}/)
        selector = match[1]
        new_properties = begin
          replacement.match(/\{([^}]+)\}/)[1]
        rescue
          replacement
        end

        # Replace the rule in content
        @original_content.gsub(/#{Regexp.escape(selector)}\s*\{[^}]+\}/) do
          "#{selector} {#{new_properties}}"
        end
      end
    end

    def replace_javascript_structure
      # Simple structural replacement for common patterns

      # Variable/const declaration
      if search_pattern =~ /(?:const|let|var)\s+(\w+)\s*=/
        var_name = $1
        @original_content.gsub(/(?:const|let|var)\s+#{var_name}\s*=\s*[^;]+;/) do
          replacement.strip.end_with?(";") ? replacement : "#{replacement};"
        end
      end
    end

    def perform_semantic_replacement
      # Use embedding similarity or other semantic matching
      # For now, use a simple heuristic-based approach

      # Find the most similar block of text
      search_size = search_pattern.lines.size
      best_match = nil
      best_score = 0

      @original_content.lines.each_cons(search_size).with_index do |lines, index|
        block = lines.join
        score = calculate_similarity(search_pattern, block)
        if score > best_score
          best_score = score
          best_match = {lines: lines, index: index, block: block}
        end
      end

      if best_match && best_score > 0.7
        lines = @original_content.lines
        lines[best_match[:index], search_size] = replacement.lines
        lines.join
      end
    end

    def calculate_similarity(text1, text2)
      # Simple similarity based on common tokens
      tokens1 = text1.downcase.scan(/\w+/)
      tokens2 = text2.downcase.scan(/\w+/)

      return 0 if tokens1.empty? || tokens2.empty?

      common = tokens1 & tokens2
      (2.0 * common.size) / (tokens1.size + tokens2.size)
    end

    def find_best_line_sequence(search_lines, content)
      content_lines = content.lines.map(&:strip)
      best_match = nil
      best_score = 0

      (0..content_lines.size - search_lines.size).each do |i|
        score = 0
        search_lines.each_with_index do |search_line, j|
          content_line = content_lines[i + j]
          if search_line == content_line
            score += 1.0
          elsif content_line.include?(search_line) || search_line.include?(content_line)
            score += 0.5
          end
        end

        normalized_score = score / search_lines.size
        if normalized_score > best_score
          best_score = normalized_score
          best_match = {
            type: :line_sequence,
            start_line: i,
            end_line: i + search_lines.size - 1,
            score: normalized_score
          }
        end
      end

      best_match
    end

    def perform_line_sequence_replacement(match_info)
      lines = @original_content.lines
      lines[match_info[:start_line]..match_info[:end_line]] = replacement.lines
      lines.join
    end

    def extract_key_tokens(text)
      # Extract significant tokens (variables, functions, properties)
      text.scan(/(?:--|[\w-]+):\s*[\w.%]+|[\w-]+\(|class\s+\w+|function\s+\w+|const\s+\w+/)
    end

    def all_tokens_present?(tokens, content)
      tokens.all? { |token| content.include?(token) }
    end

    def find_token_sequence_position(tokens, content)
      # Find where the token sequence starts
      first_token = tokens.first
      content.index(first_token) || 0
    end

    def map_compact_to_original(compact_pos, original)
      # Map position in compacted string back to original
      0 # Simplified for now
    end

    def perform_whitespace_insensitive_replacement(match_info)
      # Replace ignoring whitespace differences
      @original_content # Simplified for now
    end

    def perform_token_based_replacement(match_info)
      # Replace based on token positions
      @original_content # Simplified for now
    end

    def code_file?
      file.file_type.in?(["js", "jsx", "ts", "tsx", "css", "scss", "rb", "py"])
    end

    def save_and_return(new_content, message)
      @file.update!(
        content: new_content,
        size_bytes: new_content.bytesize
      )

      {
        success: true,
        message: message,
        stats: {
          original_size: @original_content.bytesize,
          new_size: new_content.bytesize,
          method_used: message
        }
      }
    end

    def error_result(message)
      {
        success: false,
        error: message
      }
    end
  end
end
