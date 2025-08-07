module Ai
  # Smart code search service with regex patterns and file filtering
  # Similar to Lovable's lov-search-files tool
  class SmartSearchService
    MAX_RESULTS = 100
    MAX_FILE_SIZE = 1.megabyte
    
    def initialize(app)
      @app = app
    end
    
    # Search across app files using regex patterns with filtering
    # Similar to Lovable's lov-search-files tool
    def search_files(query:, include_pattern: nil, exclude_pattern: nil, case_sensitive: false, context_lines: 2)
      results = []
      
      begin
        # Build regex pattern
        regex_flags = case_sensitive ? 0 : Regexp::IGNORECASE
        search_regex = Regexp.new(query, regex_flags)
        
        # Get all app files
        files = @app.app_files.includes(:app)
        
        # Apply file filtering
        if include_pattern
          include_glob = File.fnmatch_pattern(include_pattern)
          files = files.select { |file| include_glob.match?(file.path) }
        end
        
        if exclude_pattern
          exclude_glob = File.fnmatch_pattern(exclude_pattern)
          files = files.reject { |file| exclude_glob.match?(file.path) }
        end
        
        files.each do |file|
          next if file.size_bytes > MAX_FILE_SIZE # Skip large files
          next unless file.content.present?
          
          file_results = search_in_file(file, search_regex, context_lines)
          results.concat(file_results) if file_results.any?
          
          break if results.length >= MAX_RESULTS
        end
        
        {
          success: true,
          results: results.take(MAX_RESULTS),
          total_files_searched: files.count,
          query: query,
          case_sensitive: case_sensitive
        }
        
      rescue RegexpError => e
        {
          success: false,
          error: "Invalid regex pattern: #{e.message}",
          query: query
        }
      rescue => e
        Rails.logger.error "[SmartSearch] Search error: #{e.message}"
        {
          success: false,
          error: "Search failed: #{e.message}",
          query: query
        }
      end
    end
    
    # Search for component definitions (React components, functions, etc.)
    def search_components(component_name, component_type: :react)
      case component_type
      when :react
        query = "(?:function\\s+#{component_name}|const\\s+#{component_name}\\s*=|class\\s+#{component_name})"
      when :function
        query = "(?:function\\s+#{component_name}|const\\s+#{component_name}\\s*=.*=>)"
      when :class
        query = "class\\s+#{component_name}"
      else
        query = component_name
      end
      
      search_files(
        query: query,
        include_pattern: "src/**/*.{js,jsx,ts,tsx}",
        case_sensitive: true
      )
    end
    
    # Search for imports/exports of a specific module
    def search_imports(module_name)
      query = "(?:import.*from\\s*['\"].*#{module_name}|export.*#{module_name})"
      
      search_files(
        query: query,
        include_pattern: "src/**/*.{js,jsx,ts,tsx}",
        case_sensitive: false
      )
    end
    
    # Search for CSS classes or styles
    def search_styles(class_name_or_property)
      query = "(?:\\.#{class_name_or_property}|#{class_name_or_property}\\s*:)"
      
      search_files(
        query: query,
        include_pattern: "**/*.{css,scss,sass,less}",
        case_sensitive: false
      )
    end
    
    # Search for API calls or endpoints
    def search_api_calls(endpoint_pattern)
      query = "(?:fetch\\s*\\(|axios\\.|api\\.).*#{endpoint_pattern}"
      
      search_files(
        query: query,
        include_pattern: "src/**/*.{js,jsx,ts,tsx}",
        case_sensitive: false
      )
    end
    
    # Search for specific hook usage (useState, useEffect, etc.)
    def search_hooks(hook_name)
      query = "#{hook_name}\\s*\\("
      
      search_files(
        query: query,
        include_pattern: "src/**/*.{js,jsx,ts,tsx}",
        case_sensitive: true
      )
    end
    
    private
    
    # Search within a single file and return matches with context
    def search_in_file(file, regex, context_lines)
      lines = file.content.lines
      matches = []
      
      lines.each_with_index do |line, line_number|
        if line.match?(regex)
          # Get context lines before and after
          start_line = [0, line_number - context_lines].max
          end_line = [lines.length - 1, line_number + context_lines].min
          
          context = lines[start_line..end_line].map.with_index(start_line) do |context_line, ctx_line_num|
            {
              line_number: ctx_line_num + 1,
              content: context_line.chomp,
              is_match: ctx_line_num == line_number
            }
          end
          
          # Find all matches in the line for highlighting
          line_matches = line.scan(regex).flatten
          
          matches << {
            file_path: file.path,
            file_type: file.file_type,
            line_number: line_number + 1,
            line_content: line.chomp,
            matches: line_matches,
            context: context
          }
        end
      end
      
      matches
    end
    
    # Helper to convert glob patterns to regex (simplified)
    def self.glob_to_regex(pattern)
      # Convert glob pattern to regex
      # This is a simplified implementation - could use a gem like 'fnmatch' for full support
      escaped = Regexp.escape(pattern)
      regex_pattern = escaped
        .gsub('\*\*', '.*')  # ** matches any path
        .gsub('\*', '[^/]*') # * matches any filename chars except /
        .gsub('\?', '[^/]')  # ? matches any single char except /
        .gsub('\{', '(')     # { starts group
        .gsub('\}', ')')     # } ends group
        .gsub(',', '|')      # , is OR in groups
      
      Regexp.new("\\A#{regex_pattern}\\z")
    end
  end
  
  # Monkey patch File class to add fnmatch pattern matching
  class File
    def self.fnmatch_pattern(pattern)
      SmartSearchService.glob_to_regex(pattern)
    end
  end
end