module Ai
  class OpenRouterClient
    include HTTParty
    base_uri ENV.fetch("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")

    MODELS = {
      kimi_k2: "moonshotai/kimi-k2",  # Main model for app generation
      deepseek_v3: "deepseek/deepseek-chat",  # Fallback model
      gemini_flash: "google/gemini-1.5-flash", # Quick tasks
      claude_sonnet: "anthropic/claude-3.5-sonnet" # High quality tasks
    }.freeze

    DEFAULT_MODEL = :kimi_k2

    def initialize(api_key = nil)
      @api_key = api_key || ENV.fetch("OPENROUTER_API_KEY")
      @options = {
        headers: {
          "Authorization" => "Bearer #{@api_key}",
          "HTTP-Referer" => ENV.fetch("OPENROUTER_REFERER", "https://overskill.app"),
          "X-Title" => "OverSkill Platform",
          "Content-Type" => "application/json"
        },
        timeout: 600  # 10 minute timeout for long generation requests
      }
    end

    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: 8000)
      model_id = MODELS[model] || model

      body = {
        model: model_id,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: false
      }

      Rails.logger.info "[AI] Calling OpenRouter with model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      retries = 0
      max_retries = 2
      
      begin
        response = self.class.post("/chat/completions", @options.merge(body: body.to_json))
      rescue Net::ReadTimeout => e
        retries += 1
        if retries <= max_retries
          Rails.logger.warn "[AI] Timeout occurred, retrying (#{retries}/#{max_retries})..."
          sleep(retries * 2) # Exponential backoff
          retry
        else
          Rails.logger.error "[AI] Timeout after #{max_retries} retries"
          raise e
        end
      end

      if response.success?
        result = response.parsed_response
        usage = result.dig("usage")

        if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
          Rails.logger.info "[AI] Token usage - Prompt: #{usage["prompt_tokens"]}, Completion: #{usage["completion_tokens"]}, Cost: $#{calculate_cost(usage, model_id)}"
        end

        {
          success: true,
          content: result.dig("choices", 0, "message", "content"),
          usage: usage,
          model: model_id
        }
      else
        Rails.logger.error "[AI] OpenRouter error: #{response.code} - #{response.body}"
        {
          success: false,
          error: response.parsed_response["error"] || "Unknown error",
          code: response.code
        }
      end
    rescue => e
      Rails.logger.error "[AI] OpenRouter exception: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end

    def generate_app(prompt, framework: "react", app_type: nil)
      # Build a detailed spec from the user's prompt
      spec = Ai::AppSpecBuilder.build_spec(prompt, framework)

      messages = [
        {role: "system", content: "You are an expert web developer. Follow the specifications exactly."},
        {role: "user", content: spec}
      ]

      chat(messages, model: :kimi_k2, temperature: 0.7, max_tokens: 16000)
    end

    def update_app(user_request, current_files, app_context)
      # Build update spec
      spec = Ai::AppSpecBuilder.build_update_spec(user_request, current_files, app_context)

      messages = [
        {role: "system", content: "You are an expert web developer. Make precise updates to the existing application."},
        {role: "user", content: spec}
      ]

      chat(messages, model: :kimi_k2, temperature: 0.7, max_tokens: 8000)
    end
    
    def analyze_app_update_request(request:, current_files:, app_context:)
      messages = [
        {role: "system", content: "You are an AI assistant helping to plan app updates. Analyze the request and create a detailed plan."},
        {role: "user", content: build_analysis_prompt(request, current_files, app_context)}
      ]
      
      response = chat(messages, model: :kimi_k2, temperature: 0.3, max_tokens: 2000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          plan = JSON.parse(content, symbolize_names: true)
          { success: true, plan: plan }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse plan: #{e.message}" }
        end
      else
        response
      end
    end
    
    def execute_app_update(plan)
      messages = [
        {role: "system", content: "You are an expert web developer. Execute the plan and generate the necessary code changes."},
        {role: "user", content: build_execution_prompt(plan)}
      ]
      
      response = chat(messages, model: :kimi_k2, temperature: 0.5, max_tokens: 8000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          changes = JSON.parse(content, symbolize_names: true)
          { success: true, changes: changes }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse changes: #{e.message}" }
        end
      else
        response
      end
    end
    
    def fix_app_issues(issues:, current_files:)
      messages = [
        {role: "system", content: "You are an expert web developer. Fix the identified issues in the code."},
        {role: "user", content: build_fix_prompt(issues, current_files)}
      ]
      
      response = chat(messages, model: :kimi_k2, temperature: 0.3, max_tokens: 8000)
      
      if response[:success]
        begin
          content = response[:content].strip
          # Handle markdown wrapped JSON
          if content.start_with?("```")
            content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
          end
          changes = JSON.parse(content, symbolize_names: true)
          { success: true, changes: changes }
        rescue JSON::ParserError => e
          { success: false, error: "Failed to parse fixes: #{e.message}" }
        end
      else
        response
      end
    end

    private
    
    def build_analysis_prompt(request, current_files, app_context)
      prompt = <<~PROMPT
        Analyze this user request and create a detailed plan for updating the app.
        
        User Request: #{request}
        
        Current App Context:
        - Name: #{app_context[:name]}
        - Type: #{app_context[:type]}
        - Framework: #{app_context[:framework]}
        
        Current Files:
        #{current_files.map { |f| "- #{f[:path]} (#{f[:type]})" }.join("\n")}
        
        Return a JSON response with this structure:
        {
          "analysis": "Brief analysis of what the user wants",
          "approach": "High-level approach to implement the changes",
          "steps": [
            {"description": "Step 1 description", "files_affected": ["file1.js"]},
            {"description": "Step 2 description", "files_affected": ["file2.css"]}
          ],
          "considerations": ["Any important considerations"],
          "trade_offs": ["Any trade-offs to consider"]
        }
      PROMPT
    end
    
    def build_execution_prompt(plan)
      prompt = <<~PROMPT
        Execute this plan and generate the necessary code changes.
        
        Plan:
        #{plan.to_json}
        
        Generate the complete updated code for all affected files.
        
        Return a JSON response with this structure:
        {
          "summary": "Brief summary of changes made",
          "files": [
            {
              "path": "filename.ext",
              "content": "complete file content here",
              "summary": "What was changed in this file"
            }
          ],
          "whats_next": [
            {"title": "Suggestion 1", "description": "Description of what could be done next"}
          ],
          "validation_issues": [
            {"severity": "warning", "title": "Issue", "description": "Description", "file": "file.js"}
          ]
        }
      PROMPT
    end
    
    def build_fix_prompt(issues, current_files)
      prompt = <<~PROMPT
        Fix these issues in the app:
        
        Issues:
        #{issues.map { |i| "- #{i[:severity]}: #{i[:title]} in #{i[:file]}" }.join("\n")}
        
        Current Files:
        #{current_files.map { |f| "File: #{f[:path]}\n```\n#{f[:content]}\n```" }.join("\n\n")}
        
        Return a JSON response with this structure:
        {
          "summary": "Summary of fixes applied",
          "files": [
            {
              "path": "filename.ext",
              "content": "complete fixed file content"
            }
          ],
          "fixes": [
            {"issue": "Issue description", "solution": "How it was fixed"}
          ]
        }
      PROMPT
    end

    def calculate_cost(usage, model_id)
      # Cost estimates per 1M tokens from OpenRouter
      costs = {
        "moonshotai/kimi-k2" => {prompt: 0.30, completion: 0.30},  # $0.30 per 1M tokens
        "deepseek/deepseek-chat" => {prompt: 0.001, completion: 0.002},
        "google/gemini-1.5-flash" => {prompt: 0.00015, completion: 0.0006},
        "anthropic/claude-3.5-sonnet" => {prompt: 0.003, completion: 0.015}
      }

      rates = costs[model_id] || {prompt: 0.001, completion: 0.001}

      prompt_cost = (usage["prompt_tokens"] / 1_000_000.0) * rates[:prompt]
      completion_cost = (usage["completion_tokens"] / 1_000_000.0) * rates[:completion]

      (prompt_cost + completion_cost).round(6)
    end
  end
end
