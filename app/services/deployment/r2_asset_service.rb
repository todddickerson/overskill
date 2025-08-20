# Service for uploading static assets to Cloudflare R2 storage
# This reduces Worker bundle size by offloading images, fonts, and large files to R2
require 'aws-sdk-s3'
require 'digest'

module Deployment
  class R2AssetService
    attr_reader :app, :bucket_name, :client
    
    # File size threshold for R2 upload (50KB)
    SIZE_THRESHOLD = 50_000
    
    # Asset file extensions that should always go to R2
    ASSET_EXTENSIONS = %w[
      .jpg .jpeg .png .gif .webp .svg .ico
      .woff .woff2 .ttf .otf .eot
      .mp4 .webm .mp3 .wav
      .pdf .zip
    ].freeze
    
    def initialize(app)
      @app = app
      @bucket_name = ENV['CLOUDFLARE_R2_BUCKET'] || 'overskill-apps-dev'
      
      # Initialize S3-compatible client for R2
      @client = Aws::S3::Client.new(
        access_key_id: ENV['CLOUDFLARE_R2_ACCESS_KEY_ID'],
        secret_access_key: ENV['CLOUDFLARE_R2_SECRET_ACCESS_KEY'],
        endpoint: ENV['CLOUDFLARE_R2_ENDPOINT'],
        region: 'auto',
        force_path_style: true
      )
      
      @public_base_url = ENV['CLOUDFLARE_R2_PUBLIC_URL'] || "https://pub.overskill.app"
    end
    
    # Upload built files to R2 and return mapping of paths to URLs
    def upload_assets(built_files)
      Rails.logger.info "[R2Asset] Processing #{built_files.keys.size} files for app #{@app.id}"
      
      asset_urls = {}
      uploaded_count = 0
      uploaded_size = 0
      
      built_files.each do |path, file_data|
        if should_upload_to_r2?(path, file_data)
          begin
            url = upload_to_r2(path, file_data)
            asset_urls[path] = url
            uploaded_count += 1
            uploaded_size += calculate_file_size(file_data)
            Rails.logger.info "[R2Asset] Uploaded: #{path} -> #{url}"
          rescue => e
            Rails.logger.error "[R2Asset] Failed to upload #{path}: #{e.message}"
            # Continue with other files even if one fails
          end
        end
      end
      
      Rails.logger.info "[R2Asset] Uploaded #{uploaded_count} assets (#{(uploaded_size / 1024.0 / 1024.0).round(2)} MB) to R2"
      
      {
        asset_urls: asset_urls,
        stats: {
          uploaded_count: uploaded_count,
          uploaded_size: uploaded_size,
          total_files: built_files.keys.size
        }
      }
    end
    
    # Upload a single file to R2
    def upload_file(path, content, content_type: nil)
      key = build_s3_key(path)
      
      # Prepare upload parameters
      upload_params = {
        bucket: @bucket_name,
        key: key,
        body: content,
        content_type: content_type || detect_content_type(path),
        cache_control: cache_control_for_path(path),
        metadata: {
          'app-id' => @app.id.to_s,
          'app-name' => @app.name.to_s,
          'uploaded-at' => Time.current.iso8601
        }
      }
      
      # Add content encoding for text files
      if text_file?(path) && !binary_content?(content)
        upload_params[:content_encoding] = 'utf-8'
      end
      
      # Upload to R2
      @client.put_object(upload_params)
      
      # Return public URL
      build_public_url(key)
    end
    
    private
    
    def should_upload_to_r2?(path, file_data)
      # Upload if it's an asset file type
      return true if asset_file?(path)
      
      # Upload if file is larger than threshold
      size = calculate_file_size(file_data)
      return true if size > SIZE_THRESHOLD
      
      # Don't upload HTML, small JS/CSS files
      false
    end
    
    def asset_file?(path)
      extension = File.extname(path).downcase
      ASSET_EXTENSIONS.include?(extension)
    end
    
    def upload_to_r2(path, file_data)
      content = prepare_content(file_data)
      content_type = file_data[:content_type] || detect_content_type(path)
      
      upload_file(path, content, content_type: content_type)
    end
    
    def prepare_content(file_data)
      if file_data[:binary]
        # Decode base64 for binary files
        Base64.decode64(file_data[:content])
      else
        # Use content as-is for text files
        file_data[:content]
      end
    end
    
    def calculate_file_size(file_data)
      if file_data[:binary]
        # Calculate size of decoded binary
        Base64.decode64(file_data[:content]).bytesize
      else
        file_data[:content].bytesize
      end
    end
    
    def build_s3_key(path)
      # Structure: app-{uuid}/{environment}/{path}
      # Remove leading slash if present
      clean_path = path.start_with?('/') ? path[1..] : path
      
      "app-#{@app.id}/production/#{clean_path}"
    end
    
    def build_public_url(key)
      # Use public R2 URL or fallback to direct R2 endpoint
      if @public_base_url.present?
        "#{@public_base_url}/#{key}"
      else
        "#{ENV['CLOUDFLARE_R2_ENDPOINT']}/#{@bucket_name}/#{key}"
      end
    end
    
    def detect_content_type(path)
      extension = File.extname(path).downcase
      
      case extension
      # Images
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.png' then 'image/png'
      when '.gif' then 'image/gif'
      when '.webp' then 'image/webp'
      when '.svg' then 'image/svg+xml'
      when '.ico' then 'image/x-icon'
      
      # Fonts
      when '.woff' then 'font/woff'
      when '.woff2' then 'font/woff2'
      when '.ttf' then 'font/ttf'
      when '.otf' then 'font/otf'
      when '.eot' then 'application/vnd.ms-fontobject'
      
      # Documents
      when '.pdf' then 'application/pdf'
      when '.zip' then 'application/zip'
      
      # Media
      when '.mp4' then 'video/mp4'
      when '.webm' then 'video/webm'
      when '.mp3' then 'audio/mpeg'
      when '.wav' then 'audio/wav'
      
      # Web files
      when '.html' then 'text/html'
      when '.css' then 'text/css'
      when '.js', '.mjs' then 'application/javascript'
      when '.json' then 'application/json'
      when '.xml' then 'application/xml'
      
      else
        'application/octet-stream'
      end
    end
    
    def cache_control_for_path(path)
      extension = File.extname(path).downcase
      
      # Immutable for versioned assets
      if path.include?('/assets/') && path.match?(/\-[a-f0-9]{8}\./)
        'public, max-age=31536000, immutable'
      # Long cache for fonts and images
      elsif ASSET_EXTENSIONS.include?(extension)
        'public, max-age=2592000' # 30 days
      # Short cache for HTML
      elsif extension == '.html'
        'public, max-age=300' # 5 minutes
      # Medium cache for JS/CSS
      elsif ['.js', '.css'].include?(extension)
        'public, max-age=86400' # 1 day
      else
        'public, max-age=3600' # 1 hour
      end
    end
    
    def text_file?(path)
      extension = File.extname(path).downcase
      ['.html', '.css', '.js', '.json', '.xml', '.svg', '.txt'].include?(extension)
    end
    
    def binary_content?(content)
      # Check if content appears to be binary
      content.encoding == Encoding::ASCII_8BIT || content.include?("\x00")
    end
    
    # Check if R2 bucket is accessible
    def verify_connection
      @client.head_bucket(bucket: @bucket_name)
      true
    rescue => e
      Rails.logger.error "[R2Asset] Cannot access R2 bucket: #{e.message}"
      false
    end
    
    # Get URL for existing asset
    def get_asset_url(path)
      key = build_s3_key(path)
      build_public_url(key)
    end
    
    # Delete assets for an app (cleanup)
    def delete_app_assets
      prefix = "app-#{@app.id}/"
      
      objects = @client.list_objects_v2(
        bucket: @bucket_name,
        prefix: prefix
      )
      
      return if objects.contents.empty?
      
      # Delete in batches
      delete_objects = objects.contents.map { |obj| { key: obj.key } }
      
      @client.delete_objects(
        bucket: @bucket_name,
        delete: {
          objects: delete_objects
        }
      )
      
      Rails.logger.info "[R2Asset] Deleted #{delete_objects.size} assets for app #{@app.id}"
    end
  end
end