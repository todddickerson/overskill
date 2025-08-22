module Deployment
  class CloudflareWorkersDeployer
    include HTTParty
    base_uri 'https://api.cloudflare.com/client/v4'
    
    def initialize(app)
      @app = app
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @api_token = ENV['CLOUDFLARE_API_TOKEN']
      @api_key = ENV['CLOUDFLARE_API_KEY']
      @email = ENV['CLOUDFLARE_EMAIL']
      @zone_id = ENV['CLOUDFLARE_ZONE_ID']
      @base_domain = ENV['APP_BASE_DOMAIN'] || 'overskillproject.com'
      
      # Prefer API Token if it looks valid (contains underscore and is proper length)
      # API tokens are typically 40+ chars with underscores, not dashes
      if @api_token.present? && (@api_token.include?('_') || @api_token.length > 30)
        Rails.logger.info "[CloudflareWorkersDeployer] Using API Token authentication"
        self.class.headers('Authorization' => "Bearer #{@api_token}")
      elsif @api_key.present? && @email.present?
        Rails.logger.info "[CloudflareWorkersDeployer] Using Global API Key authentication"
        self.class.headers({
          'X-Auth-Email' => @email,
          'X-Auth-Key' => @api_key
        })
      else
        Rails.logger.error "[CloudflareWorkersDeployer] No valid Cloudflare authentication found"
      end
    end
    
    def deploy_with_secrets(built_code:, deployment_type: :preview, r2_asset_urls: {}, worker_name_override: nil)
      worker_name = worker_name_override || generate_worker_name(deployment_type)
      
      Rails.logger.info "[CloudflareWorkersDeployer] Deploying to #{worker_name}"
      
      # Generate Worker script from built code and R2 URLs
      worker_script = generate_worker_script(built_code, r2_asset_urls)
      worker_size_mb = (worker_script.bytesize / 1024.0 / 1024.0).round(2)
      
      Rails.logger.info "[CloudflareWorkersDeployer] Worker script size: #{worker_size_mb} MB"
      
      if worker_script.bytesize > 10 * 1024 * 1024  # 10MB limit
        return { success: false, error: "Worker script too large: #{worker_size_mb} MB" }
      end
      
      # 1. Deploy the Worker script with environment variables included
      deploy_worker(worker_name, worker_script)
      
      # 2. Configure routes based on deployment type
      worker_url = configure_worker_routes(worker_name, deployment_type)
      
      # 3. Handle custom domain if configured (check if custom_domain method exists)
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
    
    # Clear Cloudflare cache for a worker (non-blocking - deployment continues even if cache clear fails)
    def clear_cache(deployment_type = :preview)
      unless ENV['CLOUDFLARE_ZONE_ID'].present?
        Rails.logger.warn "[CloudflareWorkersDeployer] Zone ID not configured - skipping cache clear"
        return { success: true, message: "Cache clear skipped - no zone ID configured" }
      end
      
      worker_name = generate_worker_name(deployment_type)
      zone_id = ENV['CLOUDFLARE_ZONE_ID']
      
      Rails.logger.info "[CloudflareWorkersDeployer] Clearing cache for #{worker_name}"
      
      # Get the hostname for this deployment
      hostname = case deployment_type
      when :preview
        "preview-#{@app.obfuscated_id.downcase}.overskillproject.com"
      when :production
        "app-#{@app.obfuscated_id.downcase}.overskillproject.com"
      else
        "#{worker_name}.overskillproject.com"
      end
      
      # Try cache clear but don't fail deployment if it doesn't work
      begin
        # Use purge_everything for broader compatibility (requires different permissions)
        response = self.class.post(
          "/zones/#{zone_id}/purge_cache",
          body: { purge_everything: true }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        
        if response.success?
          Rails.logger.info "[CloudflareWorkersDeployer] Cache cleared successfully for #{hostname}"
          { success: true, message: "Cache cleared for #{hostname}" }
        else
          error_msg = response['errors']&.first&.dig('message') || 'Unknown error'
          Rails.logger.warn "[CloudflareWorkersDeployer] Cache clear failed (non-blocking): #{error_msg}"
          # Return success anyway - cache clear is non-critical
          { success: true, message: "Deployment succeeded, cache clear failed (#{error_msg})" }
        end
      rescue => e
        Rails.logger.warn "[CloudflareWorkersDeployer] Cache clear failed (non-blocking): #{e.message}"
        # Return success anyway - cache clear is non-critical  
        { success: true, message: "Deployment succeeded, cache clear failed (#{e.message})" }
      end
    end
    
    private
    
    def generate_worker_name(deployment_type)
      # Different worker names for preview vs production
      case deployment_type
      when :preview
        "preview-app-#{@app.obfuscated_id.downcase}"
      when :production
        "app-#{@app.obfuscated_id.downcase}"
      else
        "app-#{@app.obfuscated_id.downcase}-#{deployment_type}"
      end
    end
    
    def deploy_worker(worker_name, script_content)
      Rails.logger.info "[CloudflareWorkersDeployer] Uploading Worker script with environment variables (#{script_content.bytesize} bytes)"
      
      # Get all secrets/env vars for this worker
      secrets = gather_all_secrets
      
      # Build bindings for environment variables
      bindings = secrets.map do |key, value|
        {
          name: key,
          text: value.to_s,
          type: 'plain_text'
        }
      end
      
      # Create metadata with bindings
      metadata = {
        main_module: 'worker.js',
        compatibility_date: '2024-01-01',
        compatibility_flags: ['nodejs_compat'],
        bindings: bindings
      }
      
      # Use multipart form data as required by Cloudflare API
      boundary = "----WebKitFormBoundary#{SecureRandom.hex(16)}"
      
      # Build multipart body
      body_parts = []
      
      # Add metadata
      body_parts << "--#{boundary}\r\n"
      body_parts << "Content-Disposition: form-data; name=\"metadata\"\r\n\r\n"
      body_parts << metadata.to_json
      body_parts << "\r\n"
      
      # Add worker script (name must match main_module in metadata)
      body_parts << "--#{boundary}\r\n"
      body_parts << "Content-Disposition: form-data; name=\"worker.js\"; filename=\"worker.js\"\r\n"
      body_parts << "Content-Type: application/javascript+module\r\n\r\n"
      body_parts << script_content
      body_parts << "\r\n"
      
      # Close boundary
      body_parts << "--#{boundary}--\r\n"
      
      multipart_body = body_parts.join('')
      
      Rails.logger.info "[CloudflareWorkersDeployer] Deploying worker with #{bindings.count} environment variables"
      bindings.each { |binding| Rails.logger.debug "  #{binding[:name]}: #{binding[:text][0..20]}..." }
      
      response = self.class.put(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        body: multipart_body,
        headers: { 
          'Content-Type' => "multipart/form-data; boundary=#{boundary}"
        }
      )
      
      handle_api_response(response, "deploy worker #{worker_name} with environment variables")
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
      
      # Cloudflare API requires setting secrets individually via PUT
      # The endpoint is /workers/scripts/{script_name}/secrets/{secret_name}
      secrets.each do |key, value|
        begin
          response = self.class.put(
            "/accounts/#{@account_id}/workers/scripts/#{worker_name}/secrets/#{key}",
            body: {
              text: value.to_s,
              type: 'secret_text'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
          
          if response.success?
            Rails.logger.debug "[CloudflareWorkersDeployer] Set secret #{key} for #{worker_name}"
          else
            Rails.logger.warn "[CloudflareWorkersDeployer] Failed to set secret #{key}: #{response.body}"
          end
        rescue => e
          Rails.logger.error "[CloudflareWorkersDeployer] Error setting secret #{key}: #{e.message}"
        end
      end
      
      Rails.logger.info "[CloudflareWorkersDeployer] Finished setting #{secrets.count} secrets for #{worker_name}"
    end
    
    def generate_worker_script(built_code, r2_asset_urls = {})
      # Handle both string (legacy) and hash (new) formats
      if built_code.is_a?(String)
        return built_code  # Already a Worker script
      end
      
      # Ensure all file contents are properly escaped for JavaScript
      # This prevents issues with apostrophes, quotes, and other special characters
      sanitized_built_code = built_code.transform_values do |content|
        # Ensure content is a string and properly escape any problematic characters
        content.to_s
      end
      
      # Generate Worker script from file hash with proper JSON escaping
      code_files_json = JSON.generate(sanitized_built_code)
      asset_urls_json = JSON.generate(r2_asset_urls)
      
      <<~JAVASCRIPT
        // Code files embedded in Worker
        const CODE_FILES = #{code_files_json};
        
        // Asset URLs in R2
        const ASSET_URLS = #{asset_urls_json};
        
        // ES Module export for Cloudflare Workers
        export default {
          async fetch(request, env, ctx) {
            return handleRequest(request, { env, ctx });
          }
        };
        
        async function handleRequest(request, event) {
          const env = event.env || {}
            const url = new URL(request.url);
            const pathname = url.pathname;
            
            // Handle API routes
            if (pathname.startsWith('/api/')) {
              return handleApiRequest(request, env);
            }
            
            // Clean path for lookups
            const cleanPath = pathname === '/' ? 'index.html' : pathname.slice(1);
            
            // Check if this is an asset in R2
            if (ASSET_URLS[cleanPath]) {
              return Response.redirect(ASSET_URLS[cleanPath], 301);
            }
            
            // Check if this is a code file
            if (CODE_FILES[cleanPath]) {
              const content = CODE_FILES[cleanPath];
              const contentType = getContentType(cleanPath);
              
              // Special handling for index.html
              if (cleanPath === 'index.html') {
                const publicEnvVars = getPublicEnvVars(env);
                const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`;
                
                let modifiedHtml = content;
                if (content.includes('</head>')) {
                  modifiedHtml = content.replace('</head>', envScript + '</head>');
                } else {
                  modifiedHtml = envScript + content;
                }
                
                return new Response(modifiedHtml, {
                  headers: {
                    'Content-Type': contentType,
                    'Cache-Control': 'no-cache',
                    'X-Frame-Options': 'ALLOWALL'
                  }
                });
              }
              
              // Serve other code files
              return new Response(content, {
                headers: {
                  'Content-Type': contentType,
                  'Cache-Control': 'public, max-age=86400',
                  'Access-Control-Allow-Origin': '*'
                }
              });
            }
            
            // For all other routes, serve index.html (SPA routing)
            const indexHtml = CODE_FILES['index.html'];
            if (indexHtml) {
              const publicEnvVars = getPublicEnvVars(env);
              const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`;
              
              let modifiedHtml = indexHtml;
              if (indexHtml.includes('</head>')) {
                modifiedHtml = indexHtml.replace('</head>', envScript + '</head>');
              } else {
                modifiedHtml = envScript + indexHtml;
              }
              
              return new Response(modifiedHtml, {
                headers: {
                  'Content-Type': 'text/html',
                  'Cache-Control': 'no-cache',
                  'X-Frame-Options': 'ALLOWALL'
                }
              });
            }
            
            return new Response('Not found', { status: 404 });
        }
        
        function getContentType(path) {
          const ext = path.split('.').pop().toLowerCase();
          const types = {
            'html': 'text/html',
            'js': 'application/javascript',
            'mjs': 'application/javascript',
            'css': 'text/css',
            'json': 'application/json'
          };
          return types[ext] || 'text/plain';
        }
        
        function getPublicEnvVars(env) {
          const publicVars = {};
          const publicKeys = ['APP_ID', 'ENVIRONMENT', 'API_BASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY'];
          
          for (const key in env) {
            if (publicKeys.includes(key) || key.startsWith('PUBLIC_') || key.startsWith('VITE_')) {
              publicVars[key] = env[key];
            }
          }
          
          return publicVars;
        }
        
        async function handleApiRequest(request, env) {
          const url = new URL(request.url);
          const path = url.pathname;
          
          // Proxy to Supabase
          if (path.startsWith('/api/supabase')) {
            const supabaseUrl = env.SUPABASE_URL;
            const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY;
            
            if (!supabaseUrl || !supabaseKey) {
              return new Response(JSON.stringify({ error: 'Database not configured' }), {
                status: 503,
                headers: { 'Content-Type': 'application/json' }
              });
            }
            
            const targetUrl = supabaseUrl + path.replace('/api/supabase', '');
            const proxyRequest = new Request(targetUrl, request);
            proxyRequest.headers.set('apikey', supabaseKey);
            proxyRequest.headers.set('Authorization', `Bearer ${supabaseKey}`);
            
            return fetch(proxyRequest);
          }
          
          return new Response(JSON.stringify({ error: 'API endpoint not found' }), {
            status: 404,
            headers: { 'Content-Type': 'application/json' }
          });
        }
      JAVASCRIPT
    end
    
    def gather_all_secrets
      secrets = {}
      
      # Platform secrets (hidden from users)
      secrets['SUPABASE_URL'] = ENV['SUPABASE_URL']
      secrets['SUPABASE_SECRET_KEY'] = ENV['SUPABASE_SERVICE_KEY']
      secrets['SUPABASE_ANON_KEY'] = ENV['SUPABASE_ANON_KEY'] # Public key for client-side auth
      
      # System defaults - ensure strings are safe for JavaScript contexts
      secrets['APP_ID'] = @app.id.to_s
      secrets['OWNER_ID'] = @app.team.id.to_s
      secrets['ENVIRONMENT'] = Rails.env
      
      # Add app name if needed, but ensure it's safe for JavaScript
      # Note: We don't typically expose app name as an env var, but if we do, it should be safe
      # secrets['APP_NAME'] = @app.name.to_s  # Commented out - not currently used
      
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
      # Configure subdomain based on deployment type using app.subdomain (slug)
      subdomain = case deployment_type
                  when :preview, :staging
                    "preview--#{@app.subdomain}"  # Use app slug: preview--pageforge
                  when :production
                    @app.subdomain  # Use app slug: pageforge
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