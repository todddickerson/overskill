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
      
      begin
        # Validate line numbers
        return error_result("Invalid line range") unless valid_line_range?
        
        # Extract content to replace
        target_content = extract_target_content
        
        # Check if search pattern matches (with ellipsis support)
        unless pattern_matches?(target_content)
          Rails.logger.warn "[LineReplaceService] Pattern mismatch in #{file.path}"
          Rails.logger.warn "[LineReplaceService] Expected pattern: #{@search_pattern[0..200]}..."
          Rails.logger.warn "[LineReplaceService] Actual content: #{target_content[0..200]}..."
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
    
    def extract_target_content
      target_lines = @lines[(@first_line - 1)..(@last_line - 1)]
      target_lines.join
    end
    
    def pattern_matches?(target_content)
      # Support ellipsis (...) in search patterns like Lovable
      if @search_pattern.include?('...')
        return ellipsis_pattern_matches?(target_content)
      else
        # Exact match for simple patterns
        normalized_pattern = @search_pattern.strip
        normalized_target = target_content.strip
        normalized_pattern == normalized_target
      end
    end
    
    def ellipsis_pattern_matches?(target_content)
      # Split pattern by ellipsis
      parts = @search_pattern.split('...')
      
      return false if parts.size != 2
      
      prefix = parts[0].strip
      suffix = parts[1].strip
      
      # Check if target content starts and ends with the pattern parts
      normalized_target = target_content.strip
      
      starts_with_prefix = prefix.empty? || normalized_target.start_with?(prefix)
      ends_with_suffix = suffix.empty? || normalized_target.end_with?(suffix)
      
      Rails.logger.info "[LineReplaceService] Ellipsis match: prefix=#{starts_with_prefix}, suffix=#{ends_with_suffix}"
      
      starts_with_prefix && ends_with_suffix
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
        return { valid: false, error: "Replacement resulted in empty content" }
      end
      
      # If it's a JavaScript/JSX file, do basic syntax checking
      if @file.file_type.in?(['js', 'jsx'])
        return validate_javascript_syntax(new_content)
      end
      
      { valid: true }
    end
    
    def validate_javascript_syntax(content)
      # Basic JavaScript validation - check for common syntax errors
      errors = []
      
      # Check for unmatched braces/brackets/parens
      brace_count = content.count('{') - content.count('}')
      bracket_count = content.count('[') - content.count(']')
      paren_count = content.count('(') - content.count(')')
      
      errors << "Unmatched braces" if brace_count != 0
      errors << "Unmatched brackets" if bracket_count != 0
      errors << "Unmatched parentheses" if paren_count != 0
      
      # Check for common JSX issues
      if @file.file_type == 'jsx'
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
        return { valid: false, error: "JavaScript syntax issues: #{errors.join(', ')}" }
      end
      
      { valid: true }
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
  end
end