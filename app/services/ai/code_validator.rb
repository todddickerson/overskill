# Validates AI-generated code before writing to prevent build failures
class Ai::CodeValidator
  VALID_TAILWIND_SHADOWS = %w[sm md lg xl 2xl inner none]
  VALID_TAILWIND_TEXT_SIZES = %w[xs sm base lg xl 2xl 3xl 4xl 5xl 6xl 7xl 8xl 9xl]
  VALID_TAILWIND_ROUNDED = %w[none sm md lg xl 2xl 3xl full]

  # Common invalid classes AI might generate
  INVALID_CLASS_REPLACEMENTS = {
    "shadow-3xl" => "shadow-2xl",
    "shadow-4xl" => "shadow-2xl",
    "shadow-5xl" => "shadow-2xl",
    "text-10xl" => "text-9xl",
    "text-11xl" => "text-9xl",
    "rounded-4xl" => "rounded-3xl",
    "rounded-5xl" => "rounded-3xl",
    "rounded-6xl" => "rounded-3xl"
  }.freeze

  def self.validate_and_fix_css(content)
    return content if content.blank?

    fixed_content = content.dup
    replacements_made = []

    # First, fix invalid Tailwind classes
    INVALID_CLASS_REPLACEMENTS.each do |invalid, valid|
      if fixed_content.include?(invalid)
        fixed_content.gsub!(invalid, valid)
        replacements_made << "#{invalid} → #{valid}"
      end
    end

    # Then check and fix CSS syntax issues
    syntax_fixes = fix_css_syntax_issues(fixed_content)
    if syntax_fixes[:fixed]
      fixed_content = syntax_fixes[:content]
      replacements_made.concat(syntax_fixes[:fixes])
    end

    if replacements_made.any?
      Rails.logger.warn "[AI_VALIDATOR] Fixed CSS issues: #{replacements_made.join(", ")}"
    end

    fixed_content
  end

  def self.fix_css_syntax_issues(content)
    fixes = []
    lines = content.split("\n")
    fixed_lines = []
    brace_stack = []
    in_comment = false

    lines.each_with_index do |line, index|
      current_line = line

      # Track comment state
      if line.include?("/*") && !line.include?("*/")
        in_comment = true
      end
      if line.include?("*/")
        in_comment = false
        fixed_lines << current_line
        next
      end

      if in_comment
        fixed_lines << current_line
        next
      end

      # Count braces first before any modifications
      opening_braces = current_line.count("{")
      closing_braces = current_line.count("}")

      # Track nested structure first
      opening_braces.times do
        # Determine what opened
        if line.match?(/@layer\s+\w+\s*\{/)
          brace_stack.push({type: "layer", line: index})
        elsif line.match?(/@media[^{]*\{/)
          brace_stack.push({type: "media", line: index})
        elsif line.match?(/@keyframes\s+\w+\s*\{/)
          brace_stack.push({type: "keyframes", line: index})
        elsif line.match?(/^\s*\w+[^{]*\{/) || line.match?(/^\s*\*\s*\{/)
          brace_stack.push({type: "selector", line: index})
        else
          brace_stack.push({type: "block", line: index})
        end
      end

      # Now handle closing braces - check for extras before popping from stack
      if closing_braces > 0
        available_to_close = brace_stack.size
        if closing_braces > available_to_close
          # We have more closing braces than open blocks - remove extras
          extra_closes = closing_braces - available_to_close
          (1..extra_closes).each do
            # Remove one extra closing brace each time
            current_line = current_line.sub(/\s*\}\s*$/, "")
            fixes << "Removed extra closing brace at line #{index + 1}"
          end
          # Recalculate after removing extras
          closing_braces = current_line.count("}")
        end
      end

      # Pop from stack for the remaining valid closing braces
      closing_braces.times { brace_stack.pop if brace_stack.any? }

      # Add missing semicolons (including after @apply which needs semicolons)
      if !current_line.strip.empty? &&
          !current_line.strip.end_with?(";", "{", "}", "*/") &&
          !current_line.include?("@layer") &&
          !current_line.include?("@media") &&
          !current_line.include?("@keyframes") &&
          (current_line.include?(":") || current_line.include?("@apply"))
        current_line += ";"
        fixes << "Added missing semicolon at line #{index + 1}"
      end

      fixed_lines << current_line
    end

    # Check for unclosed blocks at specific nesting points
    if brace_stack.any?
      # Add closing braces for unclosed blocks
      brace_stack.reverse_each do |block|
        case block[:type]
        when "layer"
          # Check if a new @layer started without closing previous one
          layer_line = lines[block[:line]]
          if layer_line&.match?(/@layer\s+(\w+)/)
            layer_name = $1
            # Find where this layer's content should end
            # Look for the next @layer or end of file
            next_layer_index = lines.index.with_index { |l, i| i > block[:line] && l.match?(/@layer\s+(?!#{layer_name})/) }

            if next_layer_index
              # Insert closing brace before the next @layer
              fixed_lines.insert(next_layer_index, "}")
              fixes << "Added missing closing brace for @layer #{layer_name}"
            else
              # Add at end if no next layer found
              fixed_lines << "}"
              fixes << "Added missing closing brace for @layer #{layer_name} at end"
            end
          end
        when "selector"
          # Find the selector name for context
          selector_line = lines[block[:line]]
          selector_name = selector_line.strip.split("{").first.strip
          # Add closing brace at the next appropriate position
          fixed_lines << "}"
          fixes << "Added missing closing brace for selector '#{selector_name}'"
        else
          fixed_lines << "}"
          fixes << "Added missing closing brace for #{block[:type]}"
        end
      end
    end

    {
      fixed: fixes.any?,
      content: fixed_lines.join("\n"),
      fixes: fixes
    }
  end

  def self.validate_jsx_syntax(content, file_path = nil)
    return {valid: true} if content.blank?

    errors = []

    # Check for mismatched JSX tags
    tag_stack = []
    tag_regex = /<\/?([A-Z][A-Za-z]*)[^>]*>/

    content.scan(tag_regex) do |match|
      tag_name = match[0]
      full_match = Regexp.last_match[0]

      if full_match.start_with?("</")
        # Closing tag
        if tag_stack.empty?
          errors << "Unexpected closing tag </#{tag_name}>"
        elsif tag_stack.last != tag_name
          errors << "Mismatched closing tag </#{tag_name}>, expected </#{tag_stack.last}>"
        else
          tag_stack.pop
        end
      elsif !full_match.end_with?("/>")
        # Opening tag (not self-closing)
        tag_stack.push(tag_name)
      end
    end

    if tag_stack.any?
      errors << "Unclosed tags: #{tag_stack.join(", ")}"
    end

    # Check for common React mistakes
    if content.include?("class=") && !content.include?("className=")
      errors << "Using 'class' instead of 'className' in JSX"
    end

    if errors.any?
      Rails.logger.error "[AI_VALIDATOR] JSX validation failed#{file_path ? " for #{file_path}" : ""}: #{errors.join("; ")}"
      return {valid: false, errors: errors}
    end

    {valid: true}
  end

  def self.validate_typescript(content, file_path = nil)
    return {valid: true} if content.blank?

    errors = []

    # DISABLED: This validation has a broken regex that causes false positives
    # The regex [^}]* stops at the first closing brace, so any function with
    # nested blocks (if statements, loops, etc.) will be incorrectly flagged
    # as missing a return statement even when it has one.
    #
    # if content.match?(/export\s+(default\s+)?function\s+\w+.*?\{/)
    #   function_bodies = content.scan(/export\s+(?:default\s+)?function\s+\w+[^{]*\{([^}]*)\}/m)
    #   function_bodies.each do |body|
    #     unless body[0].include?('return')
    #       errors << "Function component missing return statement"
    #     end
    #   end
    # end

    # Check for incorrect useState syntax
    if content.match?(/const\s+\w+\s*=\s*useState\(/) && !content.match?(/const\s+\[\w+,\s*set\w+\]\s*=\s*useState\(/)
      errors << "Incorrect useState destructuring syntax"
    end

    if errors.any?
      Rails.logger.warn "[AI_VALIDATOR] TypeScript issues found#{file_path ? " in #{file_path}" : ""}: #{errors.join("; ")}"
    end

    {valid: errors.empty?, errors: errors}
  end

  def self.validate_file(content, file_path)
    return content if content.blank?

    case ::File.extname(file_path)
    when ".css"
      validate_and_fix_css(content)
    when ".jsx", ".tsx"
      result = validate_jsx_syntax(content, file_path)
      if result[:valid]
        validate_typescript(content, file_path)
        content
      else
        # Attempt to fix or reject
        Rails.logger.error "[AI_VALIDATOR] Cannot auto-fix JSX errors in #{file_path}"
        raise "Invalid JSX syntax in #{file_path}: #{result[:errors].join("; ")}"
      end
    when ".ts", ".js"
      validate_typescript(content, file_path)
      content
    else
      content
    end
  end
end
