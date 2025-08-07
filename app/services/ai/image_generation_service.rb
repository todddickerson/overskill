module Ai
  # AI-powered image generation service for creating app assets
  # Similar to Lovable's generate_image and edit_image tools
  class ImageGenerationService
    include HTTParty
    
    # Image generation providers
    PROVIDERS = {
      openai: {
        base_url: 'https://api.openai.com/v1',
        models: {
          'dall-e-3': { max_size: 1024, quality: 'standard', style: 'vivid' },
          'dall-e-2': { max_size: 1024 }
        }
      },
      stability: {
        base_url: 'https://api.stability.ai/v1',
        models: {
          'stable-diffusion-xl-1024-v1-0': { max_size: 1024 },
          'stable-diffusion-xl-beta-v2-2-2': { max_size: 512 }
        }
      },
      replicate: {
        base_url: 'https://api.replicate.com/v1',
        models: {
          'flux-schnell': { max_size: 1920, speed: 'fast', quality: 'good' },
          'flux-dev': { max_size: 1920, speed: 'slow', quality: 'best' }
        }
      }
    }.freeze
    
    # Dimension presets for common use cases
    DIMENSION_PRESETS = {
      square: { width: 1024, height: 1024 },
      landscape: { width: 1792, height: 1024 },
      portrait: { width: 1024, height: 1792 },
      banner: { width: 1920, height: 480 },
      hero: { width: 1920, height: 1080 },
      thumbnail: { width: 512, height: 512 },
      icon: { width: 256, height: 256 },
      social: { width: 1200, height: 630 },
      mobile: { width: 390, height: 844 }
    }.freeze
    
    def initialize(app, provider: :openai)
      @app = app
      @provider = provider
      @api_key = get_api_key(provider)
      @base_url = PROVIDERS[provider][:base_url]
    end
    
    # Generate an image based on text prompt (similar to Lovable's generate_image)
    def generate_image(prompt:, target_path:, width: nil, height: nil, model: nil, style_preset: nil)
      # Enhance prompt for better quality
      enhanced_prompt = enhance_prompt(prompt, style_preset)
      
      # Determine dimensions
      dimensions = determine_dimensions(width, height, target_path)
      
      # Select appropriate model based on requirements
      selected_model = select_model(model, dimensions[:width], dimensions[:height])
      
      Rails.logger.info "[ImageGeneration] Generating image with #{@provider}/#{selected_model}"
      Rails.logger.info "[ImageGeneration] Prompt: #{enhanced_prompt[0..100]}..."
      Rails.logger.info "[ImageGeneration] Dimensions: #{dimensions[:width]}x#{dimensions[:height]}"
      
      # Generate based on provider
      result = case @provider
      when :openai
        generate_with_openai(enhanced_prompt, selected_model, dimensions)
      when :stability
        generate_with_stability(enhanced_prompt, selected_model, dimensions)
      when :replicate
        generate_with_replicate(enhanced_prompt, selected_model, dimensions)
      else
        { success: false, error: "Unknown provider: #{@provider}" }
      end
      
      # Save the generated image if successful
      if result[:success]
        save_result = save_image_to_app(result[:image_data], target_path, result[:metadata])
        
        if save_result[:success]
          Rails.logger.info "[ImageGeneration] Saved image to #{target_path}"
          {
            success: true,
            target_path: target_path,
            size: save_result[:size],
            dimensions: dimensions,
            model: selected_model,
            provider: @provider,
            message: "Generated and saved image to #{target_path}"
          }
        else
          save_result
        end
      else
        result
      end
    rescue => e
      Rails.logger.error "[ImageGeneration] Failed: #{e.message}"
      { success: false, error: e.message }
    end
    
    # Edit an existing image with AI (similar to Lovable's edit_image)
    def edit_image(image_paths:, prompt:, target_path:, strength: 0.75)
      # This would integrate with image editing APIs
      # For now, we'll implement a basic version
      
      Rails.logger.info "[ImageGeneration] Editing #{image_paths.length} images with prompt: #{prompt[0..50]}..."
      
      if image_paths.empty?
        return { success: false, error: "No images provided for editing" }
      end
      
      # In production, this would:
      # 1. Load the existing images
      # 2. Send to an AI editing API (like Stability's img2img or DALL-E edit)
      # 3. Apply the transformations based on the prompt
      # 4. Save the result
      
      {
        success: false,
        error: "Image editing requires API integration (coming soon)",
        suggestion: "For now, generate a new image with your desired changes"
      }
    end
    
    # Generate multiple variations of an image
    def generate_variations(prompt:, count: 3, base_style: nil)
      variations = []
      
      count.times do |i|
        variation_prompt = vary_prompt(prompt, i)
        target_path = "src/assets/generated_variation_#{i + 1}.png"
        
        result = generate_image(
          prompt: variation_prompt,
          target_path: target_path,
          style_preset: base_style
        )
        
        variations << result if result[:success]
      end
      
      {
        success: true,
        variations: variations,
        count: variations.length
      }
    end
    
    # Generate app-specific images (icons, splash screens, etc.)
    def generate_app_assets(app_type:, theme: nil)
      assets = []
      
      # Determine what assets to generate based on app type
      asset_configs = case app_type
      when 'dashboard', 'saas'
        [
          { name: 'logo', prompt: "Modern minimalist logo for a SaaS dashboard app", size: :icon },
          { name: 'hero', prompt: "Abstract geometric hero image for a modern dashboard", size: :hero },
          { name: 'pattern', prompt: "Subtle geometric pattern background", size: :square }
        ]
      when 'landing_page'
        [
          { name: 'hero', prompt: "Stunning hero image for a modern landing page", size: :hero },
          { name: 'feature1', prompt: "Icon representing speed and efficiency", size: :thumbnail },
          { name: 'feature2', prompt: "Icon representing security and trust", size: :thumbnail },
          { name: 'feature3', prompt: "Icon representing collaboration", size: :thumbnail }
        ]
      when 'game'
        [
          { name: 'background', prompt: "Game background with vibrant colors", size: :landscape },
          { name: 'character', prompt: "Friendly game character sprite", size: :square },
          { name: 'item', prompt: "Collectible game item icon", size: :icon }
        ]
      else
        [
          { name: 'logo', prompt: "Modern app logo", size: :icon },
          { name: 'hero', prompt: "Beautiful hero image", size: :hero }
        ]
      end
      
      # Add theme to prompts if specified
      if theme
        asset_configs.each do |config|
          config[:prompt] += ", #{theme} style"
        end
      end
      
      # Generate each asset
      asset_configs.each do |config|
        dimensions = DIMENSION_PRESETS[config[:size]]
        target_path = "src/assets/#{config[:name]}.png"
        
        result = generate_image(
          prompt: config[:prompt],
          target_path: target_path,
          width: dimensions[:width],
          height: dimensions[:height]
        )
        
        assets << result if result[:success]
      end
      
      {
        success: true,
        assets: assets,
        total: assets.length,
        app_type: app_type
      }
    end
    
    private
    
    def get_api_key(provider)
      case provider
      when :openai
        ENV['OPENAI_API_KEY']
      when :stability
        ENV['STABILITY_API_KEY']
      when :replicate
        ENV['REPLICATE_API_TOKEN']
      else
        nil
      end
    end
    
    def enhance_prompt(prompt, style_preset)
      enhanced = prompt.dup
      
      # Add quality modifiers
      quality_terms = ["high quality", "professional", "detailed", "4k", "ultra high resolution"]
      enhanced += ", #{quality_terms.sample}"
      
      # Add style if specified
      if style_preset
        style_descriptions = {
          modern: "modern, clean, minimalist design",
          vintage: "vintage, retro, nostalgic style",
          futuristic: "futuristic, sci-fi, high-tech",
          realistic: "photorealistic, highly detailed",
          artistic: "artistic, creative, stylized",
          corporate: "professional, corporate, business-oriented",
          playful: "fun, colorful, playful design"
        }
        
        if style_descriptions[style_preset.to_sym]
          enhanced += ", #{style_descriptions[style_preset.to_sym]}"
        end
      end
      
      # Add aspect ratio hint
      enhanced += ", perfect composition"
      
      enhanced
    end
    
    def determine_dimensions(width, height, target_path)
      # If dimensions provided, use them
      if width && height
        return { width: constrain_dimension(width), height: constrain_dimension(height) }
      end
      
      # Infer from target path
      if target_path
        case target_path.downcase
        when /hero/
          return DIMENSION_PRESETS[:hero]
        when /banner/
          return DIMENSION_PRESETS[:banner]
        when /icon/
          return DIMENSION_PRESETS[:icon]
        when /thumbnail/
          return DIMENSION_PRESETS[:thumbnail]
        when /logo/
          return DIMENSION_PRESETS[:icon]
        when /background/
          return DIMENSION_PRESETS[:landscape]
        end
      end
      
      # Default to square
      DIMENSION_PRESETS[:square]
    end
    
    def constrain_dimension(value)
      # Ensure dimensions are multiples of 32 and within limits
      value = (value / 32.0).round * 32
      [[value, 1920].min, 256].max
    end
    
    def select_model(requested_model, width, height)
      return requested_model if requested_model
      
      max_dimension = [width, height].max
      
      case @provider
      when :openai
        max_dimension <= 1024 ? 'dall-e-3' : 'dall-e-2'
      when :stability
        'stable-diffusion-xl-1024-v1-0'
      when :replicate
        max_dimension <= 1024 ? 'flux-schnell' : 'flux-dev'
      else
        'default'
      end
    end
    
    def generate_with_openai(prompt, model, dimensions)
      return { success: false, error: "OpenAI API key not configured" } unless @api_key
      
      # OpenAI DALL-E API call
      response = HTTParty.post(
        "#{@base_url}/images/generations",
        headers: {
          'Authorization' => "Bearer #{@api_key}",
          'Content-Type' => 'application/json'
        },
        body: {
          model: model,
          prompt: prompt,
          n: 1,
          size: "#{dimensions[:width]}x#{dimensions[:height]}",
          quality: 'standard',
          response_format: 'b64_json'
        }.to_json
      )
      
      if response.success?
        image_data = response.parsed_response.dig('data', 0, 'b64_json')
        if image_data
          {
            success: true,
            image_data: image_data,
            metadata: { model: model, provider: 'openai' }
          }
        else
          { success: false, error: "No image data in response" }
        end
      else
        { success: false, error: response.parsed_response['error']&.dig('message') || "API error" }
      end
    rescue => e
      { success: false, error: "OpenAI generation failed: #{e.message}" }
    end
    
    def generate_with_stability(prompt, model, dimensions)
      # Stability AI implementation
      # This would integrate with Stability AI's API
      { 
        success: false, 
        error: "Stability AI integration coming soon",
        suggestion: "Use OpenAI provider for now"
      }
    end
    
    def generate_with_replicate(prompt, model, dimensions)
      # Replicate implementation for Flux models
      # This would integrate with Replicate's API
      { 
        success: false, 
        error: "Replicate integration coming soon",
        suggestion: "Use OpenAI provider for now"
      }
    end
    
    def save_image_to_app(image_data, target_path, metadata = {})
      # Ensure path is in assets folder
      target_path = "src/assets/#{File.basename(target_path)}" unless target_path.start_with?('src/assets/')
      
      file = @app.app_files.find_or_initialize_by(path: target_path)
      file.content = image_data  # Base64 encoded
      file.file_type = 'image'
      file.is_binary = true
      file.team = @app.team if file.new_record?
      
      # Store metadata
      file_metadata = metadata.merge({
        generated_at: Time.current.iso8601,
        provider: @provider,
        dimensions: "#{metadata[:width]}x#{metadata[:height]}"
      })
      
      file.metadata = file_metadata.to_json
      
      if file.save
        # Clear cache
        Ai::ContextCacheService.new.clear_app_cache(@app.id)
        
        {
          success: true,
          path: target_path,
          size: (image_data.length * 3 / 4), # Approximate decoded size
          metadata: file_metadata
        }
      else
        { success: false, error: file.errors.full_messages.join(', ') }
      end
    end
    
    def vary_prompt(base_prompt, variation_index)
      variations = [
        "#{base_prompt}, alternative style",
        "#{base_prompt}, different perspective",
        "#{base_prompt}, unique interpretation",
        "#{base_prompt}, creative variation",
        "#{base_prompt}, fresh approach"
      ]
      
      variations[variation_index % variations.length]
    end
  end
end