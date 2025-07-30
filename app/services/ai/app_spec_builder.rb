module AI
  class AppSpecBuilder
    def self.build_spec(user_prompt, framework = "react")
      <<~SPEC
        You are building a web application based on this request: #{user_prompt}

        IMPORTANT: Generate a complete, production-ready application following these specifications:

        ## Tech Stack & Structure
        
        ### For React Apps:
        - Use React 18+ via CDN (unpkg)
        - Functional components with hooks only
        - Use Tailwind CSS via CDN for styling
        - Include Babel standalone for JSX
        - Structure:
          - index.html (main entry)
          - app.js (main React app)
          - components.js (reusable components)
          - styles.css (custom styles if needed)
        
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
          "deployment_notes": "Any special notes"
        }

        Remember: Create a COMPLETE, working application that runs immediately when served. Include all necessary code in the files.
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
          "testing_notes": "What to test after these changes"
        }
      SPEC
    end
  end
end
