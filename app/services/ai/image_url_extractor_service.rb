# Service to extract R2 URLs from image placeholder files and create imageUrls.js
# This ensures components can easily reference generated images

module Ai
  class ImageUrlExtractorService
    def initialize(app)
      @app = app
      @logger = Rails.logger
    end

    # Extract all image URLs from placeholder files
    def extract_all_image_urls
      @logger.info "[ImageUrlExtractor] Extracting image URLs for app #{@app.id}"

      # Find all image placeholder files in assets
      image_files = @app.app_files.where("path LIKE ? OR path LIKE ?", "src/assets/%.jpg", "src/assets/%.png")
        .or(@app.app_files.where("path LIKE ?", "src/assets/%.webp"))
        .or(@app.app_files.where("path LIKE ?", "src/assets/%.gif"))

      urls = {}

      image_files.each do |file|
        # Extract R2 URL from HTML comment in placeholder
        if file.content =~ /<!-- Image hosted on R2: (.+?) -->/
          url = $1
          filename = File.basename(file.path)
          urls[filename] = url
          @logger.debug "[ImageUrlExtractor] Found URL for #{filename}: #{url}"
        elsif file.content =~ /https:\/\/pub\.overskill\.com\/[^\s]+/
          # Fallback: try to find any R2 URL in content
          url = $&
          filename = File.basename(file.path)
          urls[filename] = url
          @logger.debug "[ImageUrlExtractor] Found URL (fallback) for #{filename}: #{url}"
        else
          # If no URL found, construct the expected R2 URL
          filename = File.basename(file.path)
          url = construct_r2_url(file.path)
          urls[filename] = url
          @logger.warn "[ImageUrlExtractor] No URL found for #{filename}, using constructed: #{url}"
        end
      end

      @logger.info "[ImageUrlExtractor] Extracted #{urls.size} image URLs"
      urls
    end

    # Create or update the imageUrls.js module
    def create_image_urls_module
      urls = extract_all_image_urls

      if urls.empty?
        @logger.info "[ImageUrlExtractor] No image URLs to export, skipping imageUrls.js creation"
        return false
      end

      content = generate_image_urls_content(urls)

      # Create or update the imageUrls.js file
      file = @app.app_files.find_or_initialize_by(path: "src/imageUrls.js")
      file.content = content
      file.file_type = "javascript"
      file.team = @app.team

      if file.save
        @logger.info "[ImageUrlExtractor] Created/updated imageUrls.js with #{urls.size} URLs"
        true
      else
        @logger.error "[ImageUrlExtractor] Failed to save imageUrls.js: #{file.errors.full_messages.join(", ")}"
        false
      end
    end

    # Create a TypeScript version for TypeScript projects
    def create_image_urls_module_ts
      urls = extract_all_image_urls

      return false if urls.empty?

      content = generate_image_urls_content_ts(urls)

      file = @app.app_files.find_or_initialize_by(path: "src/imageUrls.ts")
      file.content = content
      file.file_type = "typescript"
      file.team = @app.team

      if file.save
        @logger.info "[ImageUrlExtractor] Created/updated imageUrls.ts with #{urls.size} URLs"
        true
      else
        @logger.error "[ImageUrlExtractor] Failed to save imageUrls.ts: #{file.errors.full_messages.join(", ")}"
        false
      end
    end

    # Process all images and ensure proper setup
    def process_all_images
      @logger.info "[ImageUrlExtractor] Processing all images for app #{@app.id}"

      # Create both JS and TS versions for maximum compatibility
      js_result = create_image_urls_module
      ts_result = create_image_urls_module_ts

      # Also ensure assetResolver is configured properly
      update_asset_resolver_config

      js_result || ts_result
    end

    private

    def construct_r2_url(path)
      # Remove any leading slash
      clean_path = path.start_with?("/") ? path[1..] : path

      # Standard R2 URL format
      "https://pub.overskill.com/app-#{@app.id}/production/#{clean_path}"
    end

    def generate_image_urls_content(urls)
      <<~JS
        // Auto-generated image URL mappings for #{@app.name}
        // Generated at: #{Time.current.iso8601}
        // This file is automatically created from image placeholder files
        
        export const imageUrls = {
        #{urls.map { |name, url| "  '#{name}': '#{url}'" }.join(",\n")}
        };
        
        // Helper function to get image URL with fallback
        export function getImageUrl(imageName) {
          return imageUrls[imageName] || `https://pub.overskill.com/app-#{@app.id}/production/src/assets/${imageName}`;
        }
        
        // For direct imports
        export default imageUrls;
      JS
    end

    def generate_image_urls_content_ts(urls)
      <<~TS
        // Auto-generated image URL mappings for #{@app.name}
        // Generated at: #{Time.current.iso8601}
        // This file is automatically created from image placeholder files
        
        interface ImageUrls {
          [key: string]: string;
        }
        
        export const imageUrls: ImageUrls = {
        #{urls.map { |name, url| "  '#{name}': '#{url}'" }.join(",\n")}
        };
        
        // Helper function to get image URL with fallback
        export function getImageUrl(imageName: string): string {
          return imageUrls[imageName] || `https://pub.overskill.com/app-#{@app.id}/production/src/assets/${imageName}`;
        }
        
        // For direct imports
        export default imageUrls;
      TS
    end

    def update_asset_resolver_config
      # Update the assetResolver.js to include app-specific config
      asset_resolver = @app.app_files.find_by(path: "src/assetResolver.js")

      if asset_resolver
        # Check if it needs app ID injection
        if asset_resolver.content.include?("process.env.VITE_APP_ID")
          # Already configured, just ensure the env var is set
          ensure_env_vars_configured
        end
      end
    end

    def ensure_env_vars_configured
      env_file = @app.app_files.find_or_initialize_by(path: ".env.local")

      unless env_file.content&.include?("VITE_APP_ID")
        env_content = env_file.content || ""
        env_content += "\n" unless env_content.empty?
        env_content += "VITE_APP_ID=#{@app.id}\n"
        env_content += "VITE_R2_BASE_URL=https://pub.overskill.com\n" unless env_content.include?("VITE_R2_BASE_URL")

        env_file.content = env_content
        env_file.file_type = "env"
        env_file.team = @app.team
        env_file.save!

        @logger.info "[ImageUrlExtractor] Updated .env.local with app configuration"
      end
    end
  end
end
