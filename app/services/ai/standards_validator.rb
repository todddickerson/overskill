module Ai
  class StandardsValidator
    attr_reader :app, :validation_errors, :validation_warnings
    
    def initialize(app)
      @app = app
      @validation_errors = []
      @validation_warnings = []
    end
    
    def validate_against_standards!
      Rails.logger.info "[StandardsValidator] Validating app #{@app.id} against AI_APP_STANDARDS"
      
      @validation_errors = []
      @validation_warnings = []
      
      # Core validation checks
      validate_react_spa_structure
      validate_file_extensions
      validate_required_files
      validate_external_dependencies
      validate_authentication_requirements
      validate_code_quality
      validate_accessibility
      validate_responsive_design
      
      # Return validation result
      {
        valid: @validation_errors.empty?,
        errors: @validation_errors,
        warnings: @validation_warnings,
        score: calculate_standards_score
      }
    end
    
    private
    
    def validate_react_spa_structure
      """Ensure app follows React SPA structure requirements"""
      
      # Check for required React structure
      index_html = @app.app_files.find { |f| f.path == 'index.html' }
      unless index_html
        @validation_errors << "Missing required index.html entry point"
        return
      end
      
      # Validate index.html has React CDN scripts
      html_content = index_html.content.to_s
      unless html_content.include?('react') || html_content.include?('React')
        @validation_errors << "index.html missing React CDN scripts"
      end
      
      unless html_content.include?('babel') || html_content.include?('Babel')
        @validation_errors << "index.html missing Babel transformer for JSX"
      end
      
      # Check for main React components
      app_jsx = @app.app_files.find { |f| f.path.include?('App.jsx') }
      unless app_jsx
        @validation_warnings << "Missing src/App.jsx main component (recommended structure)"
      end
      
      main_jsx = @app.app_files.find { |f| f.path.include?('main.jsx') }
      unless main_jsx
        @validation_warnings << "Missing src/main.jsx entry point (recommended structure)"
      end
    end
    
    def validate_file_extensions
      """Ensure all React files use .jsx, never .tsx"""
      
      typescript_files = @app.app_files.select { |f| f.path.end_with?('.tsx', '.ts') }
      typescript_files.each do |file|
        @validation_errors << "File #{file.path} uses TypeScript extension - must use .jsx/.js only"
      end
      
      # Check for React components that should be .jsx
      js_components = @app.app_files.select do |f| 
        f.path.end_with?('.js') && f.content.to_s.include?('jsx')
      end
      
      js_components.each do |file|
        @validation_warnings << "File #{file.path} contains JSX but uses .js extension - should be .jsx"
      end
    end
    
    def validate_required_files
      """Check for essential files per standards"""
      
      required_files = {
        'index.html' => 'HTML entry point',
        'src/index.css' => 'Global styles and Tailwind imports (recommended)'
      }
      
      required_files.each do |path, description|
        unless @app.app_files.any? { |f| f.path == path }
          if path == 'index.html'
            @validation_errors << "Missing required file: #{path} (#{description})"
          else
            @validation_warnings << "Missing recommended file: #{path} (#{description})"
          end
        end
      end
      
      # Check for at least one JavaScript/JSX file
      js_files = @app.app_files.select { |f| f.path.end_with?('.js', '.jsx') }
      if js_files.empty?
        @validation_errors << "No JavaScript/JSX files found - React apps require JavaScript"
      end
    end
    
    def validate_external_dependencies
      """Validate only approved external resources are used"""
      
      approved_cdns = [
        'cdn.tailwindcss.com',
        'fonts.googleapis.com', 'fonts.gstatic.com',
        'unpkg.com', 'cdn.jsdelivr.net', 'cdnjs.cloudflare.com',
        'supabase.co'
      ]
      
      unapproved_deps = []
      
      @app.app_files.each do |file|
        content = file.content.to_s
        
        # Extract URLs from content
        urls = content.scan(/https?:\/\/([\w.-]+)/).flatten
        
        urls.each do |domain|
          unless approved_cdns.any? { |cdn| domain.include?(cdn) }
            unapproved_deps << { file: file.path, domain: domain }
          end
        end
      end
      
      unapproved_deps.each do |dep|
        @validation_warnings << "File #{dep[:file]} uses unapproved external resource: #{dep[:domain]}"
      end
    end
    
    def validate_authentication_requirements
      """Check if apps with user data have authentication"""
      
      # Look for patterns indicating user-specific data
      user_data_patterns = [
        /user_id|userId/,
        /auth\.(user|session)/,
        /(create|add|save|post).*\w+/i,
        /supabase.*insert/,
        /\btodos?\b|\bnotes?\b|\bposts?\b/i
      ]
      
      has_user_data = @app.app_files.any? do |file|
        content = file.content.to_s
        user_data_patterns.any? { |pattern| content.match?(pattern) }
      end
      
      if has_user_data
        # Check for authentication component
        auth_files = @app.app_files.select do |f|
          f.path.downcase.include?('auth') || 
          f.content.to_s.include?('supabase.auth') ||
          f.content.to_s.include?('signIn') ||
          f.content.to_s.include?('signUp')
        end
        
        if auth_files.empty?
          @validation_errors << "App appears to handle user data but missing authentication component (required per standards)"
        else
          Rails.logger.info "[StandardsValidator] Found auth files: #{auth_files.map(&:path).join(', ')}"
        end
      end
    end
    
    def validate_code_quality
      """Check for code quality issues"""
      
      @app.app_files.each do |file|
        next unless file.path.end_with?('.js', '.jsx')
        
        content = file.content.to_s
        
        # Check for TypeScript syntax in JS files
        if content.match?(/:\s*(string|number|boolean|any|void)\s*[;,\)\}=]/) ||
           content.match?(/interface\s+\w+\s*\{/)
          @validation_errors << "File #{file.path} contains TypeScript syntax - must be pure JavaScript/JSX"
        end
        
        # Check for proper React patterns
        if content.include?('React.createElement') && !content.include?('babel')
          @validation_warnings << "File #{file.path} uses React.createElement - consider JSX syntax instead"
        end
        
        # Check for proper imports
        if content.match?(/import.*from.*react/) && !content.match?(/useState|useEffect|Component/)
          @validation_warnings << "File #{file.path} imports React but doesn't appear to use React features"
        end
        
        # Check for console.log statements (should be removed in production)
        if content.include?('console.log')
          @validation_warnings << "File #{file.path} contains console.log statements - consider removing for production"
        end
      end
    end
    
    def validate_accessibility
      """Check for accessibility compliance"""
      
      html_files = @app.app_files.select { |f| f.path.end_with?('.html', '.jsx', '.js') }
      
      html_files.each do |file|
        content = file.content.to_s
        
        # Check for semantic HTML elements
        if content.include?('<div') && !content.match?(/<(header|main|section|article|aside|nav|footer)/)
          @validation_warnings << "File #{file.path} uses divs but missing semantic HTML elements (header, main, section, etc.)"
        end
        
        # Check for images without alt text
        if content.match?(/<img[^>]*(?!alt=)[^>]*>/)
          @validation_warnings << "File #{file.path} has images without alt attributes - required for accessibility"
        end
        
        # Check for proper form labels
        if content.include?('<input') && !content.include?('label') && !content.include?('aria-label')
          @validation_warnings << "File #{file.path} has inputs without labels or aria-labels - required for accessibility"
        end
      end
    end
    
    def validate_responsive_design
      """Check for mobile-first responsive design"""
      
      css_files = @app.app_files.select { |f| f.path.end_with?('.css') || f.content.to_s.include?('className') }
      
      has_responsive_classes = css_files.any? do |file|
        content = file.content.to_s
        # Check for Tailwind responsive classes or media queries
        content.match?(/\b(sm|md|lg|xl|2xl):/) || content.include?('@media')
      end
      
      unless has_responsive_classes
        @validation_warnings << "App missing responsive design classes - should be mobile-first with Tailwind breakpoints"
      end
      
      # Check for viewport meta tag in HTML
      index_html = @app.app_files.find { |f| f.path == 'index.html' }
      if index_html && !index_html.content.to_s.include?('viewport')
        @validation_errors << "index.html missing viewport meta tag - required for mobile responsiveness"
      end
    end
    
    def calculate_standards_score
      """Calculate compliance score (0-100)"""
      total_checks = 10  # Number of validation categories
      error_weight = -10
      warning_weight = -2
      
      base_score = 100
      penalty = (@validation_errors.length * error_weight) + (@validation_warnings.length * warning_weight)
      
      score = [base_score + penalty, 0].max
      Rails.logger.info "[StandardsValidator] Standards score: #{score}% (#{@validation_errors.length} errors, #{@validation_warnings.length} warnings)"
      
      score
    end
  end
end