# Validates AI-generated code before writing to prevent build failures
class Ai::CodeValidator
  VALID_TAILWIND_SHADOWS = %w[sm md lg xl 2xl inner none]
  VALID_TAILWIND_TEXT_SIZES = %w[xs sm base lg xl 2xl 3xl 4xl 5xl 6xl 7xl 8xl 9xl]
  VALID_TAILWIND_ROUNDED = %w[none sm md lg xl 2xl 3xl full]
  
  # Common invalid classes AI might generate
  INVALID_CLASS_REPLACEMENTS = {
    'shadow-3xl' => 'shadow-2xl',
    'shadow-4xl' => 'shadow-2xl', 
    'shadow-5xl' => 'shadow-2xl',
    'text-10xl' => 'text-9xl',
    'text-11xl' => 'text-9xl',
    'rounded-4xl' => 'rounded-3xl',
    'rounded-5xl' => 'rounded-3xl',
    'rounded-6xl' => 'rounded-3xl'
  }.freeze
  
  def self.validate_and_fix_css(content)
    return content if content.blank?
    
    fixed_content = content.dup
    replacements_made = []
    
    INVALID_CLASS_REPLACEMENTS.each do |invalid, valid|
      if fixed_content.include?(invalid)
        fixed_content.gsub!(invalid, valid)
        replacements_made << "#{invalid} → #{valid}"
      end
    end
    
    if replacements_made.any?
      Rails.logger.warn "[AI_VALIDATOR] Fixed invalid CSS classes: #{replacements_made.join(', ')}"
    end
    
    fixed_content
  end
  
  def self.validate_jsx_syntax(content, file_path = nil)
    return { valid: true } if content.blank?
    
    errors = []
    
    # Check for mismatched JSX tags
    tag_stack = []
    tag_regex = /<\/?([A-Z][A-Za-z]*)[^>]*>/
    
    content.scan(tag_regex) do |match|
      tag_name = match[0]
      full_match = Regexp.last_match[0]
      
      if full_match.start_with?('</')
        # Closing tag
        if tag_stack.empty?
          errors << "Unexpected closing tag </#{tag_name}>"
        elsif tag_stack.last != tag_name
          errors << "Mismatched closing tag </#{tag_name}>, expected </#{tag_stack.last}>"
        else
          tag_stack.pop
        end
      elsif !full_match.end_with?('/>')
        # Opening tag (not self-closing)
        tag_stack.push(tag_name)
      end
    end
    
    if tag_stack.any?
      errors << "Unclosed tags: #{tag_stack.join(', ')}"
    end
    
    # Check for common React mistakes
    if content.include?('class=') && !content.include?('className=')
      errors << "Using 'class' instead of 'className' in JSX"
    end
    
    if errors.any?
      Rails.logger.error "[AI_VALIDATOR] JSX validation failed#{file_path ? " for #{file_path}" : ""}: #{errors.join('; ')}"
      return { valid: false, errors: errors }
    end
    
    { valid: true }
  end
  
  def self.validate_typescript(content, file_path = nil)
    return { valid: true } if content.blank?
    
    errors = []
    
    # Check for missing return in function components
    if content.match?(/export\s+(default\s+)?function\s+\w+.*?\{/)
      function_bodies = content.scan(/export\s+(?:default\s+)?function\s+\w+[^{]*\{([^}]*)\}/m)
      function_bodies.each do |body|
        unless body[0].include?('return')
          errors << "Function component missing return statement"
        end
      end
    end
    
    # Check for incorrect useState syntax
    if content.match?(/const\s+\w+\s*=\s*useState\(/) && !content.match?(/const\s+\[\w+,\s*set\w+\]\s*=\s*useState\(/)
      errors << "Incorrect useState destructuring syntax"
    end
    
    if errors.any?
      Rails.logger.warn "[AI_VALIDATOR] TypeScript issues found#{file_path ? " in #{file_path}" : ""}: #{errors.join('; ')}"
    end
    
    { valid: errors.empty?, errors: errors }
  end
  
  def self.validate_file(content, file_path)
    return content if content.blank?
    
    case File.extname(file_path)
    when '.css'
      validate_and_fix_css(content)
    when '.jsx', '.tsx'
      result = validate_jsx_syntax(content, file_path)
      if result[:valid]
        validate_typescript(content, file_path)
        content
      else
        # Attempt to fix or reject
        Rails.logger.error "[AI_VALIDATOR] Cannot auto-fix JSX errors in #{file_path}"
        raise "Invalid JSX syntax in #{file_path}: #{result[:errors].join('; ')}"
      end
    when '.ts', '.js'
      validate_typescript(content, file_path)
      content
    else
      content
    end
  end
end