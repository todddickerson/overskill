module Ai
  class ImageGenerationService
    attr_reader :app, :openai_client, :ideogram_client

    def initialize(app = nil)
      @app = app
      @openai_client = OpenaiClient.new
      @ideogram_client = nil
      
      # Initialize Ideogram client for fallback
      begin
        @ideogram_client = IdeogramClient.new
      rescue => e
        Rails.logger.warn "[ImageGen] Ideogram not configured, will use OpenAI only: #{e.message}"
      end
    end

    # Main image generation method with provider fallback
    def generate_image(prompt:, width: 512, height: 512, model: 'flux.schnell', target_path: nil, options: {})
      # Validate dimensions
      validation_result = validate_dimensions(width, height)
      return validation_result if validation_result[:error]

      Rails.logger.info "[ImageGen] Generating image: #{prompt} (#{width}x#{height})"

      begin
        # Try OpenAI gpt-image-1 first (primary provider)
        result = generate_with_openai(prompt, width, height, options)
        if result[:success]
          Rails.logger.info "[ImageGen] Successfully generated with OpenAI gpt-image-1"
          return prepare_response(result, prompt, width, height, "gpt-image-1", target_path)
        else
          Rails.logger.warn "[ImageGen] OpenAI failed: #{result[:error]}"
        end

        # Fallback to Ideogram if available
        if @ideogram_client
          Rails.logger.info "[ImageGen] Falling back to Ideogram"
          result = generate_with_ideogram(prompt, width, height, options)
          if result[:success]
            Rails.logger.info "[ImageGen] Successfully generated with Ideogram"
            return prepare_response(result, prompt, width, height, "ideogram", target_path)
          else
            Rails.logger.warn "[ImageGen] Ideogram also failed: #{result[:error]}"
          end
        end

        # Both providers failed
        return { error: "Failed to generate image with both OpenAI and Ideogram providers" }

      rescue => e
        Rails.logger.error "[ImageGen] Exception during image generation: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        return { error: "Image generation failed: #{e.message}" }
      end
    end

    # Generate and save image to app files (for app builder)
    def generate_and_save_image(prompt:, width: 512, height: 512, target_path:, model: 'flux.schnell', options: {})
      unless @app
        return { error: "App context required for saving images" }
      end

      result = generate_image(
        prompt: prompt,
        width: width,
        height: height,
        model: model,
        target_path: target_path,
        options: options
      )

      if result[:success] && result[:image_data]
        save_image_to_app_files(target_path, result[:image_data])
        result.merge(path: target_path)
      else
        result
      end
    end

    # Generate logo (for logo service)
    def generate_logo(app_name, app_description, options: {})
      prompt = build_logo_prompt(app_name, app_description)
      
      # Use square aspect ratio for logos
      result = generate_image(
        prompt: prompt,
        width: 1024,
        height: 1024,
        options: options.merge(style_type: 'DESIGN')
      )

      if result[:success]
        result.merge(
          message: "Logo generated successfully (#{result[:provider]})",
          revised_prompt: prompt
        )
      else
        result
      end
    end

    private



    def validate_dimensions(width, height)
      if width < 512 || height < 512 || width > 1920 || height > 1920
        return { error: "Image dimensions must be between 512 and 1920 pixels" }
      end

      if width % 32 != 0 || height % 32 != 0
        return { error: "Image dimensions must be multiples of 32" }
      end

      { valid: true }
    end

    def generate_with_ideogram(prompt, width, height, options)
      Rails.logger.info "[ImageGen] Using Ideogram for image generation"

      # Build enhanced prompt
      enhanced_prompt = build_ideogram_prompt(prompt, width, height, options)
      
      # Calculate aspect ratio for Ideogram
      aspect_ratio = calculate_ideogram_aspect_ratio(width, height)
      
      # Generate with Ideogram
      result = @ideogram_client.generate_image(
        prompt: enhanced_prompt,
        aspect_ratio: aspect_ratio,
        rendering_speed: options[:rendering_speed] || "TURBO",
        style_type: options[:style_type] || "GENERAL",
        num_images: 1
      )

      if result[:success]
        # Download image content
        image_data = download_image_from_url(result[:image_url])
        if image_data
          result.merge(image_data: image_data)
        else
          { success: false, error: "Failed to download image from Ideogram URL" }
        end
      else
        result
      end
    end

    def generate_with_openai(prompt, width, height, options)
      Rails.logger.info "[ImageGen] Using OpenAI gpt-image-1 for image generation"

      # Determine size parameter for OpenAI
      openai_size = determine_openai_size(width, height)

      # Map quality options - gpt-image-1 supports 'standard' and 'hd'
      quality = case options[:quality]
                when 'high', 'hd', 'quality' then 'hd'
                else 'standard'
                end

      # Map style options - gpt-image-1 supports 'natural' and 'vivid'  
      style = case options[:style]
              when 'natural', 'realistic' then 'natural'
              when 'vivid', 'dramatic', 'design' then 'vivid'
              else 'vivid'  # Default to vivid for more dramatic results
              end

      result = @openai_client.generate_image(
        prompt,
        size: openai_size,
        quality: quality,
        style: style
      )

      if result[:success]
        image_data = nil

        # Handle different response formats
        if result[:image_url].present?
          image_data = download_image_from_url(result[:image_url])
        elsif result[:image_b64].present?
          image_data = Base64.decode64(result[:image_b64])
        end

        if image_data
          result.merge(image_data: image_data)
        else
          { success: false, error: "Failed to retrieve image content from OpenAI" }
        end
      else
        result
      end
    end

    def build_ideogram_prompt(prompt, width, height, options)
      aspect_info = if width > height
                      "landscape #{width}:#{height}"
                    elsif height > width
                      "portrait #{height}:#{width}"
                    else
                      "square 1:1"
                    end

      elements = [
        prompt,
        "high quality",
        "detailed",
        "sharp focus"
      ]

      # Add aspect ratio info unless it's a logo
      unless options[:style_type] == 'DESIGN'
        elements << "#{aspect_info} aspect ratio"
      end

      elements.join(", ")
    end

    def build_logo_prompt(app_name, app_description)
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

    def calculate_ideogram_aspect_ratio(width, height)
      # Common aspect ratios supported by Ideogram
      ratio = width.to_f / height.to_f
      
      case ratio
      when 0.5..0.75
        height > width ? "2x3" : "3x2"
      when 0.75..1.33
        "1x1"
      when 1.33..1.78
        width > height ? "4x3" : "3x4"
      when 1.78..2.0
        width > height ? "16x9" : "9x16"
      else
        "1x1" # Default fallback
      end
    end

    def determine_openai_size(width, height)
      # OpenAI DALL-E 3 supports specific sizes only
      aspect_ratio = width.to_f / height.to_f

      if aspect_ratio > 1.5
        "1792x1024"  # Wide image
      elsif aspect_ratio < 0.67
        "1024x1792"  # Tall image
      else
        "1024x1024"  # Square or near-square
      end
    end

    def download_image_from_url(url)
      require 'open-uri'

      Rails.logger.info "[ImageGen] Downloading image from URL: #{url[0..100]}..."

      # Download with timeout and size limits
      image_data = URI.open(url,
        read_timeout: 30,
        "User-Agent" => "OverSkill-ImageBot/1.0"
      ) do |file|
        # Limit file size to 10MB
        if file.respond_to?(:meta) && file.meta['content-length']
          size = file.meta['content-length'].to_i
          if size > 10.megabytes
            Rails.logger.error "[ImageGen] Image too large: #{size} bytes"
            return nil
          end
        end

        file.read
      end

      Rails.logger.info "[ImageGen] Successfully downloaded image (#{image_data.bytesize} bytes)"
      image_data

    rescue => e
      Rails.logger.error "[ImageGen] Failed to download image from URL: #{e.message}"
      nil
    end

    def save_image_to_app_files(target_path, image_content)
      # Save image as AppFile with binary content
      file = @app.app_files.find_or_initialize_by(path: target_path)

      # For binary files, we need to handle encoding properly
      file.content = Base64.encode64(image_content)
      file.file_type = determine_file_type(target_path)
      file.team = @app.team
      file.metadata = {
        'binary' => true,
        'encoding' => 'base64',
        'original_size' => image_content.bytesize,
        'generated_at' => Time.current.iso8601
      }

      file.save!
      Rails.logger.info "[ImageGen] Saved image file: #{target_path} (#{image_content.bytesize} bytes)"
    end

    def determine_file_type(path)
      case path
      when /\.(png|jpg|jpeg|gif|webp)$/i then 'image'
      when /\.svg$/i then 'svg'
      else 'binary'
      end
    end

    def prepare_response(result, prompt, width, height, provider, target_path)
      {
        success: true,
        prompt: prompt,
        dimensions: "#{width}x#{height}",
        provider: provider,
        image_data: result[:image_data],
        image_url: result[:image_url],
        path: target_path
      }
    end
  end
end