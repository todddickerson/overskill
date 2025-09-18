module Ai
  # Direct Moonshot API client for reliable tool calling when OpenRouter fails
  class MoonshotDirectClient
    include HTTParty
    base_uri ENV.fetch("MOONSHOT_BASE_URL", "https://api.moonshot.cn/v1")

    MODELS = {
      kimi_k2: "moonshot-v1-k2",
      kimi_v1_32k: "moonshot-v1-32k",
      kimi_v1_128k: "moonshot-v1-128k"
    }.freeze

    DEFAULT_MODEL = :kimi_k2

    def initialize(api_key = nil)
      @api_key = api_key || ENV.fetch("MOONSHOT_API_KEY")
      @options = {
        headers: {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json"
        },
        timeout: 600  # 10 minute timeout for long generation requests
      }
    end

    def chat(messages, model: DEFAULT_MODEL, temperature: 0.7, max_tokens: 8000, tools: nil)
      model_id = MODELS[model] || model

      body = {
        model: model_id,
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        stream: false
      }

      # Add tools if provided (for tool calling)
      if tools&.any?
        body[:tools] = tools
        body[:tool_choice] = "auto"
      end

      Rails.logger.info "[AI] Calling Moonshot Direct with model: #{model_id}" if ENV["VERBOSE_AI_LOGGING"] == "true"

      retries = 0
      max_retries = 2

      begin
        response = self.class.post("/chat/completions", @options.merge(body: body.to_json))
      rescue Net::ReadTimeout => e
        retries += 1
        if retries <= max_retries
          Rails.logger.warn "[AI] Moonshot timeout occurred, retrying (#{retries}/#{max_retries})..."
          sleep(retries * 2) # Exponential backoff
          retry
        else
          Rails.logger.error "[AI] Moonshot timeout after #{max_retries} retries"
          raise e
        end
      end

      if response.success?
        result = response.parsed_response
        usage = result.dig("usage")

        if usage && ENV["VERBOSE_AI_LOGGING"] == "true"
          Rails.logger.info "[AI] Moonshot Token usage - Prompt: #{usage["prompt_tokens"]}, Completion: #{usage["completion_tokens"]}, Cost: $#{calculate_cost(usage, model_id)}"
        end

        # Handle tool calling response
        message = result.dig("choices", 0, "message")
        tool_calls = message&.dig("tool_calls")

        {
          success: true,
          content: message&.dig("content"),
          tool_calls: tool_calls,
          usage: usage,
          model: model_id
        }
      else
        Rails.logger.error "[AI] Moonshot Direct error: #{response.code} - #{response.body}"
        {
          success: false,
          error: response.parsed_response["error"] || "Unknown error",
          code: response.code
        }
      end
    rescue => e
      Rails.logger.error "[AI] Moonshot Direct exception: #{e.message}"
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

    # Tool calling methods with native support
    def analyze_app_update_request_with_tools(request:, current_files:, app_context:)
      tools = [
        {
          type: "function",
          function: {
            name: "create_update_plan",
            description: "Creates a detailed plan for updating the application",
            parameters: {
              type: "object",
              properties: {
                analysis: {
                  type: "string",
                  description: "Deep analysis of user needs and how to create a sophisticated solution"
                },
                approach: {
                  type: "string",
                  description: "Professional, design-first approach using approved technologies"
                },
                design_language: {
                  type: "object",
                  properties: {
                    color_palette: {
                      type: "object",
                      properties: {
                        primary: {type: "string"},
                        secondary: {type: "string"},
                        accent: {type: "string"},
                        background: {type: "string"}
                      }
                    },
                    typography: {type: "string"},
                    aesthetic: {type: "string"}
                  }
                },
                steps: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      description: {type: "string"},
                      files_affected: {
                        type: "array",
                        items: {type: "string"}
                      },
                      design_notes: {type: "string"}
                    }
                  }
                },
                system_architecture: {
                  type: "array",
                  items: {type: "string"}
                },
                user_experience_flow: {
                  type: "array",
                  items: {type: "string"}
                },
                professional_touches: {
                  type: "array",
                  items: {type: "string"}
                }
              },
              required: ["analysis", "approach", "steps"]
            }
          }
        }
      ]

      messages = [
        {role: "system", content: build_analysis_prompt_system},
        {role: "user", content: build_analysis_prompt_user(request, current_files, app_context)}
      ]

      response = chat(messages, model: :kimi_k2, temperature: 0.3, max_tokens: 2000, tools: tools)

      if response[:success]
        if response[:tool_calls]&.any?
          # Handle native tool calling response
          tool_call = response[:tool_calls].first
          if tool_call["function"]["name"] == "create_update_plan"
            begin
              plan = JSON.parse(tool_call["function"]["arguments"], symbolize_names: true)
              {success: true, plan: plan}
            rescue JSON::ParserError => e
              {success: false, error: "Failed to parse tool call: #{e.message}"}
            end
          else
            {success: false, error: "Unexpected tool call: #{tool_call["function"]["name"]}"}
          end
        else
          # Fallback to text parsing if no tool calls
          parse_text_response(response[:content])
        end
      else
        response
      end
    end

    def execute_app_update_with_tools(plan)
      tools = [
        {
          type: "function",
          function: {
            name: "generate_file_changes",
            description: "Generates the complete updated code for all affected files",
            parameters: {
              type: "object",
              properties: {
                summary: {
                  type: "string",
                  description: "Brief summary of changes made"
                },
                files: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      path: {type: "string"},
                      content: {type: "string"},
                      summary: {type: "string"}
                    },
                    required: ["path", "content"]
                  }
                },
                whats_next: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      title: {type: "string"},
                      description: {type: "string"}
                    }
                  }
                },
                validation_issues: {
                  type: "array",
                  items: {
                    type: "object",
                    properties: {
                      severity: {type: "string"},
                      title: {type: "string"},
                      description: {type: "string"},
                      file: {type: "string"}
                    }
                  }
                }
              },
              required: ["summary", "files"]
            }
          }
        }
      ]

      messages = [
        {role: "system", content: build_execution_prompt_system},
        {role: "user", content: build_execution_prompt_user(plan)}
      ]

      response = chat(messages, model: :kimi_k2, temperature: 0.5, max_tokens: 8000, tools: tools)

      if response[:success]
        if response[:tool_calls]&.any?
          # Handle native tool calling response
          tool_call = response[:tool_calls].first
          if tool_call["function"]["name"] == "generate_file_changes"
            begin
              changes = JSON.parse(tool_call["function"]["arguments"], symbolize_names: true)
              {success: true, changes: changes}
            rescue JSON::ParserError => e
              {success: false, error: "Failed to parse tool call: #{e.message}"}
            end
          else
            {success: false, error: "Unexpected tool call: #{tool_call["function"]["name"]}"}
          end
        else
          # Fallback to text parsing if no tool calls
          parse_execution_response(response[:content])
        end
      else
        response
      end
    end

    private

    def build_analysis_prompt_system
      <<~PROMPT
        CRITICAL: You are working within OverSkill, a platform that generates client-side web apps deployed to Cloudflare Workers.
        
        PLATFORM CONSTRAINTS:
        - Apps are FILE-BASED ONLY (HTML, CSS, JS files served directly)
        - NO build processes, npm, package.json, node_modules, or compilation
        - NO server-side code, backends, or Node.js APIs
        - Apps run in sandboxed iframe environments with limited APIs
        - Use VANILLA JavaScript, HTML5, and CSS3 (with approved exceptions)
        
        APPROVED TECHNOLOGIES:
        - ✅ Tailwind CSS: Full minified build via CDN
        - ✅ Shadcn/ui Components: Copy-paste HTML/CSS components
        - ✅ Alpine.js: Lightweight JavaScript framework for interactivity
        - ✅ Chart.js: Professional data visualization
        - ✅ Lucide Icons: Consistent SVG icon system
        - ✅ Animate.css: Professional animations and transitions
        - ✅ OverSkill.js: Enhanced error handling and editor communication
        
        DESIGN EXCELLENCE REQUIREMENTS:
        Your goal is to create sophisticated, professional-grade applications that truly WOW users.
        
        VISUAL DESIGN STANDARDS:
        - Choose sophisticated color palettes with specific hex codes
        - Plan typography hierarchy for readability and elegance
        - Use generous white space and clean layouts
        - Leverage Shadcn/ui components for professional interfaces
        - Consider industry-specific aesthetics
        - Create cohesive design systems using consistent component patterns
        
        Use the create_update_plan function to provide your analysis and plan.
      PROMPT
    end

    def build_analysis_prompt_user(request, current_files, app_context)
      <<~PROMPT
        User Request: #{request}
        
        Current App Context:
        - Name: #{app_context[:name]}
        - Type: #{app_context[:type]}
        - Framework: #{app_context[:framework]} (IMPORTANT: Generate #{app_context[:framework]} code)
        
        Current Files:
        #{current_files.map { |f| "- #{f[:path]} (#{f[:type]})" }.join("\n")}
        
        Create a comprehensive update plan that addresses the user's request while maintaining OverSkill's platform constraints and achieving professional-grade quality.
      PROMPT
    end

    def build_execution_prompt_system
      <<~PROMPT
        CRITICAL: Execute this plan within OverSkill's platform constraints.
        
        EXECUTION CONSTRAINTS:
        - Generate ONLY vanilla HTML, CSS, and JavaScript files (with approved exceptions)
        - NO build processes, imports, or external dependencies (except approved CDNs)
        - Files must be self-contained and work when served directly
        - Use modern JavaScript (ES6+) but ensure browser compatibility
        - Include proper error handling and defensive programming
        
        APPROVED EXTERNAL RESOURCES:
        - ✅ Tailwind CSS: Include via CDN link
        - ✅ Shadcn/ui Components: Copy HTML/CSS directly
        - ✅ Alpine.js, Chart.js, Lucide Icons, Animate.css via CDN
        - ✅ OverSkill.js: Include for enhanced functionality
        
        Use the generate_file_changes function to provide the complete implementation.
      PROMPT
    end

    def build_execution_prompt_user(plan)
      <<~PROMPT
        Plan to Execute:
        #{plan.to_json}
        
        Generate the complete updated code for all affected files following OverSkill constraints.
        Include professional design elements, proper error handling, and all necessary CDN resources.
      PROMPT
    end

    def parse_text_response(content)
      # Fallback text parsing similar to OpenRouterClient

      content = content.strip
      if content.start_with?("```")
        content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
      end
      plan = JSON.parse(content, symbolize_names: true)
      {success: true, plan: plan}
    rescue JSON::ParserError => e
      {success: false, error: "Failed to parse plan: #{e.message}"}
    end

    def parse_execution_response(content)
      # Fallback text parsing for execution response

      content = content.strip
      if content.start_with?("```")
        content = content.match(/```(?:json)?\s*\n?(.+?)\n?```/m)&.captures&.first || content
      end
      changes = JSON.parse(content, symbolize_names: true)
      {success: true, changes: changes}
    rescue JSON::ParserError => e
      {success: false, error: "Failed to parse changes: #{e.message}"}
    end

    def calculate_cost(usage, model_id)
      # Moonshot API pricing (as of 2025)
      costs = {
        "moonshot-v1-k2" => {prompt: 0.15, completion: 2.50},  # $0.15/$2.50 per 1M tokens
        "moonshot-v1-32k" => {prompt: 0.12, completion: 0.12},
        "moonshot-v1-128k" => {prompt: 0.06, completion: 0.06}
      }

      rates = costs[model_id] || {prompt: 0.15, completion: 2.50}

      prompt_cost = (usage["prompt_tokens"] / 1_000_000.0) * rates[:prompt]
      completion_cost = (usage["completion_tokens"] / 1_000_000.0) * rates[:completion]

      (prompt_cost + completion_cost).round(6)
    end
  end
end
