module Ai
  class AppValidator
    REQUIRED_DEPENDENCIES = {
      react: {
        cdns: [
          'https://unpkg.com/react@18/umd/react.production.min.js',
          'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js'
        ],
        required_for: ['react']
      },
      tailwind: {
        cdns: [
          'https://cdn.tailwindcss.com'
        ],
        required_for: ['react', 'vanilla']
      }
    }.freeze

    def self.validate_app_files(files, framework = 'react')
      errors = []
      warnings = []

      # Find index.html
      html_file = files.find { |f| f[:path] == 'index.html' || f[:type] == 'html' }
      
      if html_file.nil?
        errors << "Missing index.html file"
        return { valid: false, errors: errors, warnings: warnings }
      end

      html_content = html_file[:content]

      # Check for required dependencies based on framework
      REQUIRED_DEPENDENCIES.each do |dep_name, dep_config|
        next unless dep_config[:required_for].include?(framework)

        has_dependency = dep_config[:cdns].any? { |cdn| html_content.include?(cdn) }
        
        unless has_dependency
          errors << "Missing #{dep_name} CDN in index.html. Required: #{dep_config[:cdns].first}"
        end
      end

      # Check for common issues
      if framework == 'react'
        # Check app.js exists
        app_file = files.find { |f| f[:path] == 'app.js' }
        if app_file
          # Check for forbidden patterns
          if app_file[:content].include?('import ') || app_file[:content].include?('export ')
            errors << "app.js contains ES6 import/export statements. Use global React objects instead."
          end
          
          if app_file[:content].include?('require(')
            errors << "app.js contains require() statements. Use global objects instead."
          end

          unless app_file[:content].include?('React.createElement')
            warnings << "app.js should use React.createElement instead of JSX"
          end
        else
          errors << "Missing app.js file for React app"
        end
      end

      # Check for Tailwind classes usage
      all_content = files.map { |f| f[:content] }.join("\n")
      unless all_content.match?(/className=["'][^"']*\b(p-|m-|flex|grid|bg-|text-|border-|rounded-)/i)
        warnings << "No Tailwind CSS classes detected. Make sure to use Tailwind classes for styling."
      end

      {
        valid: errors.empty?,
        errors: errors,
        warnings: warnings
      }
    end

    def self.fix_common_issues(files, framework = 'react')
      fixed_files = files.dup

      # Find and fix index.html
      html_index = fixed_files.find_index { |f| f[:path] == 'index.html' || f[:type] == 'html' }
      
      if html_index
        html_file = fixed_files[html_index].dup
        html_content = html_file[:content]

        # Add Tailwind if missing
        unless html_content.include?('cdn.tailwindcss.com')
          html_content = html_content.sub(
            '</head>',
            "  <script src=\"https://cdn.tailwindcss.com\"></script>\n</head>"
          )
        end

        # Add React CDNs if missing and framework is react
        if framework == 'react'
          unless html_content.include?('react.production.min.js')
            react_cdns = <<~HTML
              <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
              <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
            HTML
            
            html_content = html_content.sub('</head>', "#{react_cdns}</head>")
          end
        end

        html_file[:content] = html_content
        fixed_files[html_index] = html_file
      end

      fixed_files
    end
  end
end