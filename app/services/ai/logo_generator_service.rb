module Ai
  class LogoGeneratorService
    def initialize(app)
      @app = app
      @image_service = ImageGenerationService.new(app)
    end

    def generate_logo
      Rails.logger.info "[Logo] Generating logo for app: #{@app.name}"

      result = @image_service.generate_logo(@app.name, @app.prompt)

      if result[:success]
        # Attach the generated image
        if result[:image_data].present?
          attach_logo_from_data(result[:image_data])
        elsif result[:image_url].present?
          attach_logo_from_url(result[:image_url])
        else
          Rails.logger.error "[Logo] No image data returned from generation service"
          return {success: false, error: "No image returned from provider"}
        end

        # Store the revised prompt for reference
        @app.update(logo_prompt: result[:revised_prompt]) if result[:revised_prompt]

        Rails.logger.info "[Logo] Successfully generated logo for app: #{@app.name}"
      else
        Rails.logger.error "[Logo] Failed to generate logo: #{result[:error]}"
      end
      result
    rescue => e
      Rails.logger.error "[Logo] Exception: #{e.message}"
      {success: false, error: e.message}
    end

    def regenerate_logo(custom_prompt = nil)
      # Allow regeneration with a custom prompt
      result = if custom_prompt.present?
        @image_service.generate_image(
          prompt: custom_prompt,
          width: 1024,
          height: 1024,
          options: {style_type: "DESIGN"}
        )
      else
        @image_service.generate_logo(@app.name, @app.prompt)
      end

      if result[:success]
        if result[:image_data].present?
          attach_logo_from_data(result[:image_data])
        elsif result[:image_url].present?
          attach_logo_from_url(result[:image_url])
        else
          return {success: false, error: "No image returned from provider"}
        end
        {success: true, message: "Logo regenerated successfully"}
      else
        {success: false, error: result[:error]}
      end
    end

    private

    def attach_logo_from_data(image_data)
      # Generate a filename
      filename = "app_logo_#{@app.id}_#{Time.current.to_i}.png"

      # Attach to the app using StringIO
      @app.logo.attach(
        io: StringIO.new(image_data),
        filename: filename,
        content_type: "image/png"
      )
    rescue => e
      Rails.logger.error "[Logo] Failed to attach image from data: #{e.message}"
      raise e
    end

    def attach_logo_from_url(url)
      require "open-uri"

      # Download the image
      downloaded_image = URI.open(url)

      # Generate a filename
      filename = "app_logo_#{@app.id}_#{Time.current.to_i}.png"

      # Attach to the app (assuming you have Active Storage set up)
      @app.logo.attach(
        io: downloaded_image,
        filename: filename,
        content_type: "image/png"
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
        content_type: "image/png"
      )
    rescue => e
      Rails.logger.error "[Logo] Failed to attach base64 image: #{e.message}"
      raise e
    end
  end
end
