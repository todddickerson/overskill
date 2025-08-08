# PHASE 1 ENHANCEMENT: Code Search Service 
# Provides intelligent code discovery like Lovable's lov-search-files tool
# Prevents duplicate component creation and improves code reuse

module Ai
  class CodeSearchService
    include Rails.application.routes.url_helpers
    
    attr_reader :app, :query, :include_pattern, :exclude_pattern, :case_sensitive
    
    def initialize(app, query, include_pattern: nil, exclude_pattern: nil, case_sensitive: false)
      @app = app
      @query = query
      @include_pattern = include_pattern
      @exclude_pattern = exclude_pattern
      @case_sensitive = case_sensitive
    end
    
    def self.search(app, query, include_pattern: nil, exclude_pattern: nil, case_sensitive: false)
      service = new(app, query, include_pattern, exclude_pattern, case_sensitive)
      service.execute
    end
    
    def execute
      Rails.logger.info "[CodeSearchService] Searching for '#{@query}' in #{@app.name}"
      Rails.logger.info "[CodeSearchService] Include: #{@include_pattern}, Exclude: #{@exclude_pattern}"
      
      begin
        # Get all app files
        files = @app.app_files.includes(:app)
        
        # Filter by include pattern
        files = apply_include_filter(files) if @include_pattern.present?
        
        # Filter by exclude pattern  
        files = apply_exclude_filter(files) if @exclude_pattern.present?
        
        # Search for the query in file contents
        matches = search_in_files(files)
        
        # Analyze matches for component discovery
        analyzed_matches = analyze_matches(matches)
        
        Rails.logger.info "[CodeSearchService] Found #{matches.size} matches across #{analyzed_matches[:unique_files]} files"
        
        {
          success: true,
          matches: matches,
          analysis: analyzed_matches,
          query: @query,
          total_files_searched: files.count,
          message: "Found #{matches.size} matches"
        }
      rescue => e
        Rails.logger.error "[CodeSearchService] Search failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        {
          success: false,
          error: e.message,
          matches: [],
          message: "Search failed: #{e.message}"
        }
      end
    end
    
    private
    
    def apply_include_filter(files)
      return files unless @include_pattern
      
      # Convert glob pattern to regex
      pattern_regex = glob_to_regex(@include_pattern)
      files.select { |file| file.path.match?(pattern_regex) }
    end
    
    def apply_exclude_filter(files)
      return files unless @exclude_pattern
      
      # Convert glob pattern to regex
      pattern_regex = glob_to_regex(@exclude_pattern)
      files.reject { |file| file.path.match?(pattern_regex) }
    end
    
    def glob_to_regex(glob_pattern)
      # Convert common glob patterns to regex
      regex_pattern = glob_pattern
        .gsub('**/', '.*/')  # ** matches any directory depth
        .gsub('*', '[^/]*')  # * matches any characters except /
        .gsub('?', '.')      # ? matches single character
      
      # Ensure it matches from start to end
      /^#{regex_pattern}$/
    end
    
    def search_in_files(files)
      matches = []
      regex_flags = @case_sensitive ? 0 : Regexp::IGNORECASE
      search_regex = Regexp.new(@query, regex_flags)
      
      files.each do |file|
        next if file.content.blank?
        
        # Split content into lines for precise matching
        lines = file.content.lines
        lines.each_with_index do |line, index|
          if line.match?(search_regex)
            # Get some context around the match
            context_start = [0, index - 2].max
            context_end = [lines.size - 1, index + 2].min
            context_lines = lines[context_start..context_end]
            
            matches << {
              file_path: file.path,
              file_type: file.file_type,
              line_number: index + 1,
              line_content: line.strip,
              match_text: extract_match_text(line, search_regex),
              context: context_lines.map.with_index { |ctx_line, ctx_idx| 
                {
                  line_number: context_start + ctx_idx + 1,
                  content: ctx_line.strip,
                  is_match: (context_start + ctx_idx) == index
                }
              }
            }
          end
        end
      end
      
      matches
    end
    
    def extract_match_text(line, regex)
      # Extract the specific text that matched
      match_data = line.match(regex)
      match_data ? match_data[0] : line.strip
    end
    
    def analyze_matches(matches)
      return { unique_files: 0, patterns: [], recommendations: [] } if matches.empty?
      
      unique_files = matches.map { |m| m[:file_path] }.uniq
      
      # Analyze common patterns
      patterns = analyze_patterns(matches)
      
      # Generate recommendations
      recommendations = generate_recommendations(matches, patterns)
      
      {
        unique_files: unique_files.size,
        file_paths: unique_files,
        patterns: patterns,
        recommendations: recommendations,
        most_frequent_file: find_most_frequent_file(matches),
        component_suggestions: find_component_suggestions(matches)
      }
    end
    
    def analyze_patterns(matches)
      patterns = []
      
      # Group by file type
      by_file_type = matches.group_by { |m| m[:file_type] }
      by_file_type.each do |file_type, type_matches|
        patterns << {
          type: "file_type",
          pattern: file_type,
          count: type_matches.size,
          description: "Found in #{type_matches.size} #{file_type} files"
        }
      end
      
      # Look for common function/component patterns
      function_matches = matches.select { |m| m[:line_content].match?(/function\s+\w+|const\s+\w+\s*=|class\s+\w+/) }
      if function_matches.any?
        patterns << {
          type: "functions",
          pattern: "function_definitions", 
          count: function_matches.size,
          description: "Found #{function_matches.size} function/component definitions"
        }
      end
      
      # Look for React component patterns
      react_matches = matches.select { |m| m[:line_content].match?(/React\.|useState|useEffect|return\s*\(?\s*</) }
      if react_matches.any?
        patterns << {
          type: "react_components",
          pattern: "react_patterns",
          count: react_matches.size,
          description: "Found #{react_matches.size} React component patterns"
        }
      end
      
      patterns
    end
    
    def generate_recommendations(matches, patterns)
      recommendations = []
      
      # If multiple files have similar patterns, suggest reuse
      file_counts = matches.group_by { |m| m[:file_path] }
      frequent_files = file_counts.select { |_, file_matches| file_matches.size > 2 }
      
      if frequent_files.any?
        frequent_files.each do |file_path, file_matches|
          recommendations << {
            type: "reuse_opportunity",
            message: "Consider reusing patterns from #{file_path} (#{file_matches.size} matches)",
            file_path: file_path,
            confidence: calculate_reuse_confidence(file_matches)
          }
        end
      end
      
      # If React components are found, suggest component extraction
      react_pattern = patterns.find { |p| p[:type] == "react_components" }
      if react_pattern && react_pattern[:count] > 1
        recommendations << {
          type: "component_extraction",
          message: "Multiple React components found - consider creating reusable components",
          confidence: "medium"
        }
      end
      
      # If no matches found, suggest it's safe to create new
      if matches.empty?
        recommendations << {
          type: "safe_to_create",
          message: "No existing patterns found - safe to create new component",
          confidence: "high"
        }
      end
      
      recommendations
    end
    
    def calculate_reuse_confidence(file_matches)
      # Higher confidence if matches are in component-like files
      component_files = file_matches.count { |m| m[:file_path].match?(/component|Component/) }
      util_files = file_matches.count { |m| m[:file_path].match?(/util|helper|lib/) }
      
      if component_files > 0 || util_files > 0
        "high"
      elsif file_matches.size > 3
        "medium"
      else
        "low"
      end
    end
    
    def find_most_frequent_file(matches)
      file_counts = matches.group_by { |m| m[:file_path] }
      most_frequent = file_counts.max_by { |_, file_matches| file_matches.size }
      
      if most_frequent
        {
          file_path: most_frequent[0],
          match_count: most_frequent[1].size
        }
      end
    end
    
    def find_component_suggestions(matches)
      suggestions = []
      
      # Look for existing components that might be reusable
      component_matches = matches.select do |m| 
        m[:line_content].match?(/const\s+\w*Component|function\s+\w*Component|class\s+\w*Component/) ||
        m[:file_path].match?(/component/i)
      end
      
      component_matches.each do |match|
        # Extract component name
        component_name = extract_component_name(match[:line_content])
        if component_name
          suggestions << {
            name: component_name,
            file_path: match[:file_path],
            line_number: match[:line_number],
            suggestion: "Consider reusing #{component_name} from #{match[:file_path]}"
          }
        end
      end
      
      suggestions.uniq { |s| s[:name] }
    end
    
    def extract_component_name(line)
      # Try to extract component name from different patterns
      patterns = [
        /const\s+(\w+)/,
        /function\s+(\w+)/,
        /class\s+(\w+)/,
        /export\s+(?:default\s+)?(?:const|function|class)\s+(\w+)/
      ]
      
      patterns.each do |pattern|
        match = line.match(pattern)
        return match[1] if match
      end
      
      nil
    end
  end
end