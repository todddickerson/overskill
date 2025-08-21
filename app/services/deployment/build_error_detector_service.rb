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
    
    # Match JSX syntax errors like the Calculator.tsx issue we just fixed
    jsx_tag_mismatch = log_content.scan(/Error: (.+):(\d+):(\d+): Unexpected closing '(.+)' tag does not match opening '(.+)' tag/)
    
    jsx_tag_mismatch.each do |file, line, col, closing_tag, opening_tag|
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
    
    # Match other JSX syntax errors
    jsx_syntax_errors = log_content.scan(/Error: (.+):(\d+):(\d+): (.+JSX.+)/)
    
    jsx_syntax_errors.each do |file, line, col, message|
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
    
    # Detect unclosed JSX tags
    unclosed_jsx = log_content.scan(/Error: (.+):(\d+):(\d+): Expected corresponding JSX closing tag for <(.+)>/)
    
    unclosed_jsx.each do |file, line, col, tag|
      errors << {
        type: :jsx_unclosed_tag,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: "Expected corresponding JSX closing tag for <#{tag}>",
        tag_name: tag,
        severity: :high
      }
    end
    
    errors
  end
  
  def detect_typescript_errors(log_content)
    errors = []
    
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
      else
        :typescript_error
      end
      
      errors << {
        type: error_type,
        file: extract_relative_path(file),
        line: line.to_i,
        column: col.to_i,
        message: message,
        severity: :medium
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
end