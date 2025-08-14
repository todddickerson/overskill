module Deployment
  class CloudflareWorkersDeployer
    include HTTParty
    base_uri 'https://api.cloudflare.com/client/v4'
    
    def initialize(app)
      @app = app
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @api_token = ENV['CLOUDFLARE_API_TOKEN']
      @zone_id = ENV['CLOUDFLARE_ZONE_ID']
      @base_domain = ENV['APP_BASE_DOMAIN'] || 'overskillproject.com'
      
      self.class.headers('Authorization' => "Bearer #{@api_token}")
    end
    
    def deploy_with_secrets(built_code:, deployment_type: :preview)
      worker_name = generate_worker_name(deployment_type)
      
      Rails.logger.info "[CloudflareWorkersDeployer] Deploying to #{worker_name}"
      
      # 1. Deploy the Worker script
      deploy_worker(worker_name, built_code)
      
      # 2. Set environment variables and secrets (skip if API token lacks permissions)
      begin
        set_worker_secrets(worker_name)
        Rails.logger.info "[CloudflareWorkersDeployer] Successfully set secrets for #{worker_name}"
      rescue => secrets_error
        Rails.logger.warn "[CloudflareWorkersDeployer] Could not set secrets (continuing deployment): #{secrets_error.message}"
        # Continue deployment even if secrets fail - worker can still serve static content
      end
      
      # 3. Configure routes based on deployment type
      worker_url = configure_worker_routes(worker_name, deployment_type)
      
      # 4. Handle custom domain if configured (check if custom_domain method exists)
      custom_url = if @app.respond_to?(:custom_domain) && @app.custom_domain.present? && deployment_type == :production
                     setup_custom_domain
                   else
                     nil
                   end
      
      {
        success: true,
        worker_name: worker_name,
        worker_url: worker_url,
        custom_url: custom_url,
        deployment_type: deployment_type,
        deployed_at: Time.current
      }
    rescue => e
      Rails.logger.error "[CloudflareWorkersDeployer] Deployment failed: #{e.message}"
      { success: false, error: e.message }
    end
    
    def update_secrets(worker_name = nil)
      worker_name ||= generate_worker_name(:production)
      set_worker_secrets(worker_name)
    end
    
    def update_worker_hot(hot_update_code)
      Rails.logger.info "[CloudflareWorkersDeployer] Deploying hot update for app ##{@app.id}"
      
      worker_name = generate_worker_name(:preview)
      
      # Deploy the hot update worker code
      response = self.class.put(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        headers: { 'Content-Type' => 'application/javascript' },
        body: hot_update_code
      )
      
      if response.success?
        Rails.logger.info "[CloudflareWorkersDeployer] Hot update deployed successfully"
        
        {
          success: true,
          worker_name: worker_name,
          deployment_type: :hot_update,
          deployed_at: Time.current
        }
      else
        Rails.logger.error "[CloudflareWorkersDeployer] Hot update deployment failed: #{response.body}"
        { success: false, error: response.body }
      end
    rescue => e
      Rails.logger.error "[CloudflareWorkersDeployer] Hot update deployment error: #{e.message}"
      { success: false, error: e.message }
    end
    
    private
    
    def generate_worker_name(deployment_type)
      # Different worker names for preview vs production
      case deployment_type
      when :preview
        "preview-app-#{@app.id}"
      when :production
        "app-#{@app.id}"
      else
        "app-#{@app.id}-#{deployment_type}"
      end
    end
    
    def deploy_worker(worker_name, script_content)
      Rails.logger.info "[CloudflareWorkersDeployer] Uploading Worker script (#{script_content.bytesize} bytes)"
      
      # Send JavaScript code directly for simple deployments
      response = self.class.put(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        body: script_content,
        headers: { 
          'Content-Type' => 'application/javascript'
        }
      )
      
      handle_api_response(response, "deploy worker #{worker_name}")
    end
    
    def delete_worker(worker_name)
      Rails.logger.info "[CloudflareWorkersDeployer] Deleting Worker: #{worker_name}"
      
      response = self.class.delete(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        headers: {}
      )
      
      handle_api_response(response, "delete worker #{worker_name}")
    end
    
    def build_worker_upload_body(script_content)
      # Build multipart body for Worker deployment
      {
        'metadata' => {
          'main_module' => 'index.js',
          'compatibility_date' => '2024-01-01',
          'compatibility_flags' => ['nodejs_compat']
        }.to_json,
        'index.js' => {
          content: script_content,
          type: 'application/javascript'
        }
      }
    end
    
    def set_worker_secrets(worker_name)
      Rails.logger.info "[CloudflareWorkersDeployer] Setting secrets for #{worker_name}"
      
      secrets = gather_all_secrets
      
      # Cloudflare API requires setting secrets one at a time or in batch
      # Using batch update for efficiency
      secrets_array = secrets.map do |key, value|
        { name: key, text: value.to_s, type: 'secret_text' }
      end
      
      response = self.class.patch(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}/secrets",
        body: secrets_array.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      handle_api_response(response, "set secrets for #{worker_name}")
    end
    
    def gather_all_secrets
      secrets = {}
      
      # Platform secrets (hidden from users)
      secrets['SUPABASE_URL'] = ENV['SUPABASE_URL']
      secrets['SUPABASE_SECRET_KEY'] = ENV['SUPABASE_SERVICE_KEY']
      secrets['SUPABASE_ANON_KEY'] = ENV['SUPABASE_ANON_KEY'] # Public key for client-side auth
      
      # System defaults
      secrets['APP_ID'] = @app.id.to_s
      secrets['OWNER_ID'] = @app.team.id.to_s
      secrets['ENVIRONMENT'] = Rails.env
      
      # User's custom environment variables (non-secret only)
      if @app.respond_to?(:app_env_vars)
        begin
          # Check if var_type column exists
          if @app.app_env_vars.column_names.include?('var_type')
            user_vars = @app.app_env_vars
              .where(var_type: ['user_defined', 'system_default'])
              .pluck(:key, :value)
              .to_h
          else
            # Fallback for when var_type doesn't exist yet
            user_vars = @app.app_env_vars
              .pluck(:key, :value)
              .to_h
          end
          
          secrets['CUSTOM_VARS'] = user_vars.to_json
        rescue => e
          Rails.logger.warn "[CloudflareWorkersDeployer] Could not load env vars: #{e.message}"
          secrets['CUSTOM_VARS'] = '{}'
        end
      else
        secrets['CUSTOM_VARS'] = '{}'
      end
      
      secrets
    end
    
    def configure_worker_routes(worker_name, deployment_type)
      # Configure subdomain based on deployment type
      subdomain = case deployment_type
                  when :preview
                    "preview-#{@app.id}"
                  when :production
                    "app-#{@app.id}"
                  else
                    "#{deployment_type}-#{@app.id}"
                  end
      
      # The worker URL pattern
      worker_url = "https://#{subdomain}.#{@base_domain}"
      
      # Create or update the route
      route_pattern = "#{subdomain}.#{@base_domain}/*"
      
      create_or_update_route(route_pattern, worker_name)
      
      worker_url
    end
    
    def create_or_update_route(pattern, worker_name)
      # Check if route exists
      existing_route = find_existing_route(pattern)
      
      if existing_route
        # Update existing route
        response = self.class.put(
          "/zones/#{@zone_id}/workers/routes/#{existing_route['id']}",
          body: {
            pattern: pattern,
            script: worker_name
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      else
        # Create new route
        response = self.class.post(
          "/zones/#{@zone_id}/workers/routes",
          body: {
            pattern: pattern,
            script: worker_name
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      end
      
      handle_api_response(response, "configure route #{pattern}")
    end
    
    def find_existing_route(pattern)
      response = self.class.get("/zones/#{@zone_id}/workers/routes")
      
      if response.success?
        routes = response.parsed_response['result'] || []
        routes.find { |r| r['pattern'] == pattern }
      else
        nil
      end
    end
    
    def setup_custom_domain
      return unless @app.custom_domain.present?
      
      Rails.logger.info "[CloudflareWorkersDeployer] Setting up custom domain: #{@app.custom_domain}"
      
      # This would integrate with Cloudflare for SaaS
      # For now, return the configured domain
      @app.custom_domain
    rescue => e
      Rails.logger.error "[CloudflareWorkersDeployer] Custom domain setup failed: #{e.message}"
      nil
    end
    
    def handle_api_response(response, operation)
      if response.success?
        result = response.parsed_response['result']
        Rails.logger.info "[CloudflareWorkersDeployer] Successfully #{operation}"
        result
      else
        errors = response.parsed_response['errors'] || []
        error_message = errors.map { |e| e['message'] }.join(', ')
        raise "Failed to #{operation}: #{error_message}"
      end
    end
  end
end