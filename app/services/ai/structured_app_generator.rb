module Ai
  # StructuredAppGenerator - Works without function calling for Kimi K2
  # Uses structured prompts to get consistent JSON output
  class StructuredAppGenerator
    attr_reader :client
    
    def initialize
      @client = OpenRouterClient.new
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
      <<~PROMPT
        Create a React TypeScript app: #{user_prompt}
        
        CRITICAL REQUIREMENTS:
        - React 18+ with TypeScript (.tsx/.ts files)
        - Tailwind CSS for styling
        - Vite as build tool
        - Cloudflare Workers deployment (wrangler.toml)
        - Supabase integration with RLS
        - Analytics tracking
        
        Return JSON:
        {
          "app": {
            "name": "App Name",
            "description": "Brief description"
          },
          "files": [
            {"path": "index.html", "content": "<!DOCTYPE html>..."},
            {"path": "src/App.tsx", "content": "import React..."},
            {"path": "src/main.tsx", "content": "import React..."},
            {"path": "src/lib/supabase.ts", "content": "import { createClient }..."},
            {"path": "src/lib/analytics.ts", "content": "class OverskillAnalytics..."},
            {"path": "package.json", "content": "{...}"},
            {"path": "vite.config.ts", "content": "import { defineConfig }..."},
            {"path": "tailwind.config.js", "content": "module.exports = {..."},
            {"path": "tsconfig.json", "content": "{...}"},
            {"path": "wrangler.toml", "content": "name = ..."}
          ]
        }
        
        REQUIRED in src/lib/supabase.ts:
        - createClient with env vars VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
        - setRLSContext function for row-level security
        
        REQUIRED in src/lib/analytics.ts:
        - OverskillAnalytics class
        - track() method posting to https://overskill.app/api/v1/analytics/track
        - Auto-track page_view on init
        
        Create COMPLETE, working files. Return ONLY valid JSON.
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