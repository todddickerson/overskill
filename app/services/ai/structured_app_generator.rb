module Ai
  # StructuredAppGenerator - Works without function calling for Kimi K2
  # Uses structured prompts to get consistent JSON output
  class StructuredAppGenerator
    attr_reader :client
    
    def initialize
      @client = OpenRouterClient.new
      @template_service = AppTemplateService.new
    end
    
    def generate(prompt, framework: "react", app_type: "saas")
      Rails.logger.info "[StructuredGenerator] Starting generation"
      
      # Load standards
      standards = File.read(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) rescue ""
      
      # Build structured prompt that returns JSON without function calling
      structured_prompt = build_structured_prompt(prompt, standards)
      
      # Use Claude as primary for reliability with complex prompts
      result = generate_with_claude(structured_prompt)
      
      # Try Kimi as fallback if Claude fails (unlikely but good to have)
      if !result[:success] || result[:files].empty?
        Rails.logger.warn "[StructuredGenerator] Claude failed, trying Kimi K2"
        result = generate_with_kimi(structured_prompt)
      end
      
      result
    end
    
    private
    
    def build_structured_prompt(user_prompt, standards)
      # Enhance prompt with template if applicable
      enhanced_prompt = @template_service.enhance_prompt_with_template(user_prompt)
      
      # Keep critical requirements but optimize for performance
      <<~PROMPT
        Create a React TypeScript app: #{enhanced_prompt}
        
        REQUIREMENTS:
        - React 18+ with TypeScript
        - Tailwind CSS styling
        - Supabase integration
        - Analytics tracking
        
        Return JSON with these EXACT files:
        {
          "app": {
            "name": "descriptive name",
            "description": "what it does"
          },
          "files": [
            {"path": "index.html", "content": "<!DOCTYPE html>..."},
            {"path": "src/App.tsx", "content": "// React TypeScript component"},
            {"path": "src/main.tsx", "content": "// Entry point"},
            {"path": "src/lib/supabase.ts", "content": "// Use template below"},
            {"path": "src/lib/analytics.ts", "content": "// Use template below"},
            {"path": "package.json", "content": "// Dependencies"},
            {"path": "vite.config.ts", "content": "// Vite config"},
            {"path": "tsconfig.json", "content": "// TypeScript config"}
          ]
        }
        
        TEMPLATES for critical files:
        
        src/lib/supabase.ts MUST include:
        ```
        import { createClient } from '@supabase/supabase-js'
        const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
        const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY
        export const supabase = createClient(supabaseUrl, supabaseAnonKey)
        export const setRLSContext = async (userId: string) => {
          await supabase.rpc('set_config', {
            setting_name: 'app.current_user_id',
            new_value: userId,
            is_local: true
          })
        }
        ```
        
        src/lib/analytics.ts MUST include:
        ```
        class OverskillAnalytics {
          appId: string = import.meta.env.VITE_APP_ID || 'unknown'
          track(event: string, data: any = {}) {
            fetch('https://overskill.app/api/v1/analytics/track', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ app_id: this.appId, event, data })
            })
          }
        }
        export const analytics = new OverskillAnalytics()
        analytics.track('page_view')
        ```
        
        Return ONLY valid JSON. Create COMPLETE working files.
      PROMPT
    end
    
    def generate_with_kimi(prompt)
      messages = [
        {
          role: "system",
          content: "You are an expert developer. Return only valid JSON with the exact structure requested."
        },
        {
          role: "user",
          content: prompt
        }
      ]
      
      response = @client.chat(
        messages,
        model: :kimi_k2,
        temperature: 0.3,
        max_tokens: 12000  # Balanced for performance
      )
      
      if response[:success]
        parse_structured_response(response[:content])
      else
        { success: false, error: response[:error] }
      end
    rescue => e
      Rails.logger.error "[StructuredGenerator] Kimi error: #{e.message}"
      { success: false, error: e.message }
    end
    
    def generate_with_claude(prompt)
      messages = [
        {
          role: "system",
          content: "You are an expert developer. Return only valid JSON with the exact structure requested."
        },
        {
          role: "user",
          content: prompt
        }
      ]
      
      response = @client.chat(
        messages,
        model: :claude_4,  # Use Claude 4 Sonnet
        temperature: 0.3,
        max_tokens: 8000  # Reduced to prevent truncation issues
      )
      
      if response[:success]
        parse_structured_response(response[:content])
      else
        { success: false, error: response[:error] }
      end
    rescue => e
      Rails.logger.error "[StructuredGenerator] Claude error: #{e.message}"
      { success: false, error: e.message }
    end
    
    def parse_structured_response(content)
      Rails.logger.debug "[StructuredGenerator] Response length: #{content.length} characters"
      
      # Clean content first - remove reserved tokens and artifacts
      cleaned_content = content.gsub(/<\|reserved_token_\d+\|>/, '')
                              .gsub(/<\|.*?\|>/, '')
                              .gsub(/<\|.*$/, '') # Remove partial tokens at end
      
      # Extract JSON from response with multiple strategies
      json_match = cleaned_content.match(/```json\s*\n?(.*?)```/m) || 
                   cleaned_content.match(/```\s*\n?(\{.*?"files".*?\})\s*```/m) ||
                   cleaned_content.match(/(\{.*?"files".*?\})/m)
      
      return { success: false, error: "No JSON found in response" } unless json_match
      
      json_str = (json_match[1] || json_match[0]).strip
      
      Rails.logger.debug "[StructuredGenerator] Extracted JSON length: #{json_str.length} characters"
      
      # Additional cleaning for malformed JSON
      json_str = json_str.gsub(/,\s*\}/, '}')  # Remove trailing commas
                         .gsub(/,\s*\]/, ']')  # Remove trailing commas in arrays
      
      # Check for truncated JSON and try to fix
      if json_str.count('{') > json_str.count('}')
        Rails.logger.warn "[StructuredGenerator] JSON appears truncated, attempting repair"
        # Add missing closing braces
        missing_braces = json_str.count('{') - json_str.count('}')
        json_str += '}' * missing_braces
      end
      
      # If JSON is still malformed, try to extract just the files array
      if json_str.length > 40000 # Very large response
        Rails.logger.warn "[StructuredGenerator] Large JSON response, attempting simplified parsing"
        files_match = json_str.match(/"files"\s*:\s*\[(.*?)\]/m)
        if files_match
          # Create minimal valid structure
          json_str = %{{"app": {"name": "Generated App", "description": "AI Generated Application"}, "files": [#{files_match[1]}]}}
        end
      end
      
      data = JSON.parse(json_str)
      
      # Validate structure
      unless data["files"] && data["files"].is_a?(Array)
        return { success: false, error: "Invalid response structure" }
      end
      
      {
        success: true,
        app: data["app"] || {},
        files: data["files"],
        tool_calls: [
          {
            "function" => {
              "name" => "generate_app",
              "arguments" => data.to_json
            }
          }
        ]
      }
    rescue JSON::ParserError => e
      Rails.logger.error "[StructuredGenerator] JSON parse error: #{e.message}"
      { success: false, error: "Failed to parse JSON: #{e.message}" }
    end
  end
end