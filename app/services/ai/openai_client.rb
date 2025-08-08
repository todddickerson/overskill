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
      # Use latest OpenAI image model via Images API. Only send supported fields.
      body = {
        model: "gpt-image-1",
        prompt: prompt,
        n: 1,
        size: size
      }

      Rails.logger.info "[AI] Generating image with gpt-image-1" if ENV["VERBOSE_AI_LOGGING"] == "true"

      response = self.class.post("/images/generations", @options.merge(body: body.to_json))

      if response.success?
        result = response.parsed_response
        image_url = result.dig("data", 0, "url")
        image_b64 = result.dig("data", 0, "b64_json")
        revised_prompt = result.dig("data", 0, "revised_prompt")

        {
          success: true,
          image_url: image_url,
          image_b64: image_b64,
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

      # Build a prompt that generates good app logos with transparent backgrounds
      <<~PROMPT.strip
        Create a modern app icon logo for "#{clean_name}" - #{clean_description.present? ? clean_description : "a web application"}.
        
        CRITICAL REQUIREMENTS:
        • TRANSPARENT BACKGROUND - The icon must have a fully transparent background, not white or any color
        • Single iconic symbol or abstract shape that represents the app's purpose
        • Clean, minimalist design optimized for small display sizes
        • Bold, geometric shapes with clear silhouettes
        • Modern flat design or subtle gradient within the icon itself
        • Professional color palette appropriate for the app type
        • NO text, letters, or words in the design
        • Centered composition with proper padding from edges
        • High contrast design that works on both light and dark backgrounds
        
        Style inspiration:
        • Think Apple App Store or Google Play Store icons
        • Simple, memorable, and instantly recognizable
        • Professional tech/startup aesthetic
        • Should work at 16x16px up to 1024x1024px
        
        The icon should be distinctive and convey the essence of #{clean_name} through visual metaphor, not literal representation.
      PROMPT
    end
  end
end