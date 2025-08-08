module Ai
  class LogoGeneratorService
    def initialize(app)
      @app = app
      @openai_client = OpenaiClient.new
      @ideogram_client = nil
      if ENV["IMAGE_PROVIDER"]&.downcase == "ideogram" || ENV["OPENAI_IMAGE_DISABLED"] == "true"
        begin
          @ideogram_client = IdeogramClient.new
        rescue => e
          Rails.logger.warn "[Logo] Ideogram not configured: #{e.message}"
        end
      end
    end

    def generate_logo
      Rails.logger.info "[Logo] Generating logo for app: #{@app.name}"

      # Choose provider
      result = nil
      if @ideogram_client
        # Use Ideogram
        prompt = build_ideogram_logo_prompt(@app.name, @app.prompt)
        result = @ideogram_client.generate_image(prompt: prompt)
        # Normalize to expected shape
        if result[:success]
          attach_logo_from_url(result[:image_url])
          return { success: true, message: "Logo generated successfully (Ideogram)" }
        else
          Rails.logger.warn "[Logo] Ideogram failed, falling back to OpenAI: #{result[:error]}"
        end
      end

      # Fallback to OpenAI
      result = @openai_client.generate_app_logo(@app.name, @app.prompt)

      if result[:success]
        # Attach from URL if provided, otherwise from base64 when available
        if result[:image_url].present?
          attach_logo_from_url(result[:image_url])
        elsif result[:image_b64].present?
          attach_logo_from_base64(result[:image_b64])
        else
          Rails.logger.error "[Logo] No image payload returned (neither URL nor base64)."
          return { success: false, error: "No image returned from provider" }
        end

        # Store the revised prompt for reference
        @app.update(logo_prompt: result[:revised_prompt]) if result[:revised_prompt]

        Rails.logger.info "[Logo] Successfully generated logo for app: #{@app.name}"
        { success: true, message: "Logo generated successfully" }
      else
        Rails.logger.error "[Logo] Failed to generate logo: #{result[:error]}"
        { success: false, error: result[:error] }
      end
    rescue => e
      Rails.logger.error "[Logo] Exception: #{e.message}"
      { success: false, error: e.message }
    end

    def regenerate_logo(custom_prompt = nil)
      # Allow regeneration with a custom prompt
      if custom_prompt.present?
        result = @openai_client.generate_image(custom_prompt, size: "1024x1024", quality: "standard", style: "vivid")
      else
        result = @openai_client.generate_app_logo(@app.name, @app.prompt)
      end

      if result[:success]
        if result[:image_url].present?
          attach_logo_from_url(result[:image_url])
        elsif result[:image_b64].present?
          attach_logo_from_base64(result[:image_b64])
        else
          return { success: false, error: "No image returned from provider" }
        end
        { success: true, message: "Logo regenerated successfully" }
      else
        { success: false, error: result[:error] }
      end
    end

    private
    def build_ideogram_logo_prompt(app_name, app_description)
      clean_name = app_name.to_s.strip[0..50]
      clean_description = app_description.to_s.strip[0..200]

      [
        "Create a modern, minimalist app icon logo",
        "transparent background",
        "no text",
        "bold geometric shape",
        "high contrast",
        "professional palette",
        "centered composition",
        "#{clean_name} - #{clean_description.present? ? clean_description : "web application"}"
      ].join(", ")
    end

    def attach_logo_from_url(url)
      require 'open-uri'
      
      # Download the image
      downloaded_image = URI.open(url)
      
      # Generate a filename
      filename = "app_logo_#{@app.id}_#{Time.current.to_i}.png"
      
      # Attach to the app (assuming you have Active Storage set up)
      @app.logo.attach(
        io: downloaded_image,
        filename: filename,
        content_type: 'image/png'
      )
    rescue => e
      Rails.logger.error "[Logo] Failed to attach image: #{e.message}"
      raise e
    end

    def attach_logo_from_base64(b64)
      decoded = Base64.decode64(b64)
      filename = "app_logo_#{@app.id}_#{Time.current.to_i}.png"
      @app.logo.attach(
        io: StringIO.new(decoded),
        filename: filename,
        content_type: 'image/png'
      )
    rescue => e
      Rails.logger.error "[Logo] Failed to attach base64 image: #{e.message}"
      raise e
    end
  end
end