module Ai
  class OpenaiClient
    include HTTParty
    base_uri "https://api.openai.com/v1"

    def initialize(api_key = nil)
      @api_key = api_key || ENV.fetch("OPENAI_API_KEY")
      @options = {
        headers: {
          "Authorization" => "Bearer #{@api_key}",
          "Content-Type" => "application/json"
        },
        timeout: 60 # 1 minute timeout for image generation
      }
    end

    def generate_image(prompt, size: "1024x1024", quality: "standard", style: "natural")
      body = {
        model: "dall-e-3",
        prompt: prompt,
        n: 1,
        size: size,
        quality: quality, # "standard" or "hd"
        style: style # "natural" or "vivid"
      }

      Rails.logger.info "[AI] Generating image with DALL-E 3" if ENV["VERBOSE_AI_LOGGING"] == "true"

      response = self.class.post("/images/generations", @options.merge(body: body.to_json))

      if response.success?
        result = response.parsed_response
        image_url = result.dig("data", 0, "url")
        revised_prompt = result.dig("data", 0, "revised_prompt")

        {
          success: true,
          image_url: image_url,
          revised_prompt: revised_prompt
        }
      else
        Rails.logger.error "[AI] OpenAI error: #{response.code} - #{response.body}"
        {
          success: false,
          error: response.parsed_response["error"] || "Unknown error",
          code: response.code
        }
      end
    rescue => e
      Rails.logger.error "[AI] OpenAI exception: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end

    def generate_app_logo(app_name, app_description)
      # Create a prompt optimized for app logo generation
      prompt = build_logo_prompt(app_name, app_description)
      
      # Generate with square dimensions suitable for app logos
      generate_image(prompt, size: "1024x1024", quality: "standard", style: "vivid")
    end

    private

    def build_logo_prompt(app_name, app_description)
      # Clean and truncate inputs to avoid prompt length issues
      clean_name = app_name.strip[0..50]
      clean_description = app_description.to_s.strip[0..200]

      # Build a prompt that generates good app logos
      <<~PROMPT.strip
        Create a modern, professional app icon logo for "#{clean_name}".
        #{clean_description.present? ? "App description: #{clean_description}." : ""}
        
        Style requirements:
        - Clean, minimalist design suitable for an app icon
        - Bold, simple shapes that work at small sizes
        - Modern gradient or flat design
        - Professional color scheme
        - No text or letters in the design
        - Centered composition with adequate padding
        - Tech/startup aesthetic
        
        The logo should be instantly recognizable and work well as a square app icon.
      PROMPT
    end
  end
end