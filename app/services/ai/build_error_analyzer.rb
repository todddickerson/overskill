module Ai
  # Service to analyze build errors and generate AI-friendly fix instructions
  class BuildErrorAnalyzer
    
    # Common TypeScript/build errors and their solutions
    ERROR_PATTERNS = {
      # Module resolution errors
      /Cannot find module ['"](@\/[^'"]+)['"]/ => {
        type: :missing_module,
        category: 'import_resolution',
        extract: ->(match) { { module: match[1] } },
        solution: 'Check if the file exists at the expected path or if TypeScript paths are configured correctly'
      },
      
      # TypeScript path alias issues
      /Cannot find module ['"]@\// => {
        type: :path_alias_not_configured,
        category: 'typescript_config',
        solution: 'TypeScript paths configuration missing in tsconfig.json'
      },
      
      # Property doesn't exist errors
      /Property ['"](\w+)['"] does not exist on type/ => {
        type: :missing_property,
        category: 'type_error',
        extract: ->(match) { { property: match[1] } },
        solution: 'Add type declaration or interface for the missing property'
      },
      
      # Missing dependencies
      /Module not found: Error: Can't resolve ['"]([^'"]+)['"]/ => {
        type: :missing_dependency,
        category: 'npm_package',
        extract: ->(match) { { package: match[1] } },
        solution: 'Install the missing npm package'
      },
      
      # JSX/React errors
      /JSX element type .+ does not have any construct or call signatures/ => {
        type: :invalid_jsx_element,
        category: 'react_component',
        solution: 'Component is not properly exported or imported'
      },
      
      # Composite project errors
      /must have setting "composite": true/ => {
        type: :tsconfig_composite,
        category: 'typescript_config',
        solution: 'Add "composite": true to the referenced tsconfig file'
      },
      
      # Type errors
      /Type '(.+)' is not assignable to type '(.+)'/ => {
        type: :type_mismatch,
        category: 'type_error',
        extract: ->(match) { { from_type: match[1], to_type: match[2] } },
        solution: 'Fix type mismatch between expected and actual types'
      },
      
      # Unused variables
      /'(\w+)' is declared but its value is never read/ => {
        type: :unused_variable,
        category: 'code_quality',
        extract: ->(match) { { variable: match[1] } },
        solution: 'Remove unused variable or prefix with underscore'
      },
      
      # Duplicate identifiers
      /Duplicate identifier ['"](\w+)['"]/ => {
        type: :duplicate_identifier,
        category: 'code_error',
        extract: ->(match) { { identifier: match[1] } },
        solution: 'Rename one of the duplicate identifiers'
      }
    }.freeze
    
    def initialize(build_output)
      @build_output = build_output
      @errors = []
      @files_with_errors = {}
    end
    
    def analyze
      parse_errors
      categorize_errors
      result = generate_fix_strategy
      result[:ai_prompt] = generate_ai_prompt(result[:strategies])
      result
    end
    
    private
    
    def parse_errors
      # Extract individual error lines
      error_lines = @build_output.split("\n").select do |line|
        line.include?('error TS') || line.include?('Error:') || line.include?('error:')
      end
      
      error_lines.each do |line|
        # Parse file path and error message
        if line =~ /^(.+?)\((\d+),(\d+)\):\s*error\s+(?:TS\d+:\s*)?(.+)$/
          file = $1
          line_num = $2.to_i
          col_num = $3.to_i
          message = $4
          
          @files_with_errors[file] ||= []
          @files_with_errors[file] << {
            line: line_num,
            column: col_num,
            message: message,
            full_line: line
          }
          
          # Match against patterns
          ERROR_PATTERNS.each do |pattern, config|
            if message =~ pattern
              error_info = {
                file: file,
                line: line_num,
                column: col_num,
                message: message,
                type: config[:type],
                category: config[:category],
                solution: config[:solution]
              }
              
              # Extract additional data if extractor provided
              if config[:extract] && (match = message.match(pattern))
                error_info[:extracted] = config[:extract].call(match)
              end
              
              @errors << error_info
              break # Stop after first match
            end
          end
        end
      end
    end
    
    def categorize_errors
      @error_categories = @errors.group_by { |e| e[:category] }
      @error_types = @errors.group_by { |e| e[:type] }
    end
    
    def generate_fix_strategy
      strategies = []
      
      # Check for TypeScript path alias issues (most common)
      if @error_types[:path_alias_not_configured] || has_many_module_errors?
        strategies << {
          priority: 1,
          action: 'fix_typescript_paths',
          description: 'Add TypeScript paths configuration to tsconfig.json',
          fix: {
            file: 'tsconfig.json',
            changes: {
              add_to_compiler_options: {
                "baseUrl" => ".",
                "paths" => {
                  "@/*" => ["./src/*"]
                }
              }
            }
          }
        }
      end
      
      # Check for composite configuration issues
      if @error_types[:tsconfig_composite]
        strategies << {
          priority: 1,
          action: 'fix_tsconfig_composite',
          description: 'Fix composite setting in tsconfig.node.json',
          fix: {
            file: 'tsconfig.node.json',
            changes: {
              add_to_compiler_options: {
                "composite" => true,
                "noEmit" => false
              }
            }
          }
        }
      end
      
      # Check for missing npm packages
      missing_packages = @errors
        .select { |e| e[:type] == :missing_dependency }
        .map { |e| e[:extracted][:package] if e[:extracted] }
        .compact.uniq
      
      if missing_packages.any?
        strategies << {
          priority: 2,
          action: 'install_packages',
          description: 'Install missing npm packages',
          packages: missing_packages
        }
      end
      
      # Check for missing properties on window/global objects
      if @error_types[:missing_property]
        window_props = @errors
          .select { |e| e[:message].include?('Window') }
          .map { |e| e[:extracted][:property] if e[:extracted] }
          .compact.uniq
        
        if window_props.any?
          strategies << {
            priority: 3,
            action: 'add_type_declarations',
            description: 'Add missing type declarations',
            properties: window_props
          }
        end
      end
      
      {
        total_errors: @errors.count,
        files_affected: @files_with_errors.keys.count,
        categories: @error_categories.transform_values(&:count),
        types: @error_types.transform_values(&:count),
        strategies: strategies.sort_by { |s| s[:priority] },
        errors_summary: summarize_errors,
        can_auto_fix: can_auto_fix?
      }
    end
    
    def has_many_module_errors?
      module_errors = @errors.select { |e| e[:type] == :missing_module }
      module_errors.count > 5 && module_errors.all? { |e| e[:message].include?('@/') }
    end
    
    def summarize_errors
      summary = []
      
      # Group by error type for summary
      @error_types.each do |type, errors|
        case type
        when :missing_module
          modules = errors.map { |e| e[:extracted][:module] if e[:extracted] }.compact.uniq
          summary << "Missing #{modules.count} module imports: #{modules.first(5).join(', ')}#{'...' if modules.count > 5}"
        when :path_alias_not_configured
          summary << "TypeScript path alias '@/' is not configured (#{errors.count} errors)"
        when :missing_property
          props = errors.map { |e| e[:extracted][:property] if e[:extracted] }.compact.uniq
          summary << "Missing #{props.count} properties: #{props.first(3).join(', ')}#{'...' if props.count > 3}"
        when :missing_dependency
          packages = errors.map { |e| e[:extracted][:package] if e[:extracted] }.compact.uniq
          summary << "Missing #{packages.count} npm packages: #{packages.join(', ')}"
        when :type_mismatch
          summary << "#{errors.count} type mismatch errors"
        when :unused_variable
          summary << "#{errors.count} unused variables"
        else
          summary << "#{errors.count} #{type.to_s.humanize.downcase} errors"
        end
      end
      
      summary
    end
    
    def can_auto_fix?
      # These error types can be automatically fixed
      auto_fixable = [:path_alias_not_configured, :tsconfig_composite, :missing_dependency, :unused_variable]
      
      # Check if majority of errors are auto-fixable
      fixable_count = @errors.count { |e| auto_fixable.include?(e[:type]) }
      fixable_count > (@errors.count * 0.5)
    end
    
    def generate_ai_prompt(strategies = nil)
      prompt = "The TypeScript/Vite build failed with the following errors:\n\n"
      
      # Add error summary
      prompt += "ERROR SUMMARY:\n"
      summarize_errors.each { |s| prompt += "- #{s}\n" }
      prompt += "\n"
      
      # Add specific errors grouped by file
      prompt += "DETAILED ERRORS BY FILE:\n"
      @files_with_errors.each do |file, errors|
        prompt += "\n#{file}:\n"
        errors.first(5).each do |error|
          prompt += "  Line #{error[:line]}: #{error[:message]}\n"
        end
        prompt += "  ... and #{errors.count - 5} more errors\n" if errors.count > 5
      end
      
      # Add suggested fixes if provided
      prompt += "\nSUGGESTED FIXES:\n"
      strategies ||= []
      strategies.each_with_index do |strategy, i|
        prompt += "#{i + 1}. #{strategy[:description]}\n"
        if strategy[:fix]
          prompt += "   File: #{strategy[:fix][:file]}\n"
          prompt += "   Changes: #{strategy[:fix][:changes].to_json}\n"
        elsif strategy[:packages]
          prompt += "   Packages: #{strategy[:packages].join(', ')}\n"
        end
      end
      
      prompt += "\nPlease fix these errors by:\n"
      prompt += "1. First, ensure TypeScript paths are configured correctly in tsconfig.json\n"
      prompt += "2. Install any missing npm packages\n"
      prompt += "3. Fix any remaining type errors or missing imports\n"
      prompt += "4. Ensure all files that are imported actually exist\n"
      
      prompt
    end
  end
end