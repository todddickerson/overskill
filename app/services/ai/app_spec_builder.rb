module Ai
  class AppSpecBuilder
    def self.build_spec(user_prompt, framework = "react")
      <<~SPEC
        You are building a web application based on this request: #{user_prompt}

        IMPORTANT: Generate a complete, production-ready application following these specifications:

        ## Tech Stack & Structure
        
        ### For React Apps:
        - Use React 18+ via CDN (unpkg) - NO ES6 MODULES OR IMPORTS
        - Use React.createElement() instead of JSX (NO BABEL NEEDED)
        - Access React via global objects: const { useState, useEffect } = React;
        - Functional components with hooks only
        - Use Tailwind CSS via CDN for styling
        - ALWAYS use production CDN builds (production.min.js NOT development.js)
        - Structure:
          - index.html (loads React from CDN, then components.js, then app.js)
          - app.js (main React app using React.createElement)
          - components.js (reusable components as global functions)
          - styles.css (custom styles if needed)
        
        CRITICAL: DO NOT USE:
        - import/export statements
        - require() calls
        - JSX syntax (use React.createElement instead)
        - Any module bundler syntax
        - Development CDN builds (always use production.min.js)
        
        ### For Vanilla JS Apps:
        - Modern ES6+ JavaScript
        - Tailwind CSS via CDN
        - Web Components where appropriate
        - Structure:
          - index.html
          - app.js (main logic)
          - styles.css
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
        - Local storage for data persistence
        
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
