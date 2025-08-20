# frozen_string_literal: true

module Storage
  class R2FileStorageService
    include HTTParty

    base_uri 'https://api.cloudflare.com/client/v4'

    class R2StorageError < StandardError; end
    class R2UploadError < R2StorageError; end
    class R2DownloadError < R2StorageError; end
    class R2DeleteError < R2StorageError; end

    def initialize(bucket_name = nil)
      @bucket_name = bucket_name || ENV['CLOUDFLARE_R2_BUCKET_DB_FILES'] || 'overskill-dev'
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @api_token = ENV['CLOUDFLARE_API_TOKEN']
      @base_domain = ENV['APP_BASE_DOMAIN'] || 'overskillproject.com'
      
      validate_configuration!
      setup_http_headers
      
      Rails.logger.debug "[R2FileStorageService] Initialized with bucket: #{@bucket_name}"
    end

    # Store file content with automatic key generation
    def store_file_content(app_id, file_path, content)
      object_key = generate_file_key(app_id, file_path)
      
      Rails.logger.debug "[R2FileStorageService] Storing file: #{file_path} -> #{object_key}"
      
      result = upload_to_r2(object_key, content)
      
      {
        success: true,
        object_key: object_key,
        size: content.bytesize,
        checksum: Digest::SHA256.hexdigest(content),
        cdn_url: result[:cdn_url]
      }
    rescue => e
      Rails.logger.error "[R2FileStorageService] Failed to store file #{file_path}: #{e.message}"
      raise R2UploadError, "Failed to store file content: #{e.message}"
    end

    # Store version-specific file content
    def store_version_file_content(app_id, version_id, file_path, content)
      object_key = generate_version_file_key(app_id, version_id, file_path)
      
      Rails.logger.debug "[R2FileStorageService] Storing version file: v#{version_id}/#{file_path} -> #{object_key}"
      
      result = upload_to_r2(object_key, content)
      
      {
        success: true,
        object_key: object_key,
        size: content.bytesize,
        checksum: Digest::SHA256.hexdigest(content),
        cdn_url: result[:cdn_url]
      }
    rescue => e
      Rails.logger.error "[R2FileStorageService] Failed to store version file #{file_path}: #{e.message}"
      raise R2UploadError, "Failed to store version file content: #{e.message}"
    end

    # Store complete version snapshot
    def store_version_snapshot(app_id, version_id, files_hash)
      object_key = "apps/#{app_id}/snapshots/v#{version_id}/snapshot.json"
      content = JSON.pretty_generate(files_hash)
      
      Rails.logger.debug "[R2FileStorageService] Storing version snapshot: #{object_key}"
      
      result = upload_to_r2(object_key, content)
      
      {
        success: true,
        object_key: object_key,
        size: content.bytesize,
        checksum: Digest::SHA256.hexdigest(content),
        cdn_url: result[:cdn_url]
      }
    rescue => e
      Rails.logger.error "[R2FileStorageService] Failed to store snapshot for version #{version_id}: #{e.message}"
      raise R2UploadError, "Failed to store version snapshot: #{e.message}"
    end

    # Retrieve file content with caching
    def retrieve_file_content(object_key)
      Rails.logger.debug "[R2FileStorageService] Retrieving file: #{object_key}"
      
      # Use Rails cache with expiration
      cache_key = "r2_file_#{object_key.gsub('/', '_')}"
      
      Rails.cache.fetch(cache_key, expires_in: 30.minutes, race_condition_ttl: 30.seconds) do
        download_from_r2(object_key)
      end
    rescue => e
      Rails.logger.error "[R2FileStorageService] Failed to retrieve file #{object_key}: #{e.message}"
      raise R2DownloadError, "Failed to retrieve file content: #{e.message}"
    end

    # Delete file from R2
    def delete_file(object_key)
      Rails.logger.debug "[R2FileStorageService] Deleting file: #{object_key}"
      
      response = self.class.delete(
        "/accounts/#{@account_id}/r2/buckets/#{@bucket_name}/objects/#{object_key}"
      )

      handle_api_response(response, "Failed to delete #{object_key}") do
        Rails.cache.delete("r2_file_#{object_key.gsub('/', '_')}")
        { success: true, object_key: object_key }
      end
    rescue => e
      Rails.logger.error "[R2FileStorageService] Failed to delete file #{object_key}: #{e.message}"
      raise R2DeleteError, "Failed to delete file: #{e.message}"
    end

    # Bulk operations for efficiency
    def store_multiple_files(app_id, file_contents_hash)
      results = []
      
      file_contents_hash.each do |file_path, content|
        begin
          result = store_file_content(app_id, file_path, content)
          results << result.merge(file_path: file_path)
        rescue => e
          Rails.logger.error "[R2FileStorageService] Failed to store #{file_path}: #{e.message}"
          results << { file_path: file_path, success: false, error: e.message }
        end
      end
      
      {
        total_files: file_contents_hash.size,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        results: results
      }
    end

    # Analytics and monitoring
    def get_storage_stats(app_id)
      # This would require list operations - implement if needed
      # For now, rely on database tracking
      {
        message: "Storage stats tracked in database for performance"
      }
    end

    private

    def setup_http_headers
      self.class.headers({
        'Authorization' => "Bearer #{@api_token}",
        'Content-Type' => 'application/octet-stream' # Will be overridden per request
      })
    end

    def validate_configuration!
      missing = []
      missing << 'CLOUDFLARE_ACCOUNT_ID' if @account_id.blank?
      missing << 'CLOUDFLARE_API_TOKEN' if @api_token.blank?
      missing << 'CLOUDFLARE_R2_BUCKET_DB_FILES' if @bucket_name.blank?
      
      if missing.any?
        error_msg = "Missing required R2 configuration: #{missing.join(', ')}"
        Rails.logger.error "[R2FileStorageService] #{error_msg}"
        raise R2StorageError, error_msg
      end
    end

    def generate_file_key(app_id, file_path)
      # Clean file path and ensure no leading slash
      clean_path = file_path.gsub(/^\//, '')
      "apps/#{app_id}/files/#{clean_path}"
    end

    def generate_version_file_key(app_id, version_id, file_path)
      clean_path = file_path.gsub(/^\//, '')
      "apps/#{app_id}/versions/#{version_id}/#{clean_path}"
    end

    def upload_to_r2(object_key, content)
      content_type = determine_content_type_from_key(object_key)
      
      response = self.class.put(
        "/accounts/#{@account_id}/r2/buckets/#{@bucket_name}/objects/#{object_key}",
        body: content,
        headers: {
          'Authorization' => "Bearer #{@api_token}",
          'Content-Type' => content_type,
          'Content-Length' => content.bytesize.to_s
        }
      )

      handle_api_response(response, "Upload failed for #{object_key}") do |data|
        {
          object_key: object_key,
          size: content.bytesize,
          content_type: content_type,
          cdn_url: generate_cdn_url(object_key),
          etag: data['etag']
        }
      end
    end

    def download_from_r2(object_key)
      response = self.class.get(
        "/accounts/#{@account_id}/r2/buckets/#{@bucket_name}/objects/#{object_key}",
        headers: {
          'Authorization' => "Bearer #{@api_token}"
        }
      )

      if response.success?
        response.body
      else
        error_data = JSON.parse(response.body) rescue {}
        error_message = error_data.dig('errors', 0, 'message') || 'Download failed'
        raise R2DownloadError, "Failed to download #{object_key}: #{error_message}"
      end
    end

    def determine_content_type_from_key(object_key)
      case File.extname(object_key).downcase
      when '.js', '.jsx' then 'application/javascript'
      when '.ts', '.tsx' then 'application/typescript'
      when '.css' then 'text/css'
      when '.html' then 'text/html'
      when '.json' then 'application/json'
      when '.md' then 'text/markdown'
      when '.txt' then 'text/plain'
      when '.png' then 'image/png'
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.svg' then 'image/svg+xml'
      when '.woff2' then 'font/woff2'
      when '.woff' then 'font/woff'
      else 'application/octet-stream'
      end
    end

    def generate_cdn_url(object_key)
      # If CDN is configured, use that domain
      if ENV['CLOUDFLARE_R2_CDN_DOMAIN'].present?
        "https://#{ENV['CLOUDFLARE_R2_CDN_DOMAIN']}/#{object_key}"
      else
        # Fallback to R2 public URL (if public access is configured)
        "https://#{@bucket_name}.#{@account_id}.r2.cloudflarestorage.com/#{object_key}"
      end
    end

    def handle_api_response(response, error_message)
      unless response.success?
        error_data = JSON.parse(response.body) rescue {}
        error_details = error_data.dig('errors', 0, 'message') || response.message
        
        Rails.logger.error "[R2FileStorageService] API Error: #{error_details}"
        raise R2StorageError, "#{error_message}: #{error_details}"
      end

      result_data = JSON.parse(response.body) rescue {}
      
      if block_given?
        yield result_data.dig('result') || {}
      else
        result_data.dig('result') || {}
      end
    end
  end
end