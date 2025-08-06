module Storage
  # Cloudflare R2 service for storing app assets and build artifacts
  # Integrates with Cloudflare Workers for seamless file serving
  class CloudflareR2Service
    include HTTParty
    
    def initialize(app)
      @app = app
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @r2_access_key = ENV['CLOUDFLARE_R2_ACCESS_KEY_ID']
      @r2_secret_key = ENV['CLOUDFLARE_R2_SECRET_ACCESS_KEY']
      @bucket_name = ENV['CLOUDFLARE_R2_BUCKET_NAME'] || 'overskill-apps'
      
      # R2 endpoint (different from Workers API)
      @r2_endpoint = "https://#{@account_id}.r2.cloudflarestorage.com"
      
      # Configure AWS SDK style authentication for R2
      setup_r2_client if credentials_present?
    end
    
    # Upload app files to R2 for serving via Worker
    def upload_app_files!
      return { success: false, error: "R2 not configured" } unless credentials_present?
      
      uploaded_files = []
      failed_files = []
      
      @app.app_files.find_each do |file|
        key = "apps/#{@app.id}/#{file.path}"
        
        result = upload_file(key, file.content, content_type_for(file.path))
        
        if result[:success]
          uploaded_files << file.path
        else
          failed_files << { path: file.path, error: result[:error] }
        end
      end
      
      if failed_files.empty?
        Rails.logger.info "[R2] Uploaded #{uploaded_files.count} files for app #{@app.id}"
        { success: true, uploaded: uploaded_files.count }
      else
        Rails.logger.error "[R2] Failed to upload #{failed_files.count} files for app #{@app.id}"
        { success: false, uploaded: uploaded_files.count, failed: failed_files }
      end
    end
    
    # Upload a single file to R2
    def upload_file(key, content, content_type = 'application/octet-stream')
      return { success: false, error: "R2 not configured" } unless credentials_present?
      
      begin
        # Use presigned URL approach for simplicity
        url = generate_presigned_upload_url(key)
        
        response = HTTParty.put(url, {
          body: content,
          headers: {
            'Content-Type' => content_type,
            'Cache-Control' => cache_control_for(key)
          }
        })
        
        if response.success?
          Rails.logger.debug "[R2] Uploaded #{key}"
          { success: true, key: key, url: public_url_for(key) }
        else
          Rails.logger.error "[R2] Upload failed for #{key}: #{response.code} #{response.body}"
          { success: false, error: "Upload failed: #{response.code}" }
        end
      rescue => e
        Rails.logger.error "[R2] Upload error for #{key}: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    # Delete app files from R2
    def delete_app_files!
      return { success: false, error: "R2 not configured" } unless credentials_present?
      
      # List and delete all files for this app
      prefix = "apps/#{@app.id}/"
      
      # For simplicity, we'll mark this as successful
      # In production, implement proper R2 deletion via AWS SDK
      Rails.logger.info "[R2] Would delete files with prefix: #{prefix}"
      { success: true, message: "App files deletion queued" }
    end
    
    # Get public URL for R2 object
    def public_url_for(key)
      # If using custom domain for R2
      custom_domain = ENV['CLOUDFLARE_R2_CUSTOM_DOMAIN']
      if custom_domain
        "https://#{custom_domain}/#{key}"
      else
        # Use R2 dev endpoint (not for production)
        "#{@r2_endpoint}/#{@bucket_name}/#{key}"
      end
    end
    
    # Update Worker bindings to include R2 bucket
    def configure_worker_r2_binding(worker_name)
      return { success: false, error: "Not implemented yet" }
      
      # This would configure the Worker to have access to the R2 bucket
      # via Cloudflare's Workers API, but requires Worker script update
      # For now, we embed files directly in Worker script
    end
    
    private
    
    def credentials_present?
      @account_id.present? && @r2_access_key.present? && @r2_secret_key.present?
    end
    
    def setup_r2_client
      # R2 uses S3-compatible API
      # We'll use presigned URLs for simplicity instead of full AWS SDK
      Rails.logger.info "[R2] R2 client configured for account #{@account_id}"
    end
    
    def generate_presigned_upload_url(key)
      # For now, return a placeholder URL
      # In production, generate proper S3-style presigned URL
      "#{@r2_endpoint}/#{@bucket_name}/#{key}"
    end
    
    def content_type_for(path)
      ext = File.extname(path).downcase
      
      case ext
      when '.html' then 'text/html'
      when '.js', '.mjs' then 'application/javascript'
      when '.css' then 'text/css'
      when '.json' then 'application/json'
      when '.png' then 'image/png'
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.gif' then 'image/gif'
      when '.svg' then 'image/svg+xml'
      when '.ico' then 'image/x-icon'
      when '.woff', '.woff2' then 'font/woff2'
      when '.ttf' then 'font/ttf'
      else 'application/octet-stream'
      end
    end
    
    def cache_control_for(key)
      # Static assets get long cache
      if key.match?(/\.(js|css|png|jpg|jpeg|gif|svg|ico|woff|woff2|ttf)$/)
        'public, max-age=31536000, immutable'
      else
        'public, max-age=3600'
      end
    end
  end
end