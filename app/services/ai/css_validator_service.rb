module Ai
  class CssValidatorService
    # Common CSS syntax errors we can detect and fix
    CSS_ISSUES = [
      # Extra closing braces
      { 
        pattern: /\}\s*\}\s*\}/,
        fix: '}}',
        description: 'Triple closing braces'
      },
      # Orphaned closing braces after valid blocks
      { 
        pattern: /(\@keyframes\s+\w+\s*\{[^}]*\{[^}]*\}\s*\})\s*\}\s*\}/,
        fix: '\1',
        description: 'Extra braces after @keyframes'
      },
      # Missing semicolons (common in Tailwind/PostCSS)
      {
        pattern: /([a-z-]+:\s*[^;}\s]+)\s*\n\s*([a-z-]+:)/,
        fix: '\1;\n  \2',
        description: 'Missing semicolon between properties'
      },
      # Unclosed blocks
      {
        pattern: /(\@media[^{]*\{[^}]*)\z/,
        fix: '\1}',
        description: 'Unclosed @media block'
      }
    ]

    def initialize(app = nil)
      @app = app
      @validation_errors = []
      @fixed_files = []
    end

    # Main validation and auto-fix method
    def validate_and_fix_css(path, content)
      Rails.logger.info "[CssValidator] Validating CSS in #{path}"
      
      original_content = content.dup
      fixed_content = content.dup
      fixes_applied = []
      
      # Check for brace balance first
      brace_balance = check_brace_balance(fixed_content)
      if brace_balance != 0
        Rails.logger.warn "[CssValidator] Brace imbalance detected: #{brace_balance} extra #{brace_balance > 0 ? 'opening' : 'closing'} braces"
        
        # Try to fix extra closing braces
        if brace_balance < 0
          fixed_content = fix_extra_closing_braces(fixed_content, -brace_balance)
          fixes_applied << "Removed #{-brace_balance} extra closing braces"
        end
      end
      
      # Apply pattern-based fixes
      CSS_ISSUES.each do |issue|
        if fixed_content.match?(issue[:pattern])
          fixed_content.gsub!(issue[:pattern], issue[:fix])
          fixes_applied << issue[:description]
        end
      end
      
      # Validate CSS structure
      validation_errors = validate_css_structure(fixed_content)
      
      if fixes_applied.any?
        Rails.logger.info "[CssValidator] Applied fixes: #{fixes_applied.join(', ')}"
        
        # Add system message about the fix if in app context
        if @app && @app.respond_to?(:app_chat_messages)
          @app.app_chat_messages.create!(
            role: 'system',
            content: "🎨 Auto-fixed CSS issues in #{path}: #{fixes_applied.join(', ')}",
            status: 'completed'
          )
        end
      end
      
      if validation_errors.any?
        Rails.logger.warn "[CssValidator] Remaining CSS issues in #{path}: #{validation_errors.join(', ')}"
        @validation_errors.concat(validation_errors)
      end
      
      fixed_content
    end

    private

    def check_brace_balance(content)
      # Count opening and closing braces
      opening = content.count('{')
      closing = content.count('}')
      opening - closing
    end

    def fix_extra_closing_braces(content, extra_count)
      fixed = content.dup
      
      # Remove trailing extra closing braces
      # Look for patterns like "}\n  }\n}" at the end of blocks
      extra_count.times do
        # Find isolated closing braces (not part of a valid CSS block)
        # This regex finds closing braces that appear after already closed blocks
        if fixed =~ /(\}\s*)\}\s*$/
          fixed.sub!(/(\}\s*)\}\s*$/, '\1')
        elsif fixed =~ /\}\s*\}\s*\n\s*\}/
          # Remove middle extra brace in triple-brace patterns
          fixed.sub!(/(\}\s*)\}\s*(\n\s*\})/, '\1\2')
        else
          # Last resort: remove the last closing brace
          fixed.sub!(/\}\s*\z/, '')
        end
      end
      
      fixed
    end

    def validate_css_structure(content)
      errors = []
      
      # Check for common CSS structural issues
      lines = content.split("\n")
      
      lines.each_with_index do |line, index|
        line_num = index + 1
        
        # Check for invalid selectors
        if line =~ /^\s*[{}]\s*[a-z]/i
          errors << "Line #{line_num}: Invalid selector or orphaned brace"
        end
        
        # Check for missing colons in properties
        if line =~ /^\s*[a-z-]+\s+[^:;{}\s]/i && !line.include?(':')
          errors << "Line #{line_num}: Missing colon in property declaration"
        end
        
        # Check for duplicate semicolons
        if line =~ /;;\s*$/
          errors << "Line #{line_num}: Duplicate semicolons"
        end
      end
      
      # Check for unclosed comments
      if content.include?('/*') && !content.include?('*/')
        errors << "Unclosed comment block"
      end
      
      # Check for invalid @rules
      if content =~ /@[a-z]+(?![a-z-])[^{;]*$/m
        errors << "Invalid or incomplete @rule"
      end
      
      errors
    end

    def report_results
      {
        success: @validation_errors.empty?,
        fixed_files: @fixed_files,
        remaining_errors: @validation_errors
      }
    end

    def build_error_prompt(errors)
      prompt = "I found CSS validation errors that need fixing:\n\n"
      
      errors.each do |error|
        prompt += "- #{error}\n"
      end
      
      prompt += "\nPlease fix these CSS errors by updating the affected files."
      prompt
    end
  end
end