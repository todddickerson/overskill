module Ai
  class AppSpecBuilder
    def self.build_spec(user_prompt, framework = "react")
      <<~SPEC
        You are building a web application based on this request: #{user_prompt}

        IMPORTANT: Generate a complete, production-ready application following these specifications:

        ## Tech Stack & Structure
        
        ### REQUIRED for ALL apps:
        - Include proper meta tags with OverSkill attribution
        - Add description meta tag mentioning "Created with OverSkill"
        - Include generator meta tag with "OverSkill AI"
        - Add Open Graph tags for social sharing
        - Include Twitter Card meta tags
        - Include "Remix with OverSkill" CTA badge in bottom-right corner
        
        ### For React Apps:
        - Use React 18+ via CDN (unpkg) - NO ES6 MODULES OR IMPORTS
        - Use React.createElement() instead of JSX (NO BABEL NEEDED)
        - Access React via global objects: const { useState, useEffect } = React;
        - Functional components with hooks only
        - Use Tailwind CSS via CDN for styling
        - ALWAYS use production CDN builds (production.min.js NOT development.js)
        - Structure:
          - index.html (MUST include Tailwind CSS CDN: <script src="https://cdn.tailwindcss.com"></script>)
          - app.js (main React app using React.createElement)
          - components.js (reusable components as global functions)
          - styles.css (custom styles if needed, but most styling via Tailwind classes)
        
        CRITICAL: DO NOT USE:
        - import/export statements
        - require() calls
        - JSX syntax (use React.createElement instead)
        - Any module bundler syntax
        - Development CDN builds (always use production.min.js)
        
        IMPORTANT: HANDLE SANDBOXED ENVIRONMENTS:
        - Always wrap localStorage access in try/catch blocks
        - Check if localStorage is available before using it
        - Provide fallbacks for when localStorage is blocked
        - Example: 
          ```javascript
          let storage = null;
          try {
            if (typeof localStorage !== 'undefined') {
              localStorage.setItem('test', '1');
              localStorage.removeItem('test');
              storage = localStorage;
            }
          } catch (e) {
            // localStorage not available, use in-memory fallback
          }
          ```
        
        ### For Vanilla JS Apps:
        - Modern ES6+ JavaScript
        - Tailwind CSS via CDN (MUST be included in index.html)
        - Web Components where appropriate
        - Structure:
          - index.html (MUST include Tailwind CSS CDN: <script src="https://cdn.tailwindcss.com"></script>)
          - app.js (main logic)
          - styles.css (custom styles if needed, but most styling via Tailwind classes)
          - modules/*.js (if needed)

        ## Design Requirements
        - Clean, modern UI using Tailwind classes
        - Mobile-first responsive design
        - Smooth animations and transitions
        - Accessible (ARIA labels, keyboard nav)
        - Dark mode support (if appropriate)
        - Loading states for async operations
        
        ## Code Quality
        - Clear, self-documenting code
        - Proper error handling and validation
        - Performance optimized (debouncing, lazy loading)
        - Security best practices (sanitize inputs)
        - Local storage for data persistence WITH FALLBACK (wrap in try/catch, check if available)
        
        ## What's Next Analysis
        After generating the app, analyze the code and provide:
        1. Bug detection for common issues
        2. Smart suggestions for improvements
        3. Each suggestion should have a label and full prompt text
        
        ## File Output Format
        Return ONLY valid JSON with this structure:
        {
          "app": {
            "name": "App Name",
            "description": "What the app does",
            "type": "category",
            "features": ["feature1", "feature2"],
            "tech_stack": ["react", "tailwind", "etc"]
          },
          "files": [
            {
              "path": "index.html",
              "content": "full file content here",
              "type": "html"
            }
          ],
          "instructions": "How to use the app",
          "deployment_notes": "Any special notes",
          "whats_next": {
            "bugs": [
              {
                "message": "Description of potential issue",
                "file": "filename.js",
                "severity": "warning|error"
              }
            ],
            "suggestions": [
              {
                "label": "🔧 Fix something",
                "prompt": "Full prompt text to pre-fill when clicked"
              },
              {
                "label": "✨ Add feature",
                "prompt": "Add this specific feature..."
              }
            ]
          }
        }

        ## Example Structure (FOLLOW THIS PATTERN):
        
        ### index.html:
        ```html
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>App Title</title>
          <meta name="description" content="Created with OverSkill - Build apps without code">
          <meta name="author" content="OverSkill">
          
          <!-- Open Graph / Social Media -->
          <meta property="og:title" content="App Title">
          <meta property="og:description" content="Created with OverSkill - Build apps without code">
          <meta property="og:type" content="website">
          
          <!-- Twitter Card -->
          <meta name="twitter:card" content="summary_large_image">
          <meta name="twitter:site" content="@overskill_app">
          
          <!-- OverSkill Attribution -->
          <meta name="generator" content="OverSkill AI">
          
          <!-- React from CDN -->
          <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
          <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
          <!-- Tailwind CSS -->
          <script src="https://cdn.tailwindcss.com"></script>
          <!-- Custom styles if needed -->
          <link rel="stylesheet" href="styles.css">
        </head>
        <body>
          <div id="root"></div>
          
          <!-- Remix with OverSkill CTA badge -->
          <a href="https://overskill.app/remix?template=this-app" 
             target="_blank" 
             rel="noopener noreferrer"
             style="position: fixed; bottom: 20px; right: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 10px 16px; border-radius: 24px; text-decoration: none; font-size: 14px; font-family: system-ui, -apple-system, sans-serif; display: flex; align-items: center; gap: 8px; z-index: 9999; box-shadow: 0 4px 12px rgba(0,0,0,0.15); transition: transform 0.2s, box-shadow 0.2s;"
             onmouseover="this.style.transform='translateY(-2px)'; this.style.boxShadow='0 6px 20px rgba(0,0,0,0.2)';"
             onmouseout="this.style.transform='translateY(0)'; this.style.boxShadow='0 4px 12px rgba(0,0,0,0.15)';">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 2L2 7L12 12L22 7L12 2Z"/>
              <path d="M2 17L12 22L22 17"/>
              <path d="M2 12L12 17L22 12"/>
            </svg>
            <span style="font-weight: 600;">Remix with OverSkill</span>
          </a>
          
          <!-- Load scripts in correct order -->
          <script src="components.js"></script>
          <script src="app.js"></script>
        </body>
        </html>
        ```
        
        ### app.js (NO IMPORTS, use React.createElement):
        ```javascript
        const { useState, useEffect } = React;
        
        function App() {
          const [state, setState] = useState(initialValue);
          
          return React.createElement('div', { className: 'container' },
            React.createElement('h1', null, 'Title'),
            React.createElement(ComponentName, { prop: value })
          );
        }
        
        // Mount the app
        const root = ReactDOM.createRoot(document.getElementById('root'));
        root.render(React.createElement(App));
        ```
        
        ### components.js (Global functions, NO EXPORTS):
        ```javascript
        // Define components as global functions
        function ComponentName({ prop }) {
          return React.createElement('div', null, 'content');
        }
        
        // NO export statements - components are global
        ```

        Remember: Create a COMPLETE, working application that runs immediately when served. Test that all files work together without any bundler.
      SPEC
    end

    def self.build_update_spec(user_request, current_files, app_context)
      <<~SPEC
        You are updating an existing web application based on this request: #{user_request}

        Current application context:
        - Name: #{app_context[:name]}
        - Type: #{app_context[:type]}
        - Framework: #{app_context[:framework]}

        Current files in the project:
        #{current_files.map { |f| "- #{f[:path]}: #{f[:type]} (#{f[:size]} bytes)" }.join("\n")}

        IMPORTANT RULES:
        1. Only modify files that need to change for this request
        2. Maintain the existing code style and patterns
        3. Don't break existing functionality
        4. Keep the same tech stack unless explicitly asked to change
        5. For React apps: NO IMPORTS/EXPORTS - use global React and React.createElement()
        6. Ensure all code is browser-compatible (no require, no ES6 modules)
        7. Components should be global functions, not exported/imported
        8. ALWAYS use production CDN builds (production.min.js NOT development.js)
        9. React apps must initialize with "something on initial load always"

        WHAT'S NEXT SUGGESTIONS:
        After completing the changes, analyze the code and provide smart suggestions for next steps.
        Include:
        - Bug Detection: Check for common issues like:
          * Undefined property access (e.g., props.items.length without null check)
          * Missing React key props in list rendering
          * useState without initial values
          * API calls without error handling
          * Long functions that should be refactored (>100 lines)
          * Missing accessibility attributes
          * Performance issues (no memoization, excessive re-renders)
        
        - Smart Suggestions based on the code:
          * If React components are long (>200 lines), suggest: "Refactor [ComponentName] into smaller components"
          * If no error boundaries, suggest: "Add error boundaries for better error handling"
          * If no loading states, suggest: "Add loading states and skeleton screens"
          * If no responsive design, suggest: "Make the app fully responsive"
          * If basic styling, suggest: "Enhance UI with animations and modern design"
          * Context-specific suggestions based on app type

        Return ONLY valid JSON with this structure:
        {
          "changes": {
            "summary": "Brief description of what changed",
            "files_modified": ["file1.js", "file2.html"],
            "files_added": ["newfile.js"],
            "files_deleted": []
          },
          "files": [
            {
              "path": "app.js",
              "content": "full updated content",
              "type": "javascript",
              "action": "update"
            },
            {
              "path": "newfeature.js",
              "content": "new file content",
              "type": "javascript", 
              "action": "create"
            }
          ],
          "testing_notes": "What to test after these changes",
          "whats_next": {
            "bugs": [
              {
                "message": "Description of potential issue",
                "file": "filename.js",
                "severity": "warning|error"
              }
            ],
            "suggestions": [
              {
                "label": "🔧 Fix something",
                "prompt": "Full prompt text to pre-fill when clicked"
              },
              {
                "label": "✨ Add feature",
                "prompt": "Add this specific feature..."
              }
            ]
          }
        }
      SPEC
    end
  end
end
