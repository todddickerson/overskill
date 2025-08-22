class Deployment::BuildErrorDetectorService
  def initialize(app)
    @app = app
  end
  
  def analyze_build_errors(error_logs)
    Rails.logger.info "[BuildErrorDetector] Analyzing build errors for app #{@app.id}"
    
    detected_errors = []
    
    error_logs.each do |log|
      log_content = log[:logs]
      
      # Detect various types of build errors
      detected_errors.concat(detect_jsx_syntax_errors(log_content))
      detected_errors.concat(detect_typescript_errors(log_content))
      detected_errors.concat(detect_import_errors(log_content))
      detected_errors.concat(detect_css_errors(log_content))
      detected_errors.concat(detect_dependency_errors(log_content))
    end
    
    Rails.logger.info "[BuildErrorDetector] Detected #{detected_errors.length} fixable errors"
    detected_errors
  end
  
  private
  
  def detect_jsx_syntax_errors(log_content)
    errors = []
    
    # Modern TypeScript compiler error format: ##[error]src/pages/File.tsx(line,col): error TSxxxx: message
    modern_ts_errors = log_content.scan(/##\[error\]([^(]+)\((\d+),(\d+)\): error TS\d+: (.+)/)
    
    modern_ts_errors.each do |file, line, col, message|
      error_type = case message
      when /JSX element '(.+)' has no corresponding closing tag/
        :jsx_unclosed_tag
      when /Unexpected closing '(.+)' tag does not match opening '(.+)' tag/
        :jsx_tag_mismatch
      when /Expected corresponding JSX closing tag for '(.+)'/
        :jsx_unclosed_tag
      when /JSX expression expected/
        :jsx_expression_error
      when /Cannot read properties of undefined/
        :undefined_property_access
      when /JSX/i
        :jsx_syntax_error
      when /'\)' expected/
        :missing_parenthesis
      when /';' expected/
        :missing_semicolon
      when /Expression expected/
        :invalid_expression
      when /Declaration or statement expected/
        :invalid_statement
      when /Unterminated string literal/
        :unterminated_string
      when /Unexpected token/
        :unexpected_token
      else
        next # Skip non-JSX errors, handle in detect_typescript_errors
      end
      
      # Extract tag name for unclosed tag errors
      tag_name = case message
      when /JSX element '(.+)' has no corresponding closing tag/
        $1
      when /Expected corresponding JSX closing tag for '(.+)'/
        $1
      when /Unexpected closing '(.+)' tag does not match opening '(.+)' tag/
        $2 # The opening tag name
      else
        nil
      end
      
      # Extract additional context for better auto-fixing
      context = extract_error_context(message)
      
      errors << {
        type: error_type,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: message,
        tag_name: tag_name,
        context: context,
        severity: :high,
        auto_fixable: auto_fixable_error?(error_type, message)
      }
    end
    
    # Legacy error format support (keep for compatibility)
    jsx_tag_mismatch = log_content.scan(/Error: (.+):(\d+):(\d+): Unexpected closing '(.+)' tag does not match opening '(.+)' tag/)
    
    jsx_tag_mismatch.each do |file, line, col, closing_tag, opening_tag|
      # Skip if already found by modern format
      next if errors.any? { |e| e[:file] == extract_relative_path(file) && e[:line] == line.to_i }
      
      errors << {
        type: :jsx_tag_mismatch,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: "Unexpected closing '#{closing_tag}' tag does not match opening '#{opening_tag}' tag",
        closing_tag: closing_tag,
        opening_tag: opening_tag,
        severity: :high
      }
    end
    
    # Legacy JSX syntax errors
    jsx_syntax_errors = log_content.scan(/Error: (.+):(\d+):(\d+): (.+JSX.+)/)
    
    jsx_syntax_errors.each do |file, line, col, message|
      # Skip if already found by modern format
      next if errors.any? { |e| e[:file] == extract_relative_path(file) && e[:line] == line.to_i }
      
      errors << {
        type: :jsx_syntax_error,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: message,
        severity: :high
      }
    end
    
    errors
  end
  
  def detect_typescript_errors(log_content)
    errors = []
    
    # Modern TypeScript error format for React import errors
    # ##[error]src/pages/Upsell.tsx(14,3): error TS2686: 'React' refers to a UMD global
    react_import_errors = log_content.scan(/##\[error\]([^(]+)\((\d+),(\d+)\): error TS2686: 'React' refers to a UMD global/)
    
    react_import_errors.each do |file, line, col|
      errors << {
        type: :missing_react_import,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: "'React' refers to a UMD global, but the current file is a module",
        severity: :high,
        auto_fixable: true
      }
    end
    
    # TypeScript type errors
    ts_errors = log_content.scan(/Error: (.+\.tsx?):(\d+):(\d+): (.+)/)
    
    ts_errors.each do |file, line, col, message|
      # Skip if we already found a JSX error for this location
      next if errors.any? { |e| e[:file] == extract_relative_path(file) && e[:line] == line.to_i }
      
      error_type = case message
      when /Property '(.+)' does not exist on type/
        :property_not_found
      when /Cannot find name '(.+)'/
        :undefined_variable
      when /Type '(.+)' is not assignable to type '(.+)'/
        :type_mismatch
      when /Expected \d+ arguments, but got \d+/
        :argument_count_mismatch
      when /'React' refers to a UMD global/
        :missing_react_import
      else
        :typescript_error
      end
      
      errors << {
        type: error_type,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: message,
        severity: error_type == :missing_react_import ? :high : :medium,
        auto_fixable: error_type == :missing_react_import
      }
    end
    
    errors
  end
  
  def detect_import_errors(log_content)
    errors = []
    
    # Module not found errors
    import_errors = log_content.scan(/Error: Cannot resolve module '(.+)' from '(.+)'/)
    
    import_errors.each do |module_name, file|
      errors << {
        type: :module_not_found,
        file: extract_relative_path(file),
        message: "Cannot resolve module '#{module_name}'",
        module_name: module_name,
        severity: :high
      }
    end
    
    # Relative import errors
    relative_import_errors = log_content.scan(/Error: (.+): Cannot find module '(.+)' or its corresponding type declarations/)
    
    relative_import_errors.each do |file, module_name|
      errors << {
        type: :missing_import,
        file: extract_relative_path(file),
        message: "Cannot find module '#{module_name}' or its type declarations",
        module_name: module_name,
        severity: :medium
      }
    end
    
    errors
  end
  
  def detect_css_errors(log_content)
    errors = []
    
    # CSS syntax errors
    css_errors = log_content.scan(/Error: (.+\.css):(\d+):(\d+): (.+)/)
    
    css_errors.each do |file, line, col, message|
      errors << {
        type: :css_syntax_error,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: message,
        severity: :low
      }
    end
    
    # Tailwind CSS class errors (if using Tailwind)
    if log_content.include?('tailwind')
      tailwind_errors = log_content.scan(/warn - The utility `(.+)` is not available/)
      
      tailwind_errors.each do |class_name|
        errors << {
          type: :invalid_tailwind_class,
          message: "The utility '#{class_name}' is not available",
          class_name: class_name.first,
          severity: :low
        }
      end
    end
    
    errors
  end
  
  def detect_dependency_errors(log_content)
    errors = []
    
    # Package.json dependency issues
    dependency_errors = log_content.scan(/npm ERR! (.+)/)
    
    dependency_errors.each do |message|
      case message.first
      when /Cannot resolve dependency/
        errors << {
          type: :dependency_resolution_error,
          message: message.first,
          severity: :high
        }
      when /ERESOLVE unable to resolve dependency tree/
        errors << {
          type: :dependency_conflict,
          message: message.first,
          severity: :high
        }
      end
    end
    
    errors
  end
  
  def extract_relative_path(absolute_path)
    # Convert absolute paths to relative paths from the project root
    # e.g., "/github/workspace/src/components/Calculator.tsx" -> "src/components/Calculator.tsx"
    path_parts = absolute_path.split('/')
    
    # Look for common project indicators
    if path_parts.include?('workspace')
      workspace_index = path_parts.index('workspace')
      return path_parts[(workspace_index + 1)..-1].join('/')
    end
    
    # Look for src, components, pages, etc.
    common_dirs = ['src', 'components', 'pages', 'lib', 'utils', 'app']
    common_dirs.each do |dir|
      if path_parts.include?(dir)
        dir_index = path_parts.index(dir)
        return path_parts[dir_index..-1].join('/')
      end
    end
    
    # If we can't find a good starting point, return the filename
    File.basename(absolute_path)
  end
  
  def extract_error_context(message)
    context = {}
    
    # Extract closing tag name from mismatch errors
    if match = message.match(/Unexpected closing '(.+)' tag does not match opening '(.+)' tag/)
      context[:closing_tag] = match[1]
      context[:opening_tag] = match[2]
    end
    
    # Extract expected vs actual from other error types
    if match = message.match(/Expected '(.+)' but got '(.+)'/)
      context[:expected] = match[1]
      context[:actual] = match[2]
    end
    
    # Extract property names from property access errors
    if match = message.match(/Property '(.+)' does not exist/)
      context[:property_name] = match[1]
    end
    
    context
  end
  
  def auto_fixable_error?(error_type, message)
    case error_type
    when :jsx_unclosed_tag, :jsx_tag_mismatch
      true # We have good heuristics for these
    when :missing_semicolon, :missing_parenthesis
      true # Simple syntax fixes
    when :unterminated_string
      true # Can usually be fixed by adding closing quote
    when :missing_react_import
      true # Can always be fixed by adding React import
    when :jsx_expression_error
      message.include?('className') || message.include?('style') # Common JSX attribute issues
    when :undefined_property_access
      false # Usually requires type definition changes
    when :jsx_syntax_error
      # Only if it's a simple JSX attribute issue
      message.include?('className') || message.include?('class=')
    else
      false # Conservative approach for unknown error types
    end
  end
end