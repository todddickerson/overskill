module Ai
  class TypescriptValidatorService
    # Common TypeScript/JavaScript syntax errors we can auto-fix
    QUOTE_PATTERNS = [
      # Java System.out.println
      { 
        pattern: /"System\.out\.println\("([^"]*)"\);"/,
        replacement: '"System.out.println(\"\1\");"'
      },
      # C++ cout
      { 
        pattern: /"std::cout\s*<<\s*"([^"]*)"([^"]*);"/,
        replacement: '"std::cout << \"\1\"\2;"'
      },
      # Go fmt.Println
      { 
        pattern: /"fmt\.Println\("([^"]*)"\)"/,
        replacement: '"fmt.Println(\"\1\")"'
      },
      # Rust println!
      { 
        pattern: /"println!\("([^"]*)"\);"/,
        replacement: '"println!(\"\1\");"'
      },
      # Python print (in case)
      { 
        pattern: /"print\("([^"]*)"\)"/,
        replacement: '"print(\'\1\')"'
      },
      # Generic console.log
      { 
        pattern: /"console\.log\("([^"]*)"\);"/,
        replacement: '"console.log(\'\1\');"'
      }
    ]

    def initialize(app)
      @app = app
      @fixed_files = []
      @validation_errors = []
    end

    # Main validation and auto-fix method
    def validate_and_fix_files(files)
      Rails.logger.info "[TypescriptValidator] Validating #{files.count} files"
      
      files.each do |file|
        next unless typescript_or_javascript?(file[:path])
        
        original_content = file[:content]
        fixed_content = auto_fix_content(original_content, file[:path])
        
        if fixed_content != original_content
          Rails.logger.info "[TypescriptValidator] Auto-fixed issues in #{file[:path]}"
          file[:content] = fixed_content
          @fixed_files << file[:path]
        end
        
        # Run additional validation after fixes
        remaining_errors = validate_content(fixed_content, file[:path])
        if remaining_errors.any?
          @validation_errors.concat(remaining_errors)
        end
      end
      
      report_results
    end

    # Auto-fix common syntax errors
    def auto_fix_content(content, filepath)
      fixed = content.dup
      lines_fixed = []
      
      # Fix line by line for better tracking
      lines = fixed.split("\n")
      lines.each_with_index do |line, index|
        original_line = line.dup
        
        # Apply all quote patterns
        QUOTE_PATTERNS.each do |fix|
          if line =~ fix[:pattern]
            line.gsub!(fix[:pattern], fix[:replacement])
          end
        end
        
        # Fix escaped quotes that should use backslashes
        line.gsub!(/"([^"]*)"([^,;}]*)"([^"]*)"/) do |match|
          # This is a string containing quotes - escape them
          first_part = $1
          middle = $2
          last_part = $3
          "\"#{first_part}\\\"#{middle}\\\"#{last_part}\""
        end
        
        if line != original_line
          lines_fixed << { line_num: index + 1, from: original_line.strip, to: line.strip }
          lines[index] = line
        end
      end
      
      if lines_fixed.any?
        Rails.logger.info "[TypescriptValidator] Fixed #{lines_fixed.count} lines in #{filepath}:"
        lines_fixed.each do |fix|
          Rails.logger.info "  Line #{fix[:line_num]}: #{fix[:from][0..50]}... => #{fix[:to][0..50]}..."
        end
      end
      
      lines.join("\n")
    end

    # Validate content for remaining issues
    def validate_content(content, filepath)
      errors = []
      lines = content.split("\n")
      
      lines.each_with_index do |line, index|
        # Check for unescaped quotes (but skip template literals and comments)
        next if line.strip.start_with?('//') || line.strip.start_with?('*')
        next if line.include?('`') # Skip template literals
        
        # Detect potential unescaped quotes
        if line =~ /"[^"\\]*"[^,;}\s]*"[^"\\]*"/ && !line.include?('\\\"')
          # Double-check it's not a valid pattern
          unless valid_quote_pattern?(line)
            errors << {
              file: filepath,
              line: index + 1,
              type: 'unescaped_quotes',
              content: line.strip,
              suggestion: suggest_fix(line)
            }
          end
        end
        
        # Check for other common TypeScript errors
        if line =~ /\bfunction\s+\w+\s*\([^)]*\)\s*$/
          errors << {
            file: filepath,
            line: index + 1,
            type: 'missing_return_type',
            content: line.strip,
            suggestion: "Add return type or ': void'"
          }
        end
      end
      
      errors
    end

    private

    def typescript_or_javascript?(filepath)
      filepath.match?(/\.(ts|tsx|js|jsx)$/)
    end

    def valid_quote_pattern?(line)
      # Some patterns are valid (like HTML attributes)
      line.match?(/className="[^"]*"/) ||
      line.match?(/style="[^"]*"/) ||
      line.match?(/<\w+[^>]*"[^"]*"[^>]*>/) ||
      line.match?(/=['"`]\{.*\}['"`]/) # JSX expressions
    end

    def suggest_fix(line)
      # Provide specific fix suggestions
      if line.include?('println') || line.include?('print(')
        "Escape inner quotes with backslash: \\\" or use single quotes"
      elsif line.include?('<<')
        "Escape quotes in C++ string: std::cout << \\\"text\\\""
      else
        "Use escaped quotes (\\\"), single quotes ('), or template literals (`)"
      end
    end

    def report_results
      result = {
        success: @validation_errors.empty?,
        files_fixed: @fixed_files,
        remaining_errors: @validation_errors
      }
      
      if @fixed_files.any?
        Rails.logger.info "[TypescriptValidator] ✅ Auto-fixed #{@fixed_files.count} files"
        
        # Track this in the conversation
        if @app.respond_to?(:app_chat_messages)
          @app.app_chat_messages.create!(
            role: 'system',
            content: "🔧 Auto-fixed TypeScript syntax errors in: #{@fixed_files.join(', ')}",
            metadata: { auto_fixed_files: @fixed_files }
          )
        end
      end
      
      if @validation_errors.any?
        Rails.logger.warn "[TypescriptValidator] ⚠️ #{@validation_errors.count} errors need AI intervention"
        
        # Return errors to AI conversation for fixing
        error_prompt = build_error_prompt(@validation_errors)
        result[:ai_fix_prompt] = error_prompt
      end
      
      result
    end

    def build_error_prompt(errors)
      prompt = "I found syntax errors that need fixing:\n\n"
      
      errors.group_by { |e| e[:file] }.each do |file, file_errors|
        prompt += "**#{file}:**\n"
        file_errors.each do |error|
          prompt += "- Line #{error[:line]}: #{error[:type]}\n"
          prompt += "  Current: `#{error[:content][0..100]}`\n"
          prompt += "  Suggestion: #{error[:suggestion]}\n"
        end
        prompt += "\n"
      end
      
      prompt += "Please fix these errors by updating the affected files with os-line-replace."
      prompt
    end
  end
end