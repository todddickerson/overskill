module Ai
  # Service for managing app-specific context that changes frequently
  # Real-time context with no caching - always fresh
  class AppContextService
    
    # Files to prioritize when building app context
    HIGH_PRIORITY_PATTERNS = [
      /^src\/pages\//,           # Page components (business logic)
      /^src\/features\//,        # Feature modules (business logic)
      /^src\/services\//,        # Business services
      /^src\/api\//,             # API endpoints
      /^src\/stores\//,          # State management
      /^src\/contexts\//,        # React contexts
      /^src\/hooks\/(?!use-)/,   # Custom hooks (exclude generic ones)
      /^src\/components\/(?!ui)/ # Custom components (exclude UI library)
    ].freeze
    
    # Files to deprioritize (usually generic utilities)
    LOW_PRIORITY_PATTERNS = [
      /^src\/lib\/utils/,        # Generic utilities
      /^src\/lib\/cn/,           # Class name utilities  
      /^src\/types\//,           # Type definitions
      /^src\/components\/ui\//,  # UI library components
      /^src\/hooks\/use-/        # Generic hooks
    ].freeze
    
    def initialize
      @token_counter = TokenCountingService.new
      @dependency_analyzer = ModernDependencyAnalyzer.new
    end
    
    # Build app-specific context with smart file selection
    def build_app_context(app, focus_files = [], budget_manager)
      Rails.logger.info "[AppContext] Building context for app #{app.id} (#{app.app_files.count} total files)"
      
      context = []
      
      # Add app header
      app_header = build_app_header(app)
      if budget_manager.can_add_content?(:system_context, app_header)
        budget_manager.add_content(:system_context, app_header, "App header")
        context << app_header
      end
      
      # Get candidate files using smart selection
      candidate_files = get_relevant_app_files(app, focus_files)
      Rails.logger.info "[AppContext] Selected #{candidate_files.count} candidate files from #{app.app_files.count} total"
      
      # Select files within budget using priority scoring
      relevance_scores = calculate_app_file_scores(candidate_files, focus_files, app)
      selected_files = budget_manager.select_files_within_budget(
        candidate_files,
        :app_context,
        relevance_scores
      )
      
      if selected_files.any?
        # Group files by category for better organization
        grouped_files = group_app_files_by_category(selected_files)
        
        grouped_files.each do |category, files|
          next if files.empty?
          
          context << "## #{category}"
          context << ""
          
          files.each do |file|
            add_app_file_to_context(context, file)
          end
        end
      end
      
      # Add dependency insights if helpful
      dependency_insights = build_dependency_insights(selected_files, app)
      if dependency_insights && budget_manager.can_add_content?(:system_context, dependency_insights)
        budget_manager.add_content(:system_context, dependency_insights, "Dependency insights")
        context << dependency_insights
      end
      
      final_content = context.join("\n")
      tokens_used = @token_counter.count_tokens(final_content)
      
      Rails.logger.info "[AppContext] Built app context: #{tokens_used} tokens (#{selected_files.count} files)"
      Rails.logger.info "[AppContext] File priorities: #{log_file_priorities(selected_files, relevance_scores)}"
      
      final_content
    end
    
    # Get files that are most relevant for the current context
    def get_relevant_app_files(app, focus_files = [])
      relevant_files = Set.new
      
      # 1. Always include focus files if provided
      focus_files.each do |focus_file|
        if focus_file.is_a?(String)
          file = app.app_files.find_by(path: focus_file)
          relevant_files << file if file
        else
          relevant_files << focus_file
        end
      end
      
      # 2. Include recently modified files (active development)
      recent_files = app.app_files
                        .where('updated_at > ?', 2.hours.ago)
                        .order(updated_at: :desc)
                        .limit(8)
      relevant_files.merge(recent_files)
      
      # 3. Include high-priority pattern files
      high_priority_files = app.app_files.select do |file|
        HIGH_PRIORITY_PATTERNS.any? { |pattern| file.path.match?(pattern) }
      end
      relevant_files.merge(high_priority_files.take(12))
      
      # 4. Include dependencies of focus files
      focus_files.each do |focus_file|
        dependencies = @dependency_analyzer.find_smart_dependencies(app, focus_file, max_depth: 2)
        relevant_files.merge(dependencies.take(5))  # Limit dependencies per focus file
      end
      
      # 5. Exclude low-priority files unless they're focus files
      focus_file_paths = focus_files.map { |f| f.is_a?(String) ? f : f.path }
      filtered_files = relevant_files.reject do |file|
        LOW_PRIORITY_PATTERNS.any? { |pattern| file.path.match?(pattern) } &&
        !focus_file_paths.include?(file.path)
      end
      
      Rails.logger.debug "[AppContext] File selection: #{relevant_files.count} candidates -> #{filtered_files.count} after filtering"
      
      filtered_files.to_a.uniq.compact
    end
    
    private
    
    def build_app_header(app)
      lines = []
      lines << ""
      lines << "# App-Specific Context"
      lines << "**App**: #{app.name}"
      lines << "**Description**: #{app.description}" if app.description.present?
      lines << ""
      lines << "## Real-time Context (No caching)"
      lines << "This context contains the current state of the app's custom files."
      lines << "These files change frequently and are not cached."
      lines << ""
      
      lines.join("\n")
    end
    
    def calculate_app_file_scores(files, focus_files, app)
      scores = {}
      focus_paths = focus_files.map { |f| f.is_a?(String) ? f : f.path }
      
      files.each do |file|
        score = 1.0
        
        # Highest priority: Focus files
        if focus_paths.include?(file.path)
          score = 10.0
        end
        
        # High priority: Business logic patterns
        HIGH_PRIORITY_PATTERNS.each do |pattern|
          if file.path.match?(pattern)
            score = [score, 5.0].max
            break
          end
        end
        
        # Medium priority: Recently modified
        if file.updated_at > 1.hour.ago
          score *= 1.8
        elsif file.updated_at > 24.hours.ago
          score *= 1.3
        end
        
        # Boost for files with meaningful business logic
        if file.content && has_business_logic?(file.content)
          score *= 1.4
        end
        
        # Lower priority: Generic/utility files
        LOW_PRIORITY_PATTERNS.each do |pattern|
          if file.path.match?(pattern)
            score *= 0.3
            break
          end
        end
        
        # Penalize very large files (may be generated or boilerplate)
        if file.content && file.content.length > 10_000
          score *= 0.6
        end
        
        scores[file.path] = score
      end
      
      scores
    end
    
    def has_business_logic?(content)
      # Look for patterns that indicate business logic vs boilerplate
      business_patterns = [
        /async function/i,         # Async operations
        /fetch\(/,                 # API calls
        /useState|useEffect/,      # React hooks
        /\.map\(|\.filter\(/,      # Data processing
        /if\s*\([^)]*\)\s*{/,      # Conditional logic
        /switch\s*\(/,             # Switch statements
        /export\s+function/,       # Exported functions
        /const\s+\w+\s*=.*=>/      # Arrow functions
      ]
      
      business_patterns.any? { |pattern| content.match?(pattern) }
    end
    
    def group_app_files_by_category(files)
      categories = {
        'Business Logic Files' => [],
        'Page Components' => [],
        'Custom Components' => [],
        'Services & APIs' => [],
        'State Management' => [],
        'Configuration' => [],
        'Other Files' => []
      }
      
      files.each do |file|
        path = file.path
        
        case path
        when /^src\/pages\//
          categories['Page Components'] << file
        when /^src\/(features|services|api)\//
          categories['Services & APIs'] << file
        when /^src\/(stores|contexts)\//
          categories['State Management'] << file
        when /^src\/components\/(?!ui)/
          categories['Custom Components'] << file
        when /^src\/hooks\/(?!use-)/
          categories['Business Logic Files'] << file
        when /config|constant/
          categories['Configuration'] << file
        else
          categories['Other Files'] << file
        end
      end
      
      # Remove empty categories
      categories.select { |_, files| files.any? }
    end
    
    def add_app_file_to_context(context, file)
      context << "### #{file.path}"
      context << ""
      context << "```#{get_file_extension(file.path)}"
      
      # Add line numbers for consistency
      if file.content
        numbered_content = file.content.lines.map.with_index(1) do |line, num|
          "#{num.to_s.rjust(4)}: #{line}"
        end.join
        context << numbered_content.rstrip
      else
        context << "// File content not available"
      end
      
      context << "```"
      context << ""
    end
    
    def get_file_extension(file_path)
      ext = File.extname(file_path).downcase
      case ext
      when '.tsx', '.ts'
        'typescript'
      when '.jsx', '.js'
        'javascript'
      when '.json'
        'json'
      when '.css', '.scss'
        'css'
      else
        'text'
      end
    end
    
    def build_dependency_insights(selected_files, app)
      return nil if selected_files.count < 3
      
      lines = []
      lines << ""
      lines << "## Dependency Insights"
      
      # Find common import patterns
      import_counts = Hash.new(0)
      selected_files.each do |file|
        next unless file.content
        
        imports = file.content.scan(/import.*from\s+['"]([^'"]+)['"]/).flatten
        imports.each { |import_path| import_counts[import_path] += 1 }
      end
      
      # Show most common dependencies
      common_imports = import_counts.select { |_, count| count >= 2 }.sort_by { |_, count| -count }.first(5)
      
      if common_imports.any?
        lines << "**Common dependencies across selected files**:"
        common_imports.each do |import_path, count|
          lines << "- `#{import_path}` (used in #{count} files)"
        end
        lines << ""
      end
      
      return nil if lines.count <= 2
      lines.join("\n")
    end
    
    def log_file_priorities(selected_files, scores)
      selected_files.map do |file|
        score = scores[file.path] || 0
        "#{file.path}(#{score.round(1)})"
      end.join(', ')
    end
    
    # Simple dependency analyzer for this context
    class ModernDependencyAnalyzer
      def find_smart_dependencies(app, focus_file, max_depth: 2)
        return [] unless focus_file&.content
        
        dependencies = []
        processed = Set.new
        
        find_dependencies_recursive(app, focus_file, dependencies, processed, max_depth, 0)
        
        # Filter out generic UI components and utilities
        dependencies.reject do |dep|
          dep.path.match?(/^src\/(components\/ui|lib\/utils|types)\//i)
        end
      end
      
      private
      
      def find_dependencies_recursive(app, file, dependencies, processed, max_depth, current_depth)
        return if current_depth >= max_depth || processed.include?(file.path)
        
        processed << file.path
        
        # Extract local imports only
        imports = file.content.scan(/import.*from\s+['"]([^'"]+)['"]/).flatten
        local_imports = imports.select { |imp| imp.match?(/^\.\.?\/|^@\//) }
        
        local_imports.each do |import_path|
          resolved_path = resolve_import_path(file.path, import_path)
          dep_file = app.app_files.find_by(path: resolved_path)
          
          if dep_file && !processed.include?(dep_file.path)
            dependencies << dep_file
            find_dependencies_recursive(app, dep_file, dependencies, processed, max_depth, current_depth + 1)
          end
        end
      end
      
      def resolve_import_path(current_file_path, import_path)
        if import_path.start_with?('@/')
          import_path.sub('@/', 'src/')
        elsif import_path.start_with?('./')
          dir = File.dirname(current_file_path)
          File.join(dir, import_path.sub('./', ''))
        elsif import_path.start_with?('../')
          dir = File.dirname(current_file_path)
          File.expand_path(File.join(dir, import_path))
        else
          import_path
        end.then { |path| add_typescript_extension(path) }
      end
      
      def add_typescript_extension(path)
        return path if path.match?(/\.(tsx?|jsx?|json|css)$/)
        
        # Try common extensions
        %w[.tsx .ts .jsx .js].each do |ext|
          return "#{path}#{ext}"  # Return first extension (we'll validate existence later)
        end
        
        path
      end
    end
  end
end