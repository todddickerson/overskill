module Ai
  class IdeogramClient
    include HTTParty

    DEFAULT_BASE_URL = "https://api.ideogram.ai".freeze

    def initialize(api_key: nil, base_url: nil)
      @api_key = api_key || ENV["IDEOGRAM_API_KEY"]
      @base_url = base_url || ENV["IDEOGRAM_BASE_URL"] || DEFAULT_BASE_URL
      raise "IDEOGRAM_API_KEY not configured" if @api_key.blank?
    end

    # Generate an image from a text prompt using Ideogram's latest API
    # Returns: { success: true, image_url: "..." } or { success: false, error: "..." }
    def generate_image(prompt:, rendering_speed: "TURBO", model: "ideogram-v3", aspect_ratio: "1x1")
      endpoint = "/v1/#{model}/generate"

      headers = {
        "Api-Key" => @api_key,
        "Content-Type" => "application/json"
      }

      body = {
        prompt: prompt,
        rendering_speed: rendering_speed,
        aspect_ratio: normalize_aspect_ratio(aspect_ratio)
      }

      response = self.class.post(
        File.join(@base_url, endpoint),
        headers: headers,
        body: body.to_json,
        timeout: 60
      )

      if response.success?
        parsed = response.parsed_response

        # Try common response shapes
        image_url =
          parsed.dig("data", 0, "url") ||
          parsed.dig("images", 0, "url") ||
          parsed.dig("result", "image_url") ||
          parsed["image_url"]

        if image_url.present?
          { success: true, image_url: image_url }
        else
          { success: false, error: "No image URL found in Ideogram response" }
        end
      else
        { success: false, error: response.parsed_response || response.body }
      end
    rescue => e
      { success: false, error: e.message }
    end

    private

    # Ideogram expects aspect ratios like '1x1', '3x2', '16x9', etc.
    def normalize_aspect_ratio(input)
      return "1x1" if input.nil?
      value = input.to_s.strip.upcase

      # Common aliases
      return "1x1" if ["SQUARE", "SQ", "1:1"].include?(value)

      # Convert colon to x
      value = value.tr(":", "x")

      allowed = %w[1x3 3x1 1x2 2x1 9x16 16x9 10x16 16x10 2x3 3x2 3x4 4x3 4x5 5x4 1x1]
      allowed.include?(value.downcase) ? value.downcase : "1x1"
    end
  end
end


