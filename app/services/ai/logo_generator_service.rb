module Ai
  class LogoGeneratorService
    def initialize(app)
      @app = app
      @openai_client = OpenaiClient.new
    end

    def generate_logo
      Rails.logger.info "[Logo] Generating logo for app: #{@app.name}"

      # Generate the logo using DALL-E
      result = @openai_client.generate_app_logo(@app.name, @app.prompt)

      if result[:success]
        # Download and attach the image
        attach_logo_from_url(result[:image_url])
        
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
        attach_logo_from_url(result[:image_url])
        { success: true, message: "Logo regenerated successfully" }
      else
        { success: false, error: result[:error] }
      end
    end

    private

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
  end
end