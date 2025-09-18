module Ai
  class TypescriptValidatorService
    # Common TypeScript/JavaScript syntax errors we can auto-fix
    QUOTE_PATTERNS = [
      # Ternary operator with incorrectly escaped quotes (handles backslash before quote)
      {
        pattern: /\?\s*"([^"]*?)\\+"\s*:\s*\\+"([^"]*?)"/,
        replacement: '? "\1" : "\2"'
      },
      # Simple ternary with escaped quotes at the end of strings
      {
        pattern: /"([^"]*?)\\"\s*:\s*\\"([^"]*?)"/,
        replacement: '"\1" : "\2"'
      },
      # Handle escaped quotes in ternary expressions within function calls
      {
        pattern: /(\w+\()([^)]*?)\?\s*"([^"]*?)\\"\s*:\s*\\"([^"]*?)"([^)]*?\))/,
        replacement: '\1\2? "\3" : "\4"\5'
      },
      # JSX className with backslash before closing quote (most common pattern)
      {
        pattern: /className="([^"]*)\\">/,
        replacement: 'className="\1">'
      },
      # Any JSX attribute with backslash before closing quote
      {
        pattern: /(\w+)="([^"]*)\\">/,
        replacement: '\1="\2">'
      },
      # JSX attributes with double-escaped quotes
      {
        pattern: /(\w+)=\\"([^\\]*)\\">/,
        replacement: '\1="\2">'
      },
      # Nested JSX attributes with escaped quotes (like span inside p)
      {
        pattern: /<(\w+)\s+className=\\"([^\\]*)\\"/,
        replacement: '<\1 className="\2"'
      },
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
      # Fix double-escaped quotes (\\") to single escape (\")
      {
        pattern: /([^\\])\\\\"([^"]*?)\\\\"/,
        replacement: '\1\"\2\"'
      },
      # Generic console.log
      {
        pattern: /"console\.log\("([^"]*)"\);"/,
        replacement: '"console.log(\'\1\');"'
      }
    ]

    # Component prop validation rules
    BUTTON_VARIANTS = %w[default destructive outline secondary ghost link]
    BUTTON_SIZES = %w[default sm lg icon]

    COMPONENT_PROP_FIXES = [
      # Fix invalid Button variants
      {
        pattern: /(<Button[^>]*\s+variant=")(?:cta|hero|primary|large)(")/,
        replacement: '\1default\2',
        description: "Fixed invalid Button variant to default"
      },
      # Fix invalid Button sizes
      {
        pattern: /(<Button[^>]*\s+size=")(?:xl|extra-large|big)(")/,
        replacement: '\1lg\2',
        description: "Fixed invalid Button size to lg"
      },
      # Fix common Button prop combinations
      {
        pattern: /(<Button[^>]*\s+variant="cta"[^>]*\s+size="xl")/,
        replacement: '\1',
        description: "Fixed invalid Button variant and size combination"
      }
    ]

    attr_reader :validation_errors, :fixed_files

    def initialize(app)
      @app = app
      @fixed_files = []
      @validation_errors = []
    end

    # Single file validation and auto-fix method (used by AiToolService)
    def validate_and_fix_typescript(file_path, content)
      return content unless typescript_or_javascript?(file_path)

      Rails.logger.info "[TypescriptValidator] Validating #{file_path}"

      fixed_content = auto_fix_content(content, file_path)

      if fixed_content != content
        Rails.logger.info "[TypescriptValidator] Auto-fixed issues in #{file_path}"
        @fixed_files << file_path
      end

      # Run additional validation after fixes
      remaining_errors = validate_content(fixed_content, file_path)
      if remaining_errors.any?
        @validation_errors.concat(remaining_errors)
      end

      fixed_content
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
          if line&.match?(fix[:pattern])
            line.gsub!(fix[:pattern], fix[:replacement])
          end
        end

        # Comprehensive fix for ternary operator with escaped quotes
        if line.include?("?") && line.include?(":")
          # First pass: Fix the pattern ? "text\" : \"text"
          line.gsub!(/\?\s*"([^"]*?)\\"\s*:\s*\\"([^"]*?)"/, '? "\1" : "\2"')

          # Second pass: Fix remaining escaped quotes in ternary context
          # Fix pattern: "text\" followed by : (end of first option)
          line.gsub!(/"([^"]*?)\\"\s*:/, '"\1" :')

          # Fix pattern: : \"text" (start of second option)
          line.gsub!(/:\s*\\"([^"]*?)"/, ': "\1"')

          # Fix trailing \" at the end of a ternary expression
          # This handles cases like: "text\"); or "text\"}
          line.gsub!(/(".*?)\\("[\s\)\};,])/, '\1\2')

          # Fix any remaining \"text patterns (for nested ternaries)
          # This catches cases like: b ? \"Second\"
          line.gsub!(/([?:]\s*)\\"([^"]*?)"/, '\1"\2"')
        end

        # Apply component prop fixes
        COMPONENT_PROP_FIXES.each do |fix|
          if line =~ fix[:pattern]
            old_line = line.dup
            line.gsub!(fix[:pattern], fix[:replacement])
            if line != old_line
              Rails.logger.info "[TypescriptValidator] #{fix[:description]} on line #{index + 1}"
            end
          end
        end

        # JSX-specific fixes for common patterns that escaped the above
        # Fix className with backslash before closing quote
        line.gsub!(/(\w+)="([^"]*)\\"([^>]*)>/) do |match|
          attr_name = $1
          attr_value = $2
          rest = $3
          "#{attr_name}=\"#{attr_value}\"#{rest}>"
        end

        # Fix JSX attributes with double-escaped quotes
        line.gsub!(/<(\w+)([^>]*)\s+(\w+)=\\"([^\\]*)\\"([^>]*)>/) do |match|
          tag_name = $1
          before_attr = $2
          attr_name = $3
          attr_value = $4
          after_attr = $5
          "<#{tag_name}#{before_attr} #{attr_name}=\"#{attr_value}\"#{after_attr}>"
        end

        # Skip the generic quote fix entirely - it's causing more problems than it solves
        # The specific patterns above should handle all the cases we need

        if line != original_line
          lines_fixed << {line_num: index + 1, from: original_line.strip, to: line.strip}
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
        next if line.strip.start_with?("//", "*")
        next if line.include?("`") # Skip template literals

        # Detect potential unescaped quotes
        if line =~ /"[^"\\]*"[^,;}\s]*"[^"\\]*"/ && !line.include?('\\\"')
          # Double-check it's not a valid pattern
          unless valid_quote_pattern?(line)
            errors << {
              file: filepath,
              line: index + 1,
              type: "unescaped_quotes",
              content: line.strip,
              suggestion: suggest_fix(line)
            }
          end
        end

        # Check for invalid Button component props
        if line.include?("<Button")
          # Check for invalid variants
          if line =~ /variant="(cta|hero|primary|large)"/
            variant = $1
            errors << {
              file: filepath,
              line: index + 1,
              type: "invalid_button_variant",
              content: line.strip,
              suggestion: "Replace variant=\"#{variant}\" with one of: #{BUTTON_VARIANTS.join(", ")}"
            }
          end

          # Check for invalid sizes
          if line =~ /size="(xl|extra-large|big)"/
            size = $1
            errors << {
              file: filepath,
              line: index + 1,
              type: "invalid_button_size",
              content: line.strip,
              suggestion: "Replace size=\"#{size}\" with one of: #{BUTTON_SIZES.join(", ")}"
            }
          end
        end

        # Check for other common TypeScript errors
        if /\bfunction\s+\w+\s*\([^)]*\)\s*$/.match?(line)
          errors << {
            file: filepath,
            line: index + 1,
            type: "missing_return_type",
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
      if line.include?("println") || line.include?("print(")
        "Escape inner quotes with backslash: \\\" or use single quotes"
      elsif line.include?("<<")
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
            role: "system",
            content: "🔧 Auto-fixed TypeScript syntax errors in: #{@fixed_files.join(", ")}",
            metadata: {auto_fixed_files: @fixed_files}
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
