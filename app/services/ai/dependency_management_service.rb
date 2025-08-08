# PHASE 2 ENHANCEMENT: Dependency Management Service
# Provides automated npm package management for Pro Mode apps (TypeScript/Vite)
# Detects needed dependencies and manages package.json automatically

module Ai
  class DependencyManagementService
    include Rails.application.routes.url_helpers
    
    # Common dependencies for different features
    DEPENDENCY_MAP = {
      # React ecosystem
      'useState' => ['react', 'react-dom'],
      'useEffect' => ['react', 'react-dom'],
      'useContext' => ['react', 'react-dom'],
      'useReducer' => ['react', 'react-dom'],
      'useMemo' => ['react', 'react-dom'],
      'useCallback' => ['react', 'react-dom'],
      'useRef' => ['react', 'react-dom'],
      
      # Router
      'react-router' => ['react-router-dom'],
      'BrowserRouter' => ['react-router-dom'],
      'Route' => ['react-router-dom'],
      'Link' => ['react-router-dom'],
      'Navigate' => ['react-router-dom'],
      'useNavigate' => ['react-router-dom'],
      'useParams' => ['react-router-dom'],
      
      # Icons
      'Lucide' => ['lucide-react'],
      'HeroIcon' => ['@heroicons/react'],
      'FeatherIcon' => ['react-feather'],
      
      # UI Libraries
      'Button' => [], # Could be custom or from library
      'Modal' => [],
      'Dialog' => [],
      'Dropdown' => [],
      
      # Forms
      'useForm' => ['react-hook-form'],
      'zodResolver' => ['@hookform/resolvers', 'zod'],
      'yup' => ['yup'],
      'formik' => ['formik'],
      
      # HTTP
      'axios' => ['axios'],
      'fetch' => [], # Native
      'swr' => ['swr'],
      'react-query' => ['@tanstack/react-query'],
      
      # Date/Time
      'dayjs' => ['dayjs'],
      'moment' => ['moment'],
      'date-fns' => ['date-fns'],
      
      # Charts
      'Chart.js' => ['chart.js', 'react-chartjs-2'],
      'recharts' => ['recharts'],
      
      # Animation
      'framer-motion' => ['framer-motion'],
      'react-spring' => ['@react-spring/web'],
      
      # Utilities
      'lodash' => ['lodash'],
      'clsx' => ['clsx'],
      'classnames' => ['classnames'],
      'uuid' => ['uuid'],
      
      # State Management
      'zustand' => ['zustand'],
      'redux' => ['@reduxjs/toolkit', 'react-redux'],
      'jotai' => ['jotai'],
      'valtio' => ['valtio'],
      
      # TypeScript (for Pro Mode)
      'typescript' => ['typescript', '@types/react', '@types/react-dom', '@types/node'],
      
      # Build Tools (for Pro Mode)
      'vite' => ['vite', '@vitejs/plugin-react'],
      'webpack' => ['webpack', 'webpack-cli', '@babel/core', '@babel/preset-react'],
      'parcel' => ['parcel'],
      
      # Testing
      'jest' => ['jest', '@testing-library/react', '@testing-library/jest-dom'],
      'vitest' => ['vitest', '@testing-library/react'],
      'cypress' => ['cypress']
    }.freeze
    
    # Base dependencies for Pro Mode apps
    BASE_PRO_DEPENDENCIES = {
      'dependencies' => {
        'react' => '^18.2.0',
        'react-dom' => '^18.2.0'
      },
      'devDependencies' => {
        'vite' => '^5.0.0',
        '@vitejs/plugin-react' => '^4.0.0',
        'typescript' => '^5.0.0',
        '@types/react' => '^18.2.0',
        '@types/react-dom' => '^18.2.0',
        '@types/node' => '^20.0.0',
        'tailwindcss' => '^3.3.0',
        'autoprefixer' => '^10.4.0',
        'postcss' => '^8.4.0'
      }
    }.freeze
    
    attr_reader :app, :mode, :detected_dependencies
    
    def initialize(app, mode: :instant)
      @app = app
      @mode = mode  # :instant (CDN) or :pro (npm packages)
      @detected_dependencies = []
    end
    
    def self.analyze_and_manage_dependencies(app, mode: :instant)
      service = new(app, mode: mode)
      service.analyze_and_manage
    end
    
    def self.detect_dependencies_in_code(code_content)
      service = new(nil)
      service.detect_dependencies_from_content(code_content)
    end
    
    def analyze_and_manage
      Rails.logger.info "[DependencyManagementService] Analyzing dependencies for #{@app.name} (#{@mode} mode)"
      
      begin
        # Only manage dependencies for Pro Mode
        if @mode == :instant
          Rails.logger.info "[DependencyManagementService] Instant mode - using CDN, no npm management needed"
          return {
            success: true,
            mode: :instant,
            message: "Instant mode uses CDN - no package management required",
            dependencies: []
          }
        end
        
        # Analyze app files for dependency needs
        dependencies_needed = analyze_app_dependencies
        
        # Check current package.json
        current_package_json = find_package_json
        
        # Generate updated package.json
        updated_package_json = generate_package_json(dependencies_needed, current_package_json)
        
        # Update package.json file
        package_result = update_package_json_file(updated_package_json)
        
        # Generate install commands
        install_commands = generate_install_commands(dependencies_needed)
        
        Rails.logger.info "[DependencyManagementService] Detected #{dependencies_needed.size} dependencies for Pro Mode"
        
        {
          success: true,
          mode: :pro,
          dependencies: dependencies_needed,
          package_json_updated: package_result[:updated],
          install_commands: install_commands,
          recommendations: generate_recommendations(dependencies_needed),
          message: "Analyzed #{dependencies_needed.size} dependencies for Pro Mode"
        }
      rescue => e
        Rails.logger.error "[DependencyManagementService] Dependency management failed: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        
        {
          success: false,
          error: e.message,
          message: "Dependency analysis failed: #{e.message}"
        }
      end
    end
    
    def detect_dependencies_from_content(code_content)
      """
      Analyze code content and detect needed dependencies.
      Used for real-time dependency detection during AI generation.
      """
      dependencies = []
      
      # Check imports first (most reliable)
      import_matches = code_content.scan(/import\s+.*?\s+from\s+['"]([^'"]+)['"]/)
      import_matches.each do |match|
        package_name = match[0]
        next if package_name.start_with?('.', '/') # Skip relative imports
        
        # Extract base package name
        base_package = package_name.split('/')[0]
        base_package = base_package.gsub(/^@/, '') if base_package.start_with?('@')
        
        dependencies << {
          package: base_package,
          full_package: package_name,
          source: 'import_statement',
          confidence: 'high'
        }
      end
      
      # Check for function/hook usage patterns
      DEPENDENCY_MAP.each do |pattern, packages|
        if code_content.match?(/\b#{Regexp.escape(pattern)}\b/)
          packages.each do |package|
            dependencies << {
              package: package,
              source: "usage_of_#{pattern}",
              confidence: 'medium'
            }
          end
        end
      end
      
      # Remove duplicates
      dependencies.uniq { |dep| dep[:package] }
    end
    
    private
    
    def analyze_app_dependencies
      all_dependencies = []
      
      # Analyze all app files
      @app.app_files.each do |file|
        next unless file.content.present?
        
        # Skip non-JavaScript files
        next unless file.file_type.in?(['js', 'jsx', 'ts', 'tsx'])
        
        file_dependencies = detect_dependencies_from_content(file.content)
        
        # Add file context to dependencies
        file_dependencies.each do |dep|
          dep[:detected_in] = file.path
          all_dependencies << dep
        end
      end
      
      # Group by package and merge info
      grouped_dependencies = all_dependencies.group_by { |dep| dep[:package] }
      
      final_dependencies = grouped_dependencies.map do |package, deps|
        {
          package: package,
          version: get_recommended_version(package),
          dependency_type: get_dependency_type(package),
          detected_in_files: deps.map { |d| d[:detected_in] }.uniq,
          sources: deps.map { |d| d[:source] }.uniq,
          confidence: calculate_confidence(deps)
        }
      end
      
      # Sort by confidence and relevance
      final_dependencies.sort_by { |dep| [-confidence_score(dep[:confidence]), dep[:package]] }
    end
    
    def find_package_json
      package_json_file = @app.app_files.find_by(path: 'package.json')
      
      if package_json_file&.content.present?
        begin
          JSON.parse(package_json_file.content)
        rescue JSON::ParserError => e
          Rails.logger.warn "[DependencyManagementService] Invalid package.json: #{e.message}"
          nil
        end
      else
        nil
      end
    end
    
    def generate_package_json(dependencies_needed, current_package_json = nil)
      # Start with base or existing package.json
      package_json = if current_package_json
        current_package_json.deep_dup
      else
        {
          "name" => @app.name.parameterize,
          "version" => "1.0.0",
          "description" => @app.description || "Generated by OverSkill",
          "type" => "module",
          "scripts" => {
            "dev" => "vite",
            "build" => "tsc && vite build",
            "preview" => "vite preview",
            "typecheck" => "tsc --noEmit"
          }
        }
      end
      
      # Ensure base structure exists
      package_json['dependencies'] ||= {}
      package_json['devDependencies'] ||= {}
      
      # Add base Pro Mode dependencies
      BASE_PRO_DEPENDENCIES['dependencies'].each do |pkg, version|
        package_json['dependencies'][pkg] ||= version
      end
      
      BASE_PRO_DEPENDENCIES['devDependencies'].each do |pkg, version|
        package_json['devDependencies'][pkg] ||= version
      end
      
      # Add detected dependencies
      dependencies_needed.each do |dep|
        dep_type = dep[:dependency_type] || 'dependencies'
        package_json[dep_type][dep[:package]] ||= dep[:version]
      end
      
      # Sort dependencies alphabetically
      package_json['dependencies'] = package_json['dependencies'].sort.to_h
      package_json['devDependencies'] = package_json['devDependencies'].sort.to_h
      
      package_json
    end
    
    def update_package_json_file(package_json_content)
      package_json_file = @app.app_files.find_by(path: 'package.json')
      json_content = JSON.pretty_generate(package_json_content)
      
      if package_json_file
        # Update existing file
        old_content = package_json_file.content
        package_json_file.update!(
          content: json_content,
          size_bytes: json_content.bytesize
        )
        
        Rails.logger.info "[DependencyManagementService] Updated existing package.json"
        { updated: true, created: false, changed: old_content != json_content }
      else
        # Create new file
        @app.app_files.create!(
          path: 'package.json',
          content: json_content,
          file_type: 'json',
          size_bytes: json_content.bytesize,
          team: @app.team
        )
        
        Rails.logger.info "[DependencyManagementService] Created new package.json"
        { updated: true, created: true, changed: true }
      end
    end
    
    def generate_install_commands(dependencies)
      return [] if dependencies.empty?
      
      # Group by dependency type
      regular_deps = dependencies.select { |d| d[:dependency_type] == 'dependencies' }
      dev_deps = dependencies.select { |d| d[:dependency_type] == 'devDependencies' }
      
      commands = []
      
      if regular_deps.any?
        packages = regular_deps.map { |d| "#{d[:package]}@#{d[:version]}" }.join(' ')
        commands << {
          command: "npm install #{packages}",
          description: "Install production dependencies",
          packages: regular_deps.map { |d| d[:package] }
        }
      end
      
      if dev_deps.any?
        packages = dev_deps.map { |d| "#{d[:package]}@#{d[:version]}" }.join(' ')
        commands << {
          command: "npm install --save-dev #{packages}",
          description: "Install development dependencies",
          packages: dev_deps.map { |d| d[:package] }
        }
      end
      
      # Add convenience commands
      commands << {
        command: "npm install",
        description: "Install all dependencies from package.json",
        packages: []
      }
      
      commands
    end
    
    def generate_recommendations(dependencies)
      recommendations = []
      
      # Check for missing essential dependencies
      has_react = dependencies.any? { |d| d[:package] == 'react' }
      has_typescript = dependencies.any? { |d| d[:package] == 'typescript' }
      
      if has_react && !has_typescript
        recommendations << {
          type: 'suggestion',
          message: 'Consider adding TypeScript for better development experience',
          action: 'Add TypeScript support with npm install --save-dev typescript @types/react @types/react-dom'
        }
      end
      
      # Check for conflicting packages
      state_management_packages = dependencies.select { |d| d[:package].in?(['redux', 'zustand', 'jotai', 'valtio']) }
      if state_management_packages.size > 1
        recommendations << {
          type: 'warning',
          message: 'Multiple state management libraries detected',
          action: "Consider using just one: #{state_management_packages.map { |d| d[:package] }.join(', ')}"
        }
      end
      
      # Check for testing setup
      has_testing = dependencies.any? { |d| d[:package].in?(['jest', 'vitest', '@testing-library/react']) }
      unless has_testing
        recommendations << {
          type: 'suggestion',
          message: 'Consider adding testing framework',
          action: 'Add testing with npm install --save-dev vitest @testing-library/react @testing-library/jest-dom'
        }
      end
      
      recommendations
    end
    
    def get_recommended_version(package_name)
      # Common package versions (could be fetched from npm registry in production)
      VERSION_MAP = {
        'react' => '^18.2.0',
        'react-dom' => '^18.2.0',
        'typescript' => '^5.0.0',
        'vite' => '^5.0.0',
        '@vitejs/plugin-react' => '^4.0.0',
        'tailwindcss' => '^3.3.0',
        'react-router-dom' => '^6.8.0',
        'axios' => '^1.6.0',
        'lodash' => '^4.17.0',
        'dayjs' => '^1.11.0',
        'lucide-react' => '^0.300.0',
        '@heroicons/react' => '^2.0.0',
        'framer-motion' => '^10.0.0',
        'zustand' => '^4.4.0',
        '@tanstack/react-query' => '^4.0.0',
        'react-hook-form' => '^7.48.0',
        'zod' => '^3.22.0'
      }.freeze
      
      VERSION_MAP[package_name] || 'latest'
    end
    
    def get_dependency_type(package_name)
      # Determine if package should be in dependencies or devDependencies
      DEV_DEPENDENCIES = %w[
        typescript vite @vitejs/plugin-react
        @types/react @types/react-dom @types/node
        tailwindcss autoprefixer postcss
        jest vitest @testing-library/react @testing-library/jest-dom
        cypress eslint prettier
        @babel/core @babel/preset-react webpack webpack-cli
      ].freeze
      
      DEV_DEPENDENCIES.include?(package_name) ? 'devDependencies' : 'dependencies'
    end
    
    def calculate_confidence(deps)
      # Higher confidence if detected from imports vs usage patterns
      import_deps = deps.count { |d| d[:source] == 'import_statement' }
      usage_deps = deps.size - import_deps
      
      if import_deps > 0
        'high'
      elsif usage_deps > 1
        'medium'
      else
        'low'
      end
    end
    
    def confidence_score(confidence)
      case confidence
      when 'high' then 3
      when 'medium' then 2
      when 'low' then 1
      else 0
      end
    end
  end
end