module Ai
  # StructuredAppGenerator - Works without function calling for Kimi K2
  # Uses structured prompts to get consistent JSON output
  class StructuredAppGenerator
    attr_reader :client
    
    def initialize
      @client = OpenRouterClient.new
    end
    
    def generate(prompt, framework: "react", app_type: "saas")
      Rails.logger.info "[StructuredGenerator] Starting generation with Kimi K2"
      
      # Load standards
      standards = File.read(Rails.root.join('AI_GENERATED_APP_STANDARDS.md')) rescue ""
      
      # Build structured prompt that returns JSON without function calling
      structured_prompt = build_structured_prompt(prompt, standards)
      
      # Try Kimi K2 first (much cheaper)
      result = generate_with_kimi(structured_prompt)
      
      # Fallback to Claude if Kimi fails
      if !result[:success] || result[:files].empty?
        Rails.logger.warn "[StructuredGenerator] Kimi K2 failed, falling back to Claude"
        result = generate_with_claude(structured_prompt)
      end
      
      result
    end
    
    private
    
    def build_structured_prompt(user_prompt, standards)
      <<~PROMPT
        Create a React TypeScript app: #{user_prompt}
        
        Return JSON with this structure:
        {
          "app": {
            "name": "string",
            "description": "string"
          },
          "files": [
            {"path": "index.html", "content": "HTML content"},
            {"path": "src/App.tsx", "content": "React component"},
            {"path": "src/main.tsx", "content": "Entry point"},
            {"path": "package.json", "content": "Dependencies"}
          ]
        }
        
        Requirements:
        - React 18 with TypeScript
        - Include Tailwind CSS via CDN
        - Simple, working code
        - Return ONLY valid JSON
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
        max_tokens: 16000  # Reduced for faster response
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
        max_tokens: 16000
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
      # Extract JSON from response
      json_match = content.match(/```json\s*\n?(.*?)```/m) || 
                   content.match(/\{.*"files".*\}/m)
      
      return { success: false, error: "No JSON found in response" } unless json_match
      
      json_str = json_match[1] || json_match[0]
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