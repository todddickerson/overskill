module Ai
  class CodeValidatorService
    FORBIDDEN_PATTERNS = [
      # Module syntax
      { pattern: /\bimport\s+.*from\s+['"]/, message: "ES6 import statements are not allowed. Use script tags in HTML." },
      { pattern: /\bexport\s+(default|const|function|class)/, message: "ES6 export statements are not allowed. Use global functions." },
      { pattern: /\brequire\s*\(/, message: "CommonJS require() is not allowed. Use script tags in HTML." },
      { pattern: /\bmodule\.exports/, message: "CommonJS exports are not allowed. Use global functions." },
      
      # JSX (when not using Babel)
      { pattern: /<[A-Z]\w*[^>]*\/?>/, message: "JSX syntax detected. Use React.createElement() instead." },
      { pattern: /<\/[A-Z]\w*>/, message: "JSX closing tags detected. Use React.createElement() instead." },
      { pattern: /<div[^>]*>/, message: "JSX syntax detected. Use React.createElement() instead." },
      { pattern: /<\/div>/, message: "JSX closing tags detected. Use React.createElement() instead." },
      
      # Development CDNs
      { pattern: /unpkg\.com.*development\.js/, message: "Use production builds from CDN, not development builds." },
      { pattern: /babel.*standalone/, message: "Babel standalone should not be used. Write browser-compatible code." }
    ]
    
    def self.validate_files(files)
      errors = []
      warnings = []
      
      files.each do |file|
        next unless file[:path].match?(/\.(js|jsx|html)$/)
        
        content = file[:content]
        
        # Check for forbidden patterns
        FORBIDDEN_PATTERNS.each do |rule|
          if content.match?(rule[:pattern])
            errors << {
              file: file[:path],
              message: rule[:message],
              pattern: rule[:pattern].source
            }
          end
        end
        
        # Additional checks for React files
        if file[:path].match?(/\.(js|jsx)$/) && content.include?("React")
          # Check for proper React usage
          unless content.match?(/const\s*{\s*\w+.*}\s*=\s*React/) || content.match?(/React\.\w+/)
            warnings << {
              file: file[:path],
              message: "React components should destructure from global React object"
            }
          end
          
          # Check for proper mounting
          if file[:path] == "app.js" && !content.match?(/ReactDOM\.createRoot|ReactDOM\.render/)
            errors << {
              file: file[:path],
              message: "Main app.js must mount the React app using ReactDOM"
            }
          end
        end
        
        # Check HTML files
        if file[:path].match?(/\.html$/)
          # Ensure React is loaded from CDN
          unless content.match?(/unpkg\.com.*react.*production\.min\.js/)
            warnings << {
              file: file[:path],
              message: "HTML should load React from CDN (production build)"
            }
          end
          
          # Check script order
          if content.include?("app.js") && content.include?("components.js")
            app_index = content.index("app.js")
            comp_index = content.index("components.js")
            if app_index && comp_index && app_index < comp_index
              errors << {
                file: file[:path],
                message: "components.js must be loaded before app.js"
              }
            end
          end
        end
      end
      
      {
        valid: errors.empty?,
        errors: errors,
        warnings: warnings
      }
    end
    
    def self.fix_common_issues(content, file_type)
      return content unless file_type == "javascript"
      
      # Fix imports to use global React
      fixed = content.gsub(/import\s+React.*from\s+['"]react['"].*\n/, "const { useState, useEffect, useRef } = React;\n")
      fixed = fixed.gsub(/import\s+ReactDOM.*from\s+['"]react-dom['"].*\n/, "")
      
      # Fix exports to global functions
      fixed = fixed.gsub(/export\s+default\s+function\s+(\w+)/, 'window.\1 = function')
      fixed = fixed.gsub(/export\s+function\s+(\w+)/, 'window.\1 = function')
      fixed = fixed.gsub(/export\s+const\s+(\w+)/, 'window.\1')
      
      # Remove export statements at end
      fixed = fixed.gsub(/export\s*{\s*[^}]+\s*}.*\n?/, '')
      
      fixed
    end
  end
end