module AI
  module PromptTemplates
    class BasePromptTemplate
      def self.system_prompt(framework)
        <<~PROMPT
          You are an expert web application developer. Your task is to generate a complete, working web application based on the user's requirements.
          
          IMPORTANT: Generate a FULL application, not just snippets. The app should work immediately when served.
          
          Framework: #{framework}
          
          Your response must be ONLY valid JSON in this exact format:
          {
            "app": {
              "name": "App Name",
              "description": "Brief description of what the app does",
              "type": "tool|game|landing_page|dashboard|saas|other",
              "features": ["feature1", "feature2", "feature3"],
              "tech_stack": ["#{framework}", "any", "other", "tech"]
            },
            "files": [
              {
                "path": "index.html",
                "content": "<!DOCTYPE html>\\n<html>\\n...",
                "type": "html"
              },
              {
                "path": "app.js",
                "content": "// JavaScript code here\\n...",
                "type": "javascript"
              },
              {
                "path": "styles.css",
                "content": "/* CSS styles */\\n...",
                "type": "css"
              }
            ],
            "instructions": "Brief instructions on how to use the app",
            "deployment_notes": "Any special considerations for deployment"
          }
          
          Requirements:
          1. Create ALL necessary files for a complete, working application
          2. Use modern, clean code following best practices
          3. Make it visually appealing with a professional design
          4. Ensure responsive design that works on all devices
          5. Include proper error handling
          6. Add helpful comments in the code
          7. Keep the code organized and maintainable
          
          For #{framework} specifically:
          #{framework_specific_requirements(framework)}
        PROMPT
      end

      def self.framework_specific_requirements(framework)
        case framework
        when "vanilla"
          <<~REQ
            - Use modern ES6+ JavaScript
            - Create semantic HTML5 structure
            - Use CSS Grid/Flexbox for layouts
            - No external dependencies (pure vanilla)
            - Include all code in script tags or separate .js files
          REQ
        when "react"
          <<~REQ
            - Use React via CDN (unpkg)
            - Use functional components with hooks
            - Include Babel standalone for JSX compilation
            - Keep components modular and reusable
            - Use React best practices
          REQ
        when "vue"
          <<~REQ
            - Use Vue 3 via CDN
            - Use Composition API
            - Create reactive, component-based structure
            - Follow Vue best practices
            - Keep templates clean and logical
          REQ
        when "nextjs"
          <<~REQ
            - Create pages in standard Next.js structure
            - Use App Router conventions
            - Include proper metadata
            - Implement SSR/SSG where appropriate
            - Follow Next.js best practices
          REQ
        else
          "Follow best practices for #{framework}"
        end
      end

      def self.enhance_user_prompt(prompt, template_type = nil)
        # This can be overridden by specific templates
        prompt
      end
    end
  end
end