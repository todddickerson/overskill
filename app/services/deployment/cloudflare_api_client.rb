# frozen_string_literal: true

module Deployment
  class CloudflareApiClient
    include HTTParty

    base_uri "https://api.cloudflare.com/client/v4"

    # Cloudflare API endpoints
    WORKERS_ENDPOINT = "/accounts/%s/workers/scripts/%s"
    R2_ENDPOINT = "/accounts/%s/r2/buckets/%s/objects/%s"
    ROUTES_ENDPOINT = "/zones/%s/workers/routes"
    SECRETS_ENDPOINT = "/accounts/%s/workers/scripts/%s/secrets"
    DOMAINS_ENDPOINT = "/zones/%s/workers/routes"

    class DeploymentError < StandardError; end

    class WorkerDeploymentError < DeploymentError; end

    class R2UploadError < DeploymentError; end

    class SecretsManagementError < DeploymentError; end

    class RoutingError < DeploymentError; end

    def initialize(app)
      @app = app
      @account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
      @zone_id = ENV["CLOUDFLARE_ZONE_ID"]
      @api_token = ENV["CLOUDFLARE_API_TOKEN"]
      @api_key = ENV["CLOUDFLARE_API_KEY"]
      @email = ENV["CLOUDFLARE_EMAIL"]
      @bucket_name = ENV["CLOUDFLARE_R2_BUCKET"] || "overskill-apps"
      @base_domain = ENV["APP_BASE_DOMAIN"] || "overskillproject.com"

      Rails.logger.info "[CloudflareApiClient] Initializing for app ##{@app.id}"

      # Validate required credentials
      validate_credentials!

      setup_http_headers
    end

    def deploy_complete_application(build_result)
      Rails.logger.info "[CloudflareApiClient] Starting complete deployment for app ##{@app.id}"

      deployment_result = {
        worker_deployed: false,
        r2_assets: [],
        secrets_configured: false,
        routes_configured: false,
        deployment_urls: {}
      }

      begin
        # 1. Deploy Cloudflare Worker
        worker_result = deploy_worker(build_result)
        deployment_result[:worker_deployed] = worker_result[:success]

        # 2. Upload R2 assets (if any)
        if build_result[:r2_assets]&.any?
          r2_result = upload_r2_assets(build_result[:r2_assets])
          deployment_result[:r2_assets] = r2_result[:uploaded_files]
        end

        # 3. Configure secrets (environment variables)
        secrets_result = configure_worker_secrets
        deployment_result[:secrets_configured] = secrets_result[:success]

        # 4. Setup routing (custom domains)
        routes_result = configure_worker_routes
        deployment_result[:routes_configured] = routes_result[:success]
        deployment_result[:deployment_urls] = routes_result[:urls]

        # 5. Finalize deployment
        finalize_deployment(deployment_result)

        Rails.logger.info "[CloudflareApiClient] Complete deployment successful for app ##{@app.id}"
        deployment_result.merge(success: true)
      rescue => e
        Rails.logger.error "[CloudflareApiClient] Deployment failed: #{e.message}"
        deployment_result.merge(success: false, error: e.message)
      end
    end

    def deploy_worker(build_result)
      Rails.logger.info "[CloudflareApiClient] Deploying worker for app ##{@app.id}"

      worker_name = generate_worker_name
      worker_script = build_result[:worker_script]

      # Validate worker script
      validate_worker_script(worker_script)

      # Deploy via PUT request
      response = self.class.put(
        WORKERS_ENDPOINT % [@account_id, worker_name],
        body: worker_script,
        headers: {
          "Content-Type" => "application/javascript",
          "X-Auth-Email" => ENV["CLOUDFLARE_EMAIL"]
        }
      )

      handle_api_response(response, "Worker deployment failed") do |data|
        Rails.logger.info "[CloudflareApiClient] Worker deployed successfully: #{worker_name}"

        # Store worker metadata
        store_worker_metadata(worker_name, build_result)

        {
          success: true,
          worker_name: worker_name,
          worker_url: "https://#{worker_name}.#{@account_id}.workers.dev",
          size: worker_script.bytesize,
          deployment_id: data["id"]
        }
      end
    rescue => e
      Rails.logger.error "[CloudflareApiClient] Worker deployment error: #{e.message}"
      raise WorkerDeploymentError, "Failed to deploy worker: #{e.message}"
    end

    def upload_r2_assets(r2_assets)
      Rails.logger.info "[CloudflareApiClient] Uploading #{r2_assets.size} R2 assets for app ##{@app.id}"

      uploaded_files = []
      failed_files = []

      r2_assets.each do |path, asset|
        upload_result = upload_single_r2_asset(path, asset)
        uploaded_files << upload_result

        Rails.logger.debug "[CloudflareApiClient] Uploaded R2 asset: #{path} (#{asset[:size]} bytes)"
      rescue => e
        Rails.logger.error "[CloudflareApiClient] Failed to upload R2 asset #{path}: #{e.message}"
        failed_files << {path: path, error: e.message}
      end

      if failed_files.any?
        Rails.logger.warn "[CloudflareApiClient] #{failed_files.size} R2 uploads failed"
      end

      {
        success: failed_files.empty?,
        uploaded_files: uploaded_files,
        failed_files: failed_files,
        total_size: uploaded_files.sum { |f| f[:size] }
      }
    rescue => e
      Rails.logger.error "[CloudflareApiClient] R2 upload error: #{e.message}"
      raise R2UploadError, "Failed to upload R2 assets: #{e.message}"
    end

    def configure_worker_secrets
      Rails.logger.info "[CloudflareApiClient] Configuring worker secrets for app ##{@app.id}"

      worker_name = generate_worker_name
      secrets = prepare_worker_secrets
      configured_secrets = []

      secrets.each do |key, value|
        set_worker_secret(worker_name, key, value)
        configured_secrets << key
        Rails.logger.debug "[CloudflareApiClient] Set worker secret: #{key}"
      rescue => e
        Rails.logger.error "[CloudflareApiClient] Failed to set secret #{key}: #{e.message}"
        raise SecretsManagementError, "Failed to configure secret #{key}: #{e.message}"
      end

      {
        success: true,
        configured_secrets: configured_secrets,
        secrets_count: configured_secrets.size
      }
    rescue => e
      Rails.logger.error "[CloudflareApiClient] Secrets configuration error: #{e.message}"
      raise SecretsManagementError, "Failed to configure worker secrets: #{e.message}"
    end

    def configure_worker_routes
      Rails.logger.info "[CloudflareApiClient] Configuring worker routes for app ##{@app.id}"

      worker_name = generate_worker_name
      routes = prepare_worker_routes
      configured_routes = []

      routes.each do |route_config|
        route_result = create_worker_route(route_config, worker_name)
        configured_routes << route_result
        Rails.logger.info "[CloudflareApiClient] Configured route: #{route_config[:pattern]}"
      rescue => e
        Rails.logger.error "[CloudflareApiClient] Failed to configure route #{route_config[:pattern]}: #{e.message}"
        # Continue with other routes - routing is not critical for basic functionality
      end

      deployment_urls = generate_deployment_urls(configured_routes)

      {
        success: true,
        configured_routes: configured_routes,
        urls: deployment_urls
      }
    rescue => e
      Rails.logger.error "[CloudflareApiClient] Route configuration error: #{e.message}"
      # Don't fail deployment for routing issues
      {
        success: false,
        error: e.message,
        urls: {worker_url: "https://#{generate_worker_name}.#{@account_id}.workers.dev"}
      }
    end

    private

    def setup_http_headers
      # Prefer API Token authentication (tokens typically have underscores and are 40+ chars)
      if @api_token.present? && (@api_token.include?("_") || @api_token.length > 30)
        Rails.logger.info "[CloudflareApiClient] Using API Token authentication"
        self.class.headers({
          "Authorization" => "Bearer #{@api_token}",
          "Content-Type" => "application/json"
        })
      elsif @api_key.present? && @email.present?
        # Use Global API Key with email
        Rails.logger.info "[CloudflareApiClient] Using Global API Key authentication"
        self.class.headers({
          "X-Auth-Email" => @email,
          "X-Auth-Key" => @api_key,
          "Content-Type" => "application/json"
        })
      else
        Rails.logger.error "[CloudflareApiClient] No valid authentication credentials found"
      end
    end

    def generate_worker_name
      # Generate consistent worker name for the app
      @worker_name ||= "overskill-app-#{@app.id}"
    end

    def validate_worker_script(script)
      if script.blank?
        raise WorkerDeploymentError, "Worker script is empty"
      end

      if script.bytesize > 1.megabyte
        size_mb = (script.bytesize / 1.megabyte.to_f).round(2)
        raise WorkerDeploymentError, "Worker script size #{size_mb}MB exceeds 1MB limit"
      end

      # Basic syntax validation
      unless script.include?("export default")
        raise WorkerDeploymentError, "Worker script missing ES6 module export"
      end
    end

    def upload_single_r2_asset(path, asset)
      object_key = "apps/#{@app.id}/#{path.gsub(/^\//, "")}"
      content = asset[:content] || asset["content"]

      response = self.class.put(
        "https://api.cloudflare.com/client/v4/accounts/#{@account_id}/r2/buckets/#{@bucket_name}/objects/#{object_key}",
        body: content,
        headers: {
          "Authorization" => "Bearer #{@api_token}",
          "Content-Type" => determine_content_type(path),
          "Content-Length" => content.bytesize.to_s
        }
      )

      handle_api_response(response, "R2 upload failed for #{path}") do |data|
        {
          path: path,
          object_key: object_key,
          size: content.bytesize,
          cdn_url: asset[:cdn_url] || "https://cdn.#{@base_domain}/#{object_key}",
          etag: data["etag"]
        }
      end
    end

    def prepare_worker_secrets
      secrets = {}

      # System secrets (always required)
      secrets["SUPABASE_URL"] = ENV["SUPABASE_URL"]
      secrets["SUPABASE_SERVICE_KEY"] = ENV["SUPABASE_SERVICE_KEY"]
      secrets["APP_ID"] = @app.id.to_s
      secrets["ENVIRONMENT"] = Rails.env

      # App-specific environment variables
      @app.app_env_vars.each do |env_var|
        if env_var.is_secret?
          secrets[env_var.key] = env_var.value
        end
      end

      Rails.logger.info "[CloudflareApiClient] Prepared #{secrets.size} worker secrets"
      secrets
    end

    def set_worker_secret(worker_name, key, value)
      response = self.class.put(
        SECRETS_ENDPOINT % [@account_id, worker_name],
        body: {
          name: key,
          text: value,
          type: "secret_text"
        }.to_json
      )

      handle_api_response(response, "Failed to set secret #{key}")
    end

    def prepare_worker_routes
      routes = []

      # Development/preview route
      if @app.preview_url.present?
        domain = URI.parse(@app.preview_url).host
        routes << {
          pattern: "#{domain}/*",
          zone: @zone_id,
          type: "preview"
        }
      end

      # Production route
      if @app.production_url.present?
        domain = URI.parse(@app.production_url).host
        routes << {
          pattern: "#{domain}/*",
          zone: @zone_id,
          type: "production"
        }
      end

      # Fallback routes for app
      routes << {
        pattern: "preview-#{@app.obfuscated_id.downcase}.#{@base_domain}/*",
        zone: @zone_id,
        type: "preview"
      }

      routes << {
        pattern: "app-#{@app.obfuscated_id.downcase}.#{@base_domain}/*",
        zone: @zone_id,
        type: "production"
      }

      routes
    end

    def create_worker_route(route_config, worker_name)
      response = self.class.post(
        ROUTES_ENDPOINT % [route_config[:zone]],
        body: {
          pattern: route_config[:pattern],
          script: worker_name,
          zone: {
            id: route_config[:zone]
          }
        }.to_json
      )

      handle_api_response(response, "Failed to create route #{route_config[:pattern]}") do |data|
        {
          pattern: route_config[:pattern],
          type: route_config[:type],
          route_id: data["id"],
          worker_name: worker_name
        }
      end
    end

    def generate_deployment_urls(configured_routes)
      urls = {}

      configured_routes.each do |route|
        url = "https://#{route[:pattern].gsub("/*", "")}"

        case route[:type]
        when "preview"
          urls[:preview_url] = url
        when "production"
          urls[:production_url] = url
        end
      end

      # Fallback to worker URL if no custom routes
      if urls.empty?
        urls[:worker_url] = "https://#{generate_worker_name}.#{@account_id}.workers.dev"
      end

      urls
    end

    def store_worker_metadata(worker_name, build_result)
      metadata = {
        worker_name: worker_name,
        deployment_time: Time.current.iso8601,
        build_mode: build_result[:mode],
        worker_size: build_result[:worker_size],
        r2_assets_count: build_result[:r2_assets]&.size || 0,
        cloudflare_account: @account_id
      }

      # Store in app metadata or cache for reference
      Rails.cache.write("app_#{@app.id}_worker_metadata", metadata, expires_in: 30.days)
    end

    def finalize_deployment(deployment_result)
      # Update app with deployment information
      updates = {}

      if deployment_result[:deployment_urls][:preview_url]
        updates[:preview_url] = deployment_result[:deployment_urls][:preview_url]
      end

      if deployment_result[:deployment_urls][:production_url]
        updates[:production_url] = deployment_result[:deployment_urls][:production_url]
      end

      if deployment_result[:worker_deployed]
        updates[:status] = "deployed"
        updates[:deployed_at] = Time.current
      end

      @app.update!(updates) if updates.any?

      Rails.logger.info "[CloudflareApiClient] Deployment finalized with URLs: #{deployment_result[:deployment_urls]}"
    end

    def determine_content_type(path)
      case File.extname(path).downcase
      when ".js" then "application/javascript"
      when ".css" then "text/css"
      when ".html" then "text/html"
      when ".json" then "application/json"
      when ".png" then "image/png"
      when ".jpg", ".jpeg" then "image/jpeg"
      when ".svg" then "image/svg+xml"
      when ".woff2" then "font/woff2"
      when ".woff" then "font/woff"
      else "application/octet-stream"
      end
    end

    def handle_api_response(response, error_message)
      unless response.success?
        error_data = begin
          JSON.parse(response.body)
        rescue
          {}
        end
        error_details = error_data.dig("errors", 0, "message") || response.message

        Rails.logger.error "[CloudflareApiClient] API Error: #{error_details}"
        raise DeploymentError, "#{error_message}: #{error_details}"
      end

      result_data = JSON.parse(response.body)

      if block_given?
        yield result_data.dig("result")
      else
        result_data.dig("result")
      end
    rescue JSON::ParserError => e
      Rails.logger.error "[CloudflareApiClient] Invalid JSON response: #{e.message}"
      raise DeploymentError, "#{error_message}: Invalid API response"
    end

    def validate_credentials!
      missing_credentials = []

      missing_credentials << "CLOUDFLARE_ACCOUNT_ID" if @account_id.blank?
      missing_credentials << "CLOUDFLARE_ZONE_ID" if @zone_id.blank?

      # Need either API Token or API Key+Email
      if @api_token.blank? && @api_key.blank?
        missing_credentials << "CLOUDFLARE_API_TOKEN or CLOUDFLARE_API_KEY"
      end
      if (@api_key.present? || @api_token.present?) && @email.blank?
        missing_credentials << "CLOUDFLARE_EMAIL"
      end
      missing_credentials << "SUPABASE_URL" if ENV["SUPABASE_URL"].blank?
      missing_credentials << "SUPABASE_SERVICE_KEY" if ENV["SUPABASE_SERVICE_KEY"].blank?

      if missing_credentials.any?
        error_msg = "Missing required Cloudflare credentials: #{missing_credentials.join(", ")}"
        Rails.logger.error "[CloudflareApiClient] #{error_msg}"
        raise DeploymentError, error_msg
      end

      Rails.logger.info "[CloudflareApiClient] All required credentials validated"
    end
  end
end
