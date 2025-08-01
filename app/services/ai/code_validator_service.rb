module Ai
  class CodeValidatorService
    FORBIDDEN_PATTERNS = [
      # Module syntax
      { pattern: /\bimport\s+.*from\s+['"]/, message: "ES6 import statements are not allowed. Use script tags in HTML." },
      { pattern: /\bexport\s+(default|const|function|class)/, message: "ES6 export statements are not allowed. Use global functions." },
      { pattern: /\brequire\s*\(/, message: "CommonJS require() is not allowed. Use script tags in HTML." },
      { pattern: /\bmodule\.exports/, message: "CommonJS exports are not allowed. Use global functions." },
      
      # localStorage without try/catch
      { pattern: /(?<!try\s*\{[^}]*)\blocalStorage\.(getItem|setItem|removeItem|clear)/, message: "localStorage access must be wrapped in try/catch for sandboxed environments." },
      
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
        
        # For HTML files, check specific patterns
        if file[:path].match?(/\.html$/)
          # Extract non-script content for validation
          non_script_content = content.gsub(/<script[^>]*>.*?<\/script>/m, '')
          
          # Only check for JSX in non-script parts of HTML
          if non_script_content.match?(/<[A-Z]\w*[^>]*\/?>/) || non_script_content.match?(/<\/[A-Z]\w*>/)
            errors << {
              file: file[:path],
              message: "JSX syntax detected outside script tags. Use React.createElement() instead.",
              pattern: "JSX in HTML"
            }
          end
          
          # Check for development CDN builds in HTML
          if content.match?(/unpkg\.com.*development\.js/)
            errors << {
              file: file[:path],
              message: "Use production builds from CDN, not development builds.",
              pattern: "development.js"
            }
          end
          
          # Skip other pattern checks for HTML files
          next
        end
        
        # Check for forbidden patterns in JS/JSX files
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
          
          # CRITICAL: Ensure Tailwind CSS is loaded
          unless content.match?(/cdn\.tailwindcss\.com/)
            errors << {
              file: file[:path],
              message: "HTML MUST include Tailwind CSS CDN: <script src=\"https://cdn.tailwindcss.com\"></script>"
            }
          end
          
          # Ensure OverSkill attribution
          unless content.match?(/OverSkill/i)
            warnings << {
              file: file[:path],
              message: "HTML should include OverSkill attribution in meta tags"
            }
          end
          
          # Check for proper meta tags
          unless content.match?(/<meta\s+name=["']generator["']\s+content=["']OverSkill/i)
            warnings << {
              file: file[:path],
              message: "HTML should include generator meta tag with 'OverSkill AI'"
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
      case file_type
      when "javascript"
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
      when "html"
        fixed = content.dup
        
        # Add Tailwind CSS if missing
        unless fixed.match?(/cdn\.tailwindcss\.com/)
          tailwind_script = '  <script src="https://cdn.tailwindcss.com"></script>'
          
          if fixed.match?(/<\/head>/)
            fixed = fixed.sub(/<\/head>/, "#{tailwind_script}\n</head>")
          elsif fixed.match?(/<head>/)
            fixed = fixed.sub(/<head>/, "<head>\n#{tailwind_script}")
          end
        end
        
        # Add OverSkill meta tags if missing
        unless fixed.match?(/<meta\s+name=["']generator["']/i)
          overskill_meta = <<~META.strip
              <meta name="description" content="Created with OverSkill - Build apps without code">
              <meta name="author" content="OverSkill">
              <meta name="generator" content="OverSkill AI">
              
              <!-- Open Graph -->
              <meta property="og:description" content="Created with OverSkill - Build apps without code">
              <meta property="og:type" content="website">
              
              <!-- Twitter Card -->
              <meta name="twitter:card" content="summary">
              <meta name="twitter:site" content="@overskill_app">
          META
          
          if fixed.match?(/<title>(.*?)<\/title>/i)
            fixed = fixed.sub(/<\/title>/, "</title>\n  #{overskill_meta}")
          elsif fixed.match?(/<\/head>/)
            fixed = fixed.sub(/<\/head>/, "  #{overskill_meta}\n</head>")
          end
        end
        
        # Add Remix CTA badge if missing
        unless fixed.match?(/Remix with OverSkill/i)
          remix_badge = <<~BADGE.strip
            
            <!-- Remix with OverSkill CTA badge -->
            <a href="https://overskill.app/remix?template=this-app" 
               target="_blank" 
               rel="noopener noreferrer"
               style="position: fixed; bottom: 20px; right: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 10px 16px; border-radius: 24px; text-decoration: none; font-size: 14px; font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; gap: 8px; z-index: 9999; box-shadow: 0 4px 12px rgba(0,0,0,0.15); transition: transform 0.2s, box-shadow 0.2s;"
               onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 20px rgba(0,0,0,0.2)';"
               onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.15)';">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M12 2L2 7L12 12L22 7L12 2Z" stroke="white"/>
                <path d="M2 17L12 22L22 17" stroke="white"/>
                <path d="M2 12L12 17L22 12" stroke="white"/>
              </svg>
              <span style="font-weight: 600;">Remix with OverSkill</span>
            </a>
          BADGE
          
          if fixed.match?(/<\/body>/i)
            fixed = fixed.sub(/<\/body>/i, "#{remix_badge}\n</body>")
          end
        end
        
        fixed
      else
        content
      end
    end
  end
end