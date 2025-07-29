module AI
  class SimpleCustomizerService
    def initialize(prompt, framework = "vanilla")
      @prompt = prompt
      @framework = framework
    end

    def generate
      # For v1, we'll use AI just to customize the hello world template
      client = AI::OpenRouterClient.new
      
      customization_prompt = build_customization_prompt(@prompt)
      
      messages = [
        { role: "system", content: customization_prompt },
        { role: "user", content: @prompt }
      ]
      
      # Use a smaller model for simple customizations
      response = client.chat(messages, model: :gemini_flash, temperature: 0.8, max_tokens: 1000)
      
      if response[:success]
        begin
          # Parse the customizations from AI
          customizations = parse_customizations(response[:content])
          
          # Generate files from template
          template_result = AI::Templates::HelloWorldTemplate.generate(
            framework: @framework,
            customizations: customizations
          )
          
          if template_result
            {
              success: true,
              files: template_result[:files],
              customizations: template_result[:customizations_applied],
              ai_model: response[:model],
              usage: response[:usage]
            }
          else
            { success: false, error: "Template not found for framework: #{@framework}" }
          end
        rescue => e
          { success: false, error: "Failed to parse customizations: #{e.message}" }
        end
      else
        { success: false, error: response[:error] }
      end
    end

    private

    def build_customization_prompt(user_prompt)
      <<~PROMPT
        You are customizing a simple Hello World web application based on the user's request.
        
        Analyze the user's prompt and return ONLY a JSON object with these customization values:
        
        {
          "APP_NAME": "The name of the app",
          "GREETING": "Main heading text (keep it short)",
          "MESSAGE": "A friendly description paragraph",
          "BUTTON_TEXT": "Text for the interactive button",
          "MILESTONE_MESSAGE": "Fun message shown every 10 clicks",
          "BG_COLOR_1": "Hex color for gradient start (e.g., #667eea)",
          "BG_COLOR_2": "Hex color for gradient end (e.g., #764ba2)",
          "TEXT_COLOR": "Hex color for text (e.g., #333)",
          "BUTTON_COLOR": "Hex color for button (e.g., #667eea)"
        }
        
        Guidelines:
        - Make the customizations match the user's request
        - Keep text friendly and engaging
        - Use appropriate colors that match the theme
        - If the user doesn't specify something, use sensible defaults
        - Always return valid hex colors
        - Keep the app simple and fun
        
        Return ONLY the JSON object, no other text or explanation.
      PROMPT
    end

    def parse_customizations(ai_response)
      # Try to extract JSON from the response
      json_match = ai_response.match(/\{[\s\S]*\}/)
      
      if json_match
        customizations = JSON.parse(json_match[0])
        
        # Validate and sanitize
        validated = {}
        
        # Text fields
        %w[APP_NAME GREETING MESSAGE BUTTON_TEXT MILESTONE_MESSAGE].each do |field|
          validated[field] = customizations[field].to_s.strip if customizations[field]
        end
        
        # Color fields - ensure they're valid hex colors
        %w[BG_COLOR_1 BG_COLOR_2 TEXT_COLOR BUTTON_COLOR].each do |field|
          if customizations[field] && customizations[field].match?(/^#[0-9A-Fa-f]{6}$/)
            validated[field] = customizations[field]
          end
        end
        
        validated
      else
        # Fallback to extracting what we can from the text
        extract_fallback_customizations(ai_response)
      end
    end

    def extract_fallback_customizations(text)
      # Simple fallback that tries to extract an app name from the text
      {
        "APP_NAME" => text.match(/app.*?:?\s*["']?([^"'\n]+)["']?/i)&.[](1) || "My App",
        "GREETING" => "Hello World!"
      }
    end
  end
end