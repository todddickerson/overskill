module AI
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
        }
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
      
      response = self.class.post("/chat/completions", @options.merge(body: body.to_json))
      
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
      # Get appropriate system prompt from templates
      system_prompt = AI::PromptTemplates::TemplateSelector.get_system_prompt(framework)
      
      # Enhance the user prompt based on detected template
      enhanced_prompt = AI::PromptTemplates::TemplateSelector.enhance_prompt(prompt, app_type, framework)
      
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: enhanced_prompt }
      ]
      
      chat(messages, model: :kimi_k2, temperature: 0.7, max_tokens: 16000)
    end

    private

    def calculate_cost(usage, model_id)
      # Cost estimates per 1M tokens from OpenRouter
      costs = {
        "moonshotai/kimi-k2" => { prompt: 0.30, completion: 0.30 },  # $0.30 per 1M tokens
        "deepseek/deepseek-chat" => { prompt: 0.001, completion: 0.002 },
        "google/gemini-1.5-flash" => { prompt: 0.00015, completion: 0.0006 },
        "anthropic/claude-3.5-sonnet" => { prompt: 0.003, completion: 0.015 }
      }
      
      rates = costs[model_id] || { prompt: 0.001, completion: 0.001 }
      
      prompt_cost = (usage["prompt_tokens"] / 1_000_000.0) * rates[:prompt]
      completion_cost = (usage["completion_tokens"] / 1_000_000.0) * rates[:completion]
      
      (prompt_cost + completion_cost).round(6)
    end
  end
end