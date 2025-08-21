class Deployment::AutoFixService
  def initialize(app)
    @app = app
  end
  
  def apply_fix(error)
    Rails.logger.info "[AutoFixService] Attempting to fix #{error[:type]} in #{error[:file]}"
    
    case error[:type]
    when :jsx_tag_mismatch
      fix_jsx_tag_mismatch(error)
    when :jsx_unclosed_tag
      fix_jsx_unclosed_tag(error)
    when :jsx_syntax_error
      fix_jsx_syntax_error(error)
    when :module_not_found, :missing_import
      fix_import_error(error)
    when :property_not_found
      fix_property_not_found(error)
    when :undefined_variable
      fix_undefined_variable(error)
    when :invalid_tailwind_class
      fix_invalid_tailwind_class(error)
    when :dependency_resolution_error, :dependency_conflict
      fix_dependency_error(error)
    else
      { success: false, error: "No fix available for error type: #{error[:type]}" }
    end
  rescue => e
    Rails.logger.error "[AutoFixService] Error applying fix: #{e.message}"
    { success: false, error: "Exception while applying fix: #{e.message}" }
  end
  
  private
  
  def fix_jsx_tag_mismatch(error)
    app_file = find_app_file(error[:file])
    return { success: false, error: "File not found: #{error[:file]}" } unless app_file
    
    content = app_file.content
    lines = content.split("\n")
    
    # Try to fix the specific tag mismatch
    target_line = lines[error[:line] - 1]
    
    if target_line.include?("</#{error[:closing_tag]}>")
      # Replace the incorrect closing tag with the correct one
      fixed_line = target_line.gsub("</#{error[:closing_tag]}>", "</#{error[:opening_tag]}>")
      lines[error[:line] - 1] = fixed_line
      
      new_content = lines.join("\n")
      app_file.update!(content: new_content)
      
      return {
        success: true,
        description: "Fixed JSX tag mismatch: changed </#{error[:closing_tag]}> to </#{error[:opening_tag]}>",
        changes: [
          {
            file: error[:file],
            line: error[:line],
            old: target_line,
            new: fixed_line
          }
        ]
      }
    end
    
    # Try to find and remove duplicate closing tags (like the Calculator.tsx issue)
    if error[:closing_tag] == "div" && error[:opening_tag] == "div"
      fixed_content = fix_duplicate_div_tags(content)
      if fixed_content != content
        app_file.update!(content: fixed_content)
        return {
          success: true,
          description: "Removed duplicate div closing tags",
          changes: [
            {
              file: error[:file],
              description: "Cleaned up duplicate div tags"
            }
          ]
        }
      end
    end
    
    { success: false, error: "Could not determine appropriate fix for JSX tag mismatch" }
  end
  
  def fix_jsx_unclosed_tag(error)
    app_file = find_app_file(error[:file])
    return { success: false, error: "File not found: #{error[:file]}" } unless app_file
    
    content = app_file.content
    lines = content.split("\n")
    
    # Find the line with the unclosed tag and add the closing tag
    target_line_index = error[:line] - 1
    
    # Look for self-closing tag pattern that should be closed
    if lines[target_line_index].include?("<#{error[:tag_name]}") && 
       !lines[target_line_index].include?("/>") && 
       !lines[target_line_index].include?("</#{error[:tag_name]}>")
      
      # Find the next appropriate location to add the closing tag
      indent = lines[target_line_index][/^\s*/]
      closing_tag = "#{indent}</#{error[:tag_name]}>"
      
      # Insert closing tag after finding the logical end
      insertion_index = find_tag_insertion_point(lines, target_line_index, error[:tag_name])
      lines.insert(insertion_index, closing_tag)
      
      new_content = lines.join("\n")
      app_file.update!(content: new_content)
      
      return {
        success: true,
        description: "Added missing closing tag </#{error[:tag_name]}>",
        changes: [
          {
            file: error[:file],
            line: insertion_index + 1,
            added: closing_tag
          }
        ]
      }
    end
    
    { success: false, error: "Could not determine where to place closing tag" }
  end
  
  def fix_jsx_syntax_error(error)
    app_file = find_app_file(error[:file])
    return { success: false, error: "File not found: #{error[:file]}" } unless app_file
    
    content = app_file.content
    
    # Try common JSX syntax fixes
    fixes_applied = []
    
    # Fix common JSX attribute issues
    if error[:message].include?("class") && error[:message].include?("className")
      fixed_content = content.gsub(/\bclass=/, 'className=')
      if fixed_content != content
        app_file.update!(content: fixed_content)
        fixes_applied << "Changed 'class' attributes to 'className'"
      end
    end
    
    # Fix unclosed JSX expressions
    if error[:message].include?("Unterminated JSX contents")
      # This is complex and might require AI assistance
      return { success: false, error: "Unterminated JSX contents require manual intervention" }
    end
    
    if fixes_applied.any?
      return {
        success: true,
        description: fixes_applied.join(", "),
        changes: [{ file: error[:file], description: fixes_applied.join(", ") }]
      }
    end
    
    { success: false, error: "No automatic fix available for this JSX syntax error" }
  end
  
  def fix_import_error(error)
    # Try to fix common import path issues
    app_file = find_app_file(error[:file])
    return { success: false, error: "File not found: #{error[:file]}" } unless app_file
    
    content = app_file.content
    module_name = error[:module_name]
    
    # Check if it's a relative import that needs fixing
    if module_name.start_with?('./') || module_name.start_with?('../')
      # Try to find the actual file and fix the path
      fixed_import = find_correct_import_path(error[:file], module_name)
      if fixed_import
        fixed_content = content.gsub("'#{module_name}'", "'#{fixed_import}'")
        fixed_content = fixed_content.gsub("\"#{module_name}\"", "\"#{fixed_import}\"")
        
        if fixed_content != content
          app_file.update!(content: fixed_content)
          return {
            success: true,
            description: "Fixed import path from '#{module_name}' to '#{fixed_import}'",
            changes: [
              {
                file: error[:file],
                old: module_name,
                new: fixed_import
              }
            ]
          }
        end
      end
    end
    
    # Check if it's a missing file extension
    if !module_name.include?('.') && (module_name.start_with?('./') || module_name.start_with?('../'))
      extensions = ['.tsx', '.ts', '.jsx', '.js']
      extensions.each do |ext|
        test_path = module_name + ext
        if file_exists_in_app?(test_path, error[:file])
          fixed_content = content.gsub("'#{module_name}'", "'#{test_path}'")
          fixed_content = fixed_content.gsub("\"#{module_name}\"", "\"#{test_path}\"")
          
          if fixed_content != content
            app_file.update!(content: fixed_content)
            return {
              success: true,
              description: "Added missing file extension: #{module_name}#{ext}",
              changes: [
                {
                  file: error[:file],
                  old: module_name,
                  new: test_path
                }
              ]
            }
          end
        end
      end
    end
    
    { success: false, error: "Could not automatically fix import error" }
  end
  
  def fix_property_not_found(error)
    # This typically requires adding type definitions or interfaces
    # For now, we'll focus on common React props issues
    
    if error[:message].include?("does not exist on type") && error[:message].include?("props")
      return { success: false, error: "Property errors on props require manual type definition" }
    end
    
    { success: false, error: "Property not found errors require manual intervention" }
  end
  
  def fix_undefined_variable(error)
    app_file = find_app_file(error[:file])
    return { success: false, error: "File not found: #{error[:file]}" } unless app_file
    
    content = app_file.content
    
    # Extract variable name from error message
    variable_match = error[:message].match(/Cannot find name '(.+)'/)
    return { success: false, error: "Could not extract variable name" } unless variable_match
    
    variable_name = variable_match[1]
    
    # Check if it's a common React hook that needs importing
    react_hooks = ['useState', 'useEffect', 'useContext', 'useReducer', 'useMemo', 'useCallback']
    if react_hooks.include?(variable_name)
      # Add to existing React import or create new one
      if content.include?("import React")
        # Add to existing import
        fixed_content = content.gsub(
          /import React(?:, \{([^}]+)\})? from ['"]react['"];?/,
          "import React, { \\1, #{variable_name} } from 'react';"
        )
        # Clean up any double commas
        fixed_content = fixed_content.gsub(/, ,/, ',').gsub(/\{ ,/, '{ ')
      else
        # Add new import at the top
        fixed_content = "import React, { #{variable_name} } from 'react';\n" + content
      end
      
      if fixed_content != content
        app_file.update!(content: fixed_content)
        return {
          success: true,
          description: "Added missing React hook import: #{variable_name}",
          changes: [
            {
              file: error[:file],
              description: "Added #{variable_name} to React imports"
            }
          ]
        }
      end
    end
    
    { success: false, error: "Could not automatically fix undefined variable" }
  end
  
  def fix_invalid_tailwind_class(error)
    # This would require checking against Tailwind CSS class list
    # For now, we'll log it but not attempt automatic fixes
    { success: false, error: "Tailwind class fixes require manual intervention" }
  end
  
  def fix_dependency_error(error)
    # Dependency conflicts typically require package.json changes
    # This is complex and should be handled manually
    { success: false, error: "Dependency conflicts require manual package.json modifications" }
  end
  
  # Helper methods
  
  def find_app_file(file_path)
    # Try exact match first
    app_file = @app.app_files.find_by(path: file_path)
    return app_file if app_file
    
    # Try with src/ prefix
    app_file = @app.app_files.find_by(path: "src/#{file_path}")
    return app_file if app_file
    
    # Try finding by filename if path doesn't match exactly
    filename = File.basename(file_path)
    @app.app_files.find { |f| f.path.end_with?(filename) }
  end
  
  def fix_duplicate_div_tags(content)
    # Remove duplicate div closing tags (like the Calculator.tsx issue we fixed)
    lines = content.split("\n")
    
    # Look for patterns like:
    # </Button>
    #   </div>
    # </CardContent>
    # Where the middle </div> is likely a duplicate
    
    fixed_lines = []
    skip_next = false
    
    lines.each_with_index do |line, index|
      if skip_next
        skip_next = false
        next
      end
      
      # Check if this is a standalone </div> that might be duplicate
      if line.strip == "</div>" && index > 0 && index < lines.length - 1
        prev_line = lines[index - 1].strip
        next_line = lines[index + 1].strip
        
        # If it's between two other closing tags, it's likely duplicate
        if prev_line.match(/^<\/\w+>$/) && next_line.match(/^<\/\w+>$/)
          # Skip this line (don't add it to fixed_lines)
          next
        end
      end
      
      fixed_lines << line
    end
    
    fixed_lines.join("\n")
  end
  
  def find_tag_insertion_point(lines, start_index, tag_name)
    # Simple heuristic: find the next closing tag at the same indentation level
    original_indent = lines[start_index][/^\s*/]
    
    (start_index + 1...lines.length).each do |i|
      line = lines[i]
      current_indent = line[/^\s*/]
      
      # If we find a closing tag at the same or lesser indentation, insert before it
      if line.include?('</') && current_indent.length <= original_indent.length
        return i
      end
    end
    
    # If we can't find a good spot, insert at the end
    lines.length
  end
  
  def find_correct_import_path(current_file, import_path)
    # Try to resolve relative imports
    current_dir = File.dirname(current_file)
    resolved_path = File.join(current_dir, import_path)
    
    # Check if any app files match this path
    extensions = ['.tsx', '.ts', '.jsx', '.js', '']
    extensions.each do |ext|
      test_path = resolved_path + ext
      if @app.app_files.any? { |f| f.path.end_with?(test_path.sub(/^\.\//, '')) }
        return import_path + ext
      end
    end
    
    nil
  end
  
  def file_exists_in_app?(relative_path, current_file)
    current_dir = File.dirname(current_file)
    resolved_path = File.expand_path(relative_path, current_dir)
    
    @app.app_files.any? { |f| File.expand_path(f.path).end_with?(resolved_path) }
  end
end