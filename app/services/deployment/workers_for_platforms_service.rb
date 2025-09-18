module Deployment
  class WorkersForPlatformsService
    include HTTParty
    base_uri "https://api.cloudflare.com/client/v4"

    # Namespace naming includes Rails.env for clarity
    # Format: overskill-{rails_env}-{deployment_env}
    # Examples:
    #   Development: overskill-development-preview, overskill-development-staging, overskill-development-production
    #   Production: overskill-production-preview, overskill-production-staging, overskill-production-production
    def self.namespace_for(environment)
      rails_env = Rails.env.to_s # development, staging, production

      case environment.to_sym
      when :production
        "overskill-#{rails_env}-production"
      when :staging
        "overskill-#{rails_env}-staging"
      when :preview
        "overskill-#{rails_env}-preview"
      else
        "overskill-#{rails_env}-preview"
      end
    end

    DISPATCH_WORKER_NAME = "overskill-dispatch"

    def initialize(app = nil)
      @app = app
      @account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
      @api_token = ENV["CLOUDFLARE_API_TOKEN"]

      raise "Missing CLOUDFLARE_ACCOUNT_ID" unless @account_id
      raise "Missing CLOUDFLARE_API_TOKEN" unless @api_token
    end

    # Create dispatch namespaces (run once during setup)
    def create_dispatch_namespaces
      results = {}

      [:preview, :staging, :production].each do |env|
        namespace = self.class.namespace_for(env)
        puts "Creating namespace: #{namespace}"
        results[env] = create_namespace(namespace)
      end

      results
    end

    # Deploy app script to WFP namespace
    def deploy_app(script_content, environment: :preview, metadata: {})
      namespace = self.class.namespace_for(environment)
      script_name = generate_script_name(environment)

      # SECURITY: Audit logging for all WFP deployments
      audit_deployment_start(environment, script_name, metadata)

      # If no script content provided (GitHub Actions will deploy), just prepare the deployment
      if script_content.nil?
        # Ensure namespace exists
        namespace_result = create_namespace(namespace)
        unless namespace_result[:success]
          audit_deployment_failure(environment, script_name, namespace_result[:error])
          return namespace_result
        end

        # Return deployment info without uploading script
        # GitHub Actions will handle the actual script upload
      else
        # Upload script to dispatch namespace
        upload_result = upload_script_to_namespace(
          namespace: namespace,
          script_name: script_name,
          script_content: script_content,
          metadata: metadata
        )

        unless upload_result[:success]
          audit_deployment_failure(environment, script_name, upload_result[:error])
          return upload_result
        end
      end

      # Generate the URL based on environment
      url = generate_app_url(script_name, environment)

      # Track deployment in Analytics API for cost monitoring
      track_deployment_analytics(script_name, namespace)

      # Create specific route for this app to preserve DNS for reserved subdomains
      # Don't let route creation failure affect the main deployment result
      route_created = create_app_specific_route(script_name, environment)
      Rails.logger.warn "Failed to create app-specific route for #{script_name}" unless route_created

      {
        success: true,
        namespace: namespace,
        script_name: script_name,
        worker_name: script_name,  # For compatibility with DeployAppJob
        url: url,
        worker_url: url,  # For compatibility with DeployAppJob
        deployment_url: url,  # Alternative field name
        environment: environment,
        deployed_at: Time.current,
        route_created: route_created
      }
    end

    # Get usage analytics for cost monitoring (per user request)
    def get_usage_analytics(days: 7)
      end_date = Date.today
      start_date = end_date - days.days

      response = self.class.get(
        "/accounts/#{@account_id}/analytics/workers/data",
        headers: headers,
        query: {
          start_date: start_date.to_s,
          end_date: end_date.to_s,
          sampling_rate: 1
        }
      )

      if response.success?
        {
          success: true,
          analytics: response["result"],
          period: "#{start_date} to #{end_date}"
        }
      else
        {
          success: false,
          error: "Failed to fetch analytics"
        }
      end
    end

    # List all scripts in a namespace
    def list_namespace_scripts(environment: :preview)
      namespace = self.class.namespace_for(environment)

      response = self.class.get(
        "/accounts/#{@account_id}/workers/dispatch/namespaces/#{namespace}/scripts",
        headers: headers
      )

      if response.success?
        {
          success: true,
          scripts: response["result"] || []
        }
      else
        {
          success: false,
          error: response["errors"]&.first&.dig("message") || "Failed to list scripts"
        }
      end
    end

    # Delete a script from namespace
    def delete_app(environment: :preview)
      namespace = self.class.namespace_for(environment)
      script_name = generate_script_name(environment)

      response = self.class.delete(
        "/accounts/#{@account_id}/workers/dispatch/namespaces/#{namespace}/scripts/#{script_name}",
        headers: headers
      )

      if response.success?
        {
          success: true,
          message: "Script #{script_name} deleted from #{namespace}"
        }
      else
        {
          success: false,
          error: response["errors"]&.first&.dig("message") || "Failed to delete script"
        }
      end
    end

    # Create the main dispatch worker (one-time setup)
    def create_dispatch_worker
      dispatch_script = generate_dispatch_worker_script

      # Metadata needs compatibility_date for module workers
      metadata = {
        main_module: "index.js",
        compatibility_date: "2024-01-01",
        bindings: generate_dispatch_bindings
      }

      form_data = [
        ["metadata", metadata.to_json],
        ["index.js", dispatch_script, {
          filename: "index.js",
          content_type: "application/javascript+module"
        }]
      ]

      response = upload_multipart(
        "/accounts/#{@account_id}/workers/scripts/#{DISPATCH_WORKER_NAME}",
        form_data
      )

      if response.success?
        # Create route for *.overskill.workers.dev
        create_dispatch_route

        {
          success: true,
          message: "Dispatch worker created successfully",
          url: "https://overskill.workers.dev"
        }
      else
        {
          success: false,
          error: response["errors"]&.first&.dig("message") || "Failed to create dispatch worker"
        }
      end
    end

    private

    def create_namespace(namespace_name)
      response = self.class.post(
        "/accounts/#{@account_id}/workers/dispatch/namespaces",
        headers: headers,
        body: {
          name: namespace_name,
          enabled: true
        }.to_json
      )

      # Check if namespace already exists by checking the error message
      error_message = response["errors"]&.first&.dig("message") || ""
      already_exists = response.code == 409 || error_message.include?("already exist")

      if response.success? || already_exists
        {
          success: true,
          namespace: namespace_name,
          message: already_exists ? "Namespace already exists" : "Namespace created"
        }
      else
        {
          success: false,
          error: error_message.presence || "Failed to create namespace"
        }
      end
    end

    def upload_script_to_namespace(namespace:, script_name:, script_content:, metadata: {})
      # Prepare the multipart form data with module format
      form_data = [
        ["metadata", {
          main_module: "index.js",
          compatibility_date: "2024-01-01",
          tags: generate_script_tags(metadata),
          bindings: generate_customer_script_bindings(@app)
        }.to_json],
        ["index.js", script_content, {
          filename: "index.js",
          content_type: "application/javascript+module"
        }]
      ]

      response = upload_multipart(
        "/accounts/#{@account_id}/workers/dispatch/namespaces/#{namespace}/scripts/#{script_name}",
        form_data
      )

      if response.success?
        {
          success: true,
          message: "Script uploaded successfully"
        }
      else
        {
          success: false,
          error: response["errors"]&.first&.dig("message") || "Failed to upload script"
        }
      end
    end

    def upload_multipart(url, form_data)
      uri = URI("https://api.cloudflare.com/client/v4#{url}")

      Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        request = Net::HTTP::Put.new(uri)
        request["Authorization"] = "Bearer #{@api_token}"

        # Create multipart form data
        boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
        request["Content-Type"] = "multipart/form-data; boundary=#{boundary}"

        body = form_data.map do |name, value, options = {}|
          if options[:filename]
            [
              "--#{boundary}",
              "Content-Disposition: form-data; name=\"#{name}\"; filename=\"#{options[:filename]}\"",
              "Content-Type: #{options[:content_type] || "application/octet-stream"}",
              "",
              value
            ].join("\r\n")
          else
            [
              "--#{boundary}",
              "Content-Disposition: form-data; name=\"#{name}\"",
              "",
              value
            ].join("\r\n")
          end
        end.join("\r\n") + "\r\n--#{boundary}--\r\n"

        request.body = body
        response = http.request(request)

        # Parse response and return in consistent format
        parsed_body = begin
          JSON.parse(response.body)
        rescue
          {}
        end

        # Create a response-like object that works with HTTParty methods
        result = OpenStruct.new(
          code: response.code.to_i,
          body: parsed_body,
          parsed_response: parsed_body
        )

        # Add success? method
        def result.success?
          code == 200 || code == 201
        end

        # Add array access
        def result.[](key)
          parsed_response[key]
        end

        result
      end
    end

    def generate_script_name(environment)
      return nil unless @app

      # Generate script name WITHOUT environment prefix
      # The dispatch worker handles environment routing via namespace bindings
      case environment.to_sym
      when :production
        # Use subdomain for production (clean URLs like countmaster.overskill.app)
        @app.subdomain || @app.obfuscated_id.downcase
      when :staging, :preview
        # Use obfuscated_id for staging/preview (dispatch worker routes via namespace)
        @app.obfuscated_id.downcase
      else
        @app.obfuscated_id.downcase
      end
    end

    def generate_app_url(script_name, environment)
      # WFP supports both subdomain AND path-based routing through a single dispatch worker
      # We can simulate unique subdomains using the dispatch worker with routing logic

      account_subdomain = get_account_subdomain || "toddspontentcomsaccount" # fallback

      # Option 1: Subdomain-like URLs (simulated through dispatch worker)
      # Each app gets what LOOKS like its own subdomain but routes through dispatch worker
      # Format: https://{app-id}.overskill-apps.{account}.workers.dev
      # This requires custom domain setup but provides the cleanest UX

      # Option 2: Path-based routing (current implementation)
      # Format: https://overskill-dispatch.{account}.workers.dev/app/{script-name}
      # Works immediately with workers.dev, no custom domain needed

      # For now, use path-based routing but prepare for subdomain migration
      dispatch_url = "https://#{DISPATCH_WORKER_NAME}.#{account_subdomain}.workers.dev"

      # Generate both formats for migration flexibility
      wfp_domain = ENV["WFP_APPS_DOMAIN"] || "overskill.app"

      # Add environment prefix to URL for dispatch worker routing
      url_script_name = case environment.to_sym
      when :staging
        "staging-#{script_name}"
      when :preview
        "preview-#{script_name}"
      else
        script_name
      end

      @subdomain_style_url = "https://#{url_script_name}.#{wfp_domain}" # Production custom domain for WFP apps
      @path_style_url = "#{dispatch_url}/app/#{script_name}" # Current workers.dev fallback

      # Return subdomain style URL (WFP apps domain is configured)
      @subdomain_style_url
    end

    # Generate subdomain-style URL for production use
    def generate_subdomain_style_url(script_name, custom_domain = nil)
      domain = custom_domain || ENV["WFP_APPS_DOMAIN"] || "overskill.app"
      "https://#{script_name}.#{domain}"
    end

    def generate_script_tags(metadata)
      tags = []
      tags << "app_id:#{@app.id}" if @app
      tags << "app_name:#{@app.name.parameterize}" if @app
      tags << "rails_env:#{Rails.env}"
      tags << "deployed_at:#{Time.current.iso8601}"
      tags << "platform:overskill"

      # Add any custom metadata as tags
      metadata.each do |key, value|
        tags << "#{key}:#{value}"
      end

      tags
    end

    def generate_dispatch_bindings
      # Generate bindings for each namespace
      bindings = []

      [:preview, :staging, :production].each do |env|
        namespace = self.class.namespace_for(env)
        binding_name = "NAMESPACE_#{env.to_s.upcase}"

        bindings << {
          name: binding_name,
          type: "dispatch_namespace",
          namespace: namespace
        }
      end

      bindings
    end

    def generate_customer_script_bindings(app = nil)
      # Get the preview files KV namespace (matches WfpPreviewService)
      namespace_title = "overskill-#{Rails.env}-preview-files"
      namespace_id = get_or_create_kv_namespace(namespace_title)

      bindings = [
        # KV namespace for file updates
        {
          type: "kv_namespace",
          name: "PREVIEW_FILES",
          namespace_id: namespace_id
        }
      ]

      # ============================================================
      # HMR Implementation Decision: ActionCable over Durable Objects
      # ============================================================
      # DECISION (Sep 2025): We use ActionCable for HMR instead of Durable Objects
      #
      # Why ActionCable wins for our use case:
      # 1. INSTANT UPDATES - No hibernation delays (always 50ms updates)
      # 2. ALREADY CONNECTED - Users in Rails app, no extra WebSocket needed
      # 3. ZERO COST - Uses existing Rails/ActionCable infrastructure
      # 4. SIMPLER - One connection path vs complex edge routing
      # 5. PREDICTABLE - Consistent latency regardless of idle time
      #
      # The Durable Object binding below is DEPRECATED but kept for reference.
      # Actual HMR is handled by app/channels/app_preview_channel.rb
      # ============================================================

      # [DEPRECATED] Add HMR Durable Object binding only if HMR is not disabled
      # This code is no longer used but kept for reference
      skip_hmr = ENV["SKIP_HMR_DEPLOYMENT"] == "true" || true # Always skip now
      if skip_hmr
        Rails.logger.info "[WFP] Skipping HMRHandler binding (using ActionCable for HMR)"
      else
        bindings << {
          type: "durable_object_namespace",
          name: "DO_HMR",
          class_name: "HMRHandler",
          script_name: nil # Uses same script
        }
        Rails.logger.info "[WFP] Including HMRHandler Durable Object binding [DEPRECATED]"
      end

      # Add platform-wide safe environment variables
      # SECURITY: Only add public configuration - no secrets!
      safe_env_vars = generate_safe_environment_variables
      safe_env_vars.each do |key, value|
        bindings << {
          type: "plain_text",
          name: key,
          text: value
        }
      end

      # Add app-specific environment variables (CRITICAL for multi-tenancy)
      if app
        app_specific_vars = generate_app_specific_environment_variables(app)
        app_specific_vars.each do |key, value|
          bindings << {
            type: "plain_text",
            name: key,
            text: value
          }
        end
      end

      bindings
    end

    private

    def generate_safe_environment_variables
      # SECURITY CRITICAL: Only include public configuration values
      # Never include secrets, API keys, database credentials, etc.
      # User apps run in browser context, so these values can be public
      {
        "OVERSKILL_API_BASE_URL" => ENV["OVERSKILL_API_BASE_URL"] || "https://api.overskill.app",
        "ENVIRONMENT" => Rails.env,
        "APP_DOMAIN" => ENV["WFP_APPS_DOMAIN"] || "overskill.app",
        "HMR_ENABLED" => Rails.env.development? ? "true" : "false"
      }.compact
    end

    def generate_app_specific_environment_variables(app)
      # SECURITY CRITICAL: Generate app-specific environment variables
      # These are unique per app and isolated from other apps
      # Each app gets its own scoped variables to prevent collisions

      supabase_url = generate_app_supabase_url(app)
      supabase_key = generate_app_supabase_key(app)

      app_vars = {
        # Core app identification
        "APP_ID" => app.obfuscated_id,
        "APP_NAME" => app.name&.gsub(/[^a-zA-Z0-9_]/, "_")&.upcase,
        "APP_OWNER_ID" => app.team.obfuscated_id,

        # Database configuration (app-specific Supabase project)
        "SUPABASE_URL" => supabase_url,
        "SUPABASE_ANON_KEY" => supabase_key,

        # VITE_ prefixed versions for client-side injection
        "VITE_APP_ID" => app.obfuscated_id,
        "VITE_SUPABASE_URL" => supabase_url,
        "VITE_SUPABASE_ANON_KEY" => supabase_key,
        "VITE_OWNER_ID" => app.team.obfuscated_id,
        "VITE_ANALYTICS_ENABLED" => "true",
        "VITE_ENVIRONMENT" => "production",

        # App-specific API endpoints
        "API_BASE_URL" => "https://api.overskill.app/apps/#{app.obfuscated_id}",
        "WEBSOCKET_URL" => "wss://ws.overskill.app/apps/#{app.obfuscated_id}",

        # Development/production flags
        "DEVELOPMENT_MODE" => Rails.env.development? ? "true" : "false",
        "BUILD_TIMESTAMP" => Time.current.to_i.to_s,
        "VERSION" => app.app_versions.maximum(:id)&.to_s || "1",

        # Security context for app isolation
        "APP_NAMESPACE" => "app_#{app.obfuscated_id}",
        "TENANT_ID" => app.team.obfuscated_id
      }

      # Add any additional app-specific configuration
      app_vars.merge!(extract_app_configuration_vars(app))

      # SECURITY: All values are specific to this app instance
      # No app can access another app's variables due to WFP isolation
      app_vars.compact
    end

    def generate_app_supabase_url(app)
      # Generate app-specific Supabase URL
      # Each app gets its own isolated database schema/project
      base_url = ENV["SUPABASE_URL"] || "https://app-db.overskill.app"
      "#{base_url}/app_#{app.obfuscated_id}"
    end

    def generate_app_supabase_key(app)
      # Generate app-specific Supabase anonymous key
      # This should be scoped to only access the app's own data
      # TODO: In production, integrate with Supabase API to generate
      # app-specific keys with Row Level Security (RLS) policies
      base_key = ENV["SUPABASE_ANON_KEY"]
      return nil unless base_key

      # For now, use a deterministic but app-specific key derivation
      # In production, this should be proper Supabase key management
      app_salt = "app_#{app.obfuscated_id}_#{app.created_at.to_i}"
      Digest::SHA256.hexdigest("#{base_key}_#{app_salt}")[0..63]
    end

    def extract_app_configuration_vars(app)
      # Extract additional configuration from app files or metadata
      # Look for environment variable configuration in app files
      config_vars = {}

      # Check for .env files or configuration in app files
      env_file = app.app_files.find_by(path: ".env")
      if env_file&.content.present?
        # Parse .env file content safely (only public vars)
        env_file.content.lines.each do |line|
          line = line.strip
          next if line.blank? || line.start_with?("#")

          if line =~ /^([A-Z_]+)=(.+)$/
            key, value = $1, $2
            # Only include safe, non-sensitive variables
            if safe_env_var_key?(key)
              config_vars["APP_#{key}"] = value.gsub(/['"]/, "")
            end
          end
        end
      end

      config_vars
    end

    def safe_env_var_key?(key)
      # Whitelist of safe environment variable prefixes/names
      # Reject any potentially sensitive keys
      safe_prefixes = %w[API_BASE_URL CLIENT_ID THEME FEATURE_FLAG DEBUG_MODE LOGGING_LEVEL]
      dangerous_keys = %w[SECRET API_KEY PASSWORD TOKEN PRIVATE DATABASE_URL]

      return false if dangerous_keys.any? { |danger| key.include?(danger) }
      safe_prefixes.any? { |prefix| key.start_with?(prefix) } ||
        key.match?(/^[A-Z_]+_CONFIG$/) ||
        key.match?(/^UI_[A-Z_]+$/)
    end

    def get_or_create_kv_namespace(title)
      # Check if namespace already exists
      response = self.class.get(
        "/accounts/#{@account_id}/storage/kv/namespaces",
        headers: {"Authorization" => "Bearer #{@api_token}"}
      )

      if response.success?
        existing = response["result"].find { |ns| ns["title"] == title }
        return existing["id"] if existing
      end

      # Create new namespace
      response = self.class.post(
        "/accounts/#{@account_id}/storage/kv/namespaces",
        headers: {
          "Authorization" => "Bearer #{@api_token}",
          "Content-Type" => "application/json"
        },
        body: {title: title}.to_json
      )

      if response.success?
        Rails.logger.info "[WFP] Created KV namespace: #{title} with ID #{response["result"]["id"]}"
        response["result"]["id"]
      else
        raise "Failed to create KV namespace: #{response["errors"]}"
      end
    end

    def generate_dispatch_worker_script
      <<~JAVASCRIPT
        // OverSkill Dispatch Worker
        // Supports BOTH subdomain and path-based routing for unique-looking URLs
        // Subdomain routing: {app-id}.overskill-apps.com
        // Path routing: overskill-dispatch.workers.dev/app/{script-name}
        
        export default {
          async fetch(request, env, ctx) {
            const url = new URL(request.url);
            const hostname = url.hostname;
            const path = url.pathname;
            
            // Determine routing method and extract script name
            const routingResult = parseRouting(hostname, path);
            
            if (!routingResult.scriptName) {
              // Root/invalid request - return platform landing page
              return new Response(generateLandingPage(routingResult.method), {
                headers: { 'content-type': 'text/html' }
              });
            }
            
            const { scriptName, environment, method } = routingResult;
            
            // Get the appropriate namespace
            const namespaceBinding = env[`NAMESPACE_${environment.toUpperCase()}`];
            
            if (!namespaceBinding) {
              return new Response(`Namespace ${environment} not configured`, { status: 500 });
            }
            
            try {
              // Get the customer's Worker from the namespace
              const customerWorker = namespaceBinding.get(scriptName);
              
              if (!customerWorker) {
                return new Response(`App '${scriptName}' not found in ${environment} namespace`, { 
                  status: 404,
                  headers: { 'content-type': 'text/plain' }
                });
              }
              
              // Create a clean request for the customer worker
              // For subdomain routing, present the request as if it came directly to their domain
              let customerUrl = url.href;
              if (method === 'subdomain') {
                // For subdomain routing, clean up the URL to look like direct access
                customerUrl = url.href;
              }
              
              const customerRequest = new Request(customerUrl, {
                method: request.method,
                headers: {
                  ...Object.fromEntries(request.headers.entries()),
                  'X-OverSkill-Environment': environment,
                  'X-OverSkill-Script': scriptName,
                  'X-OverSkill-Routing': method,
                  'X-OverSkill-Original-Host': hostname
                },
                body: request.body
              });
              
              // Forward the request to the customer's Worker
              return await customerWorker.fetch(customerRequest);
            } catch (error) {
              console.error('Dispatch error:', error);
              return new Response(`Internal server error: ${error.message}`, { status: 500 });
            }
          }
        };
        
        function parseRouting(hostname, path) {
          // Method 1: Subdomain-based routing (for custom domains)
          // Format: {app-id}.overskill.app (or configured WFP_APPS_DOMAIN)
          const wfpDomain = '#{ENV["WFP_APPS_DOMAIN"] || "overskill.app"}';
          if (hostname.includes('.' + wfpDomain)) {
            const subdomain = hostname.split('.')[0];
            
            if (subdomain && subdomain !== 'overskill-dispatch' && subdomain !== 'www') {
              let environment = 'production';
              let scriptName = subdomain;
              
              // Handle environment PREFIXES in subdomain (e.g., preview-abc123)
              if (subdomain.startsWith('preview-')) {
                environment = 'preview';
                scriptName = subdomain.replace(/^preview-/, '').toLowerCase();
              } else if (subdomain.startsWith('staging-')) {
                environment = 'staging';
                scriptName = subdomain.replace(/^staging-/, '').toLowerCase();
              } else {
                // For production, convert to lowercase to match script names
                scriptName = subdomain.toLowerCase();
              }
              
              return { scriptName, environment, method: 'subdomain' };
            }
          }
          
          // Method 2: Path-based routing (for workers.dev)
          // Format: overskill-dispatch.account.workers.dev/app/{script-name}
          const pathParts = path.split('/').filter(part => part.length > 0);
          
          if (pathParts.length >= 2 && pathParts[0] === 'app') {
            const scriptName = pathParts[1];
            let environment = 'production';
            
            // Handle environment prefixes in script name
            if (scriptName.startsWith('preview-')) {
              environment = 'preview';
            } else if (scriptName.startsWith('staging-')) {
              environment = 'staging';
            }
            
            return { scriptName, environment, method: 'path' };
          }
          
          // No valid routing found
          return { scriptName: null, environment: 'production', method: 'unknown' };
        }
        
        function generateLandingPage(routingMethod) {
          return `<!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>OverSkill Platform</title>
          <style>
            body { 
              font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
              margin: 0; padding: 2rem; background: linear-gradient(135deg, #667eea, #764ba2);
              min-height: 100vh; display: flex; align-items: center; justify-content: center;
            }
            .container { 
              background: white; border-radius: 12px; padding: 3rem; 
              box-shadow: 0 20px 40px rgba(0,0,0,0.1); max-width: 700px;
            }
            h1 { color: #333; margin-bottom: 1rem; }
            .route-info { background: #f7f9fc; padding: 1rem; border-radius: 8px; margin: 1rem 0; }
            .badge { 
              display: inline-block; background: #667eea; color: white; 
              padding: 0.25rem 0.75rem; border-radius: 20px; font-size: 0.875rem; 
              margin-right: 0.5rem;
            }
            .code { 
              background: #2d3748; color: #e2e8f0; padding: 0.25rem 0.5rem; 
              border-radius: 4px; font-family: 'Monaco', monospace; font-size: 0.875rem;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>🚀 OverSkill Platform</h1>
            <p>AI-powered app marketplace with Workers for Platforms</p>
            
            <div class="route-info">
              <h2>Dual Routing Support</h2>
              <p><strong>Current mode:</strong> <span class="badge">${routingMethod || 'unknown'}</span></p>
              <p>This dispatch worker supports both subdomain and path-based app access.</p>
            </div>
            
            <div class="route-info">
              <h2>🌐 Subdomain-Style URLs (overskill.app)</h2>
              <p>Each app gets its own subdomain that <em>looks</em> unique:</p>
              <ul>
                <li><span class="code">abc123.overskill.app</span> → Production</li>
                <li><span class="code">preview-abc123.overskill.app</span> → Preview</li>
                <li><span class="code">staging-abc123.overskill.app</span> → Staging</li>
              </ul>
              <p><small>✨ Available with overskill.app domain</small></p>
            </div>
            
            <div class="route-info">
              <h2>📁 Path-Style URLs (Workers.dev)</h2>
              <p>All apps accessed through single dispatch worker:</p>
              <ul>
                <li><span class="code">/app/abc123</span> → Production</li>
                <li><span class="code">/app/preview-abc123</span> → Preview</li>
                <li><span class="code">/app/staging-abc123</span> → Staging</li>
              </ul>
              <p><small>Works immediately with workers.dev domains</small></p>
            </div>
            
            <div class="route-info">
              <h2>Architecture Benefits</h2>
              <p><span class="badge">Single Worker</span> manages ALL apps</p>
              <p><span class="badge">Unlimited Scale</span> 50,000+ apps supported</p>
              <p><span class="badge">Cost Efficient</span> $25/month base vs $25,000</p>
            </div>
          </div>
        </body>
        </html>`;
        }
      JAVASCRIPT
    end

    def create_dispatch_route
      # Get WFP apps domain zone ID first
      wfp_domain = ENV["WFP_APPS_DOMAIN"] || "overskill.app"
      zone_id = get_zone_id(wfp_domain)

      unless zone_id
        puts "⚠️ Could not find #{wfp_domain} zone - custom domain route must be created manually"
        return true # Don't fail the deployment
      end

      # Create specific route instead of wildcard to preserve existing DNS
      # This allows reserved subdomains (dev, api, etc.) to use normal DNS routing
      puts "⚠️ Note: Using specific routes instead of wildcard to preserve DNS"
      return true # Routes are created per-app during deployment

      response = self.class.post(
        "/zones/#{zone_id}/workers/routes",
        headers: headers,
        body: route_data.to_json
      )

      wfp_domain = ENV["WFP_APPS_DOMAIN"] || "overskill.app"
      if response.success? || response.code == 409 # 409 = already exists
        puts "✅ Custom domain route created/exists for *.#{wfp_domain}"
      else
        error_msg = response["errors"]&.first&.dig("message") || "Failed to create route"
        puts "⚠️ Route creation result: #{error_msg}"
        puts "📋 Manual step: Add *.#{wfp_domain} custom domain in Cloudflare Dashboard"
      end
      true
    end

    def get_zone_id(domain)
      response = self.class.get(
        "/zones?name=#{domain}",
        headers: headers
      )

      if response.success? && response["result"]&.any?
        response["result"].first["id"]
      end
    end

    def create_app_specific_route(script_name, environment)
      wfp_domain = ENV["WFP_APPS_DOMAIN"] || "overskill.app"
      zone_id = get_zone_id(wfp_domain)
      return false unless zone_id

      # Generate route pattern based on environment
      pattern = case environment
      when :preview
        "preview-#{script_name}.#{wfp_domain}/*"
      when :staging
        "staging-#{script_name}.#{wfp_domain}/*"
      else
        "#{script_name}.#{wfp_domain}/*"
      end

      route_data = {
        pattern: pattern,
        script: DISPATCH_WORKER_NAME
      }

      response = self.class.post(
        "/zones/#{zone_id}/workers/routes",
        headers: headers,
        body: route_data.to_json
      )

      if response.success? || response.code == 409 # 409 = already exists
        puts "✅ Created route: #{pattern} → #{DISPATCH_WORKER_NAME}"
        true
      else
        error_msg = response["errors"]&.first&.dig("message") || "Failed to create route"
        puts "⚠️ Route creation failed: #{error_msg}"
        false
      end
    end

    def get_account_subdomain
      # Get account subdomain from Cloudflare API
      response = self.class.get(
        "/accounts/#{@account_id}",
        headers: headers
      )

      if response.success? && response["result"]
        account_name = response["result"]["name"]
        # Convert account name to valid subdomain
        account_name.downcase.gsub(/[^a-z0-9]/, "")
      end
    rescue => e
      Rails.logger.error "Failed to get account subdomain: #{e.message}"
      nil
    end

    # Promote app from preview to staging environment
    def promote_to_staging
      Rails.logger.info "[WorkersForPlatformsService] Promoting app to staging"

      # Get the current preview deployment
      preview_namespace = self.class.namespace_for(:preview)
      preview_script_name = generate_script_name(:preview)

      # Copy to staging namespace
      self.class.namespace_for(:staging)
      generate_script_name(:staging)

      # Get the current script from preview
      script_result = get_script_from_namespace(preview_namespace, preview_script_name)

      if script_result[:success]
        # Deploy to staging
        deployment_result = deploy_app(script_result[:content], environment: :staging)

        if deployment_result[:success]
          Rails.logger.info "[WorkersForPlatformsService] ✅ Promoted to staging: #{deployment_result[:url]}"

          {
            success: true,
            deployment_id: "staging-#{@app.obfuscated_id}-#{Time.current.to_i}",
            staging_url: deployment_result[:url],
            message: "Successfully promoted to staging"
          }
        else
          {success: false, error: "Failed to deploy to staging: #{deployment_result[:error]}"}
        end
      else
        {success: false, error: "Failed to get preview script: #{script_result[:error]}"}
      end
    rescue => e
      Rails.logger.error "[WorkersForPlatformsService] Error promoting to staging: #{e.message}"
      {success: false, error: e.message}
    end

    # Promote app from staging to production environment
    def promote_to_production
      Rails.logger.info "[WorkersForPlatformsService] Promoting app to production"

      # Get the current staging deployment
      staging_namespace = self.class.namespace_for(:staging)
      staging_script_name = generate_script_name(:staging)

      # Copy to production namespace
      self.class.namespace_for(:production)
      generate_script_name(:production)

      # Get the current script from staging
      script_result = get_script_from_namespace(staging_namespace, staging_script_name)

      if script_result[:success]
        # Deploy to production
        deployment_result = deploy_app(script_result[:content], environment: :production)

        if deployment_result[:success]
          Rails.logger.info "[WorkersForPlatformsService] ✅ Promoted to production: #{deployment_result[:url]}"

          {
            success: true,
            deployment_id: "production-#{@app.obfuscated_id}-#{Time.current.to_i}",
            production_url: deployment_result[:url],
            message: "Successfully promoted to production"
          }
        else
          {success: false, error: "Failed to deploy to production: #{deployment_result[:error]}"}
        end
      else
        {success: false, error: "Failed to get staging script: #{script_result[:error]}"}
      end
    rescue => e
      Rails.logger.error "[WorkersForPlatformsService] Error promoting to production: #{e.message}"
      {success: false, error: e.message}
    end

    # Get deployment status for all environments
    def get_deployment_status
      Rails.logger.info "[WorkersForPlatformsService] Getting deployment status"

      status = {
        success: true,
        worker_name: @app.obfuscated_id.downcase,
        environments: {}
      }

      [:preview, :staging, :production].each do |env|
        namespace = self.class.namespace_for(env)
        script_name = generate_script_name(env)

        # Check if script exists in namespace
        exists_result = script_exists_in_namespace?(namespace, script_name)

        status[:environments][env] = if exists_result[:exists]
          {
            url: generate_app_url(script_name, env),
            status: "deployed",
            last_deployed: exists_result[:modified_on]
          }
        else
          {
            url: generate_app_url(script_name, env),
            status: "not_deployed",
            last_deployed: nil
          }
        end
      end

      status
    rescue => e
      Rails.logger.error "[WorkersForPlatformsService] Error getting deployment status: #{e.message}"
      {success: false, error: e.message}
    end

    # Get script content from a namespace
    def get_script_from_namespace(namespace, script_name)
      response = self.class.get(
        "/accounts/#{@account_id}/workers/dispatch/namespaces/#{namespace}/scripts/#{script_name}/content",
        headers: headers
      )

      if response.success?
        {success: true, content: response.body}
      else
        {success: false, error: "Script not found: #{response.code}"}
      end
    rescue => e
      {success: false, error: e.message}
    end

    # Check if script exists in namespace
    def script_exists_in_namespace?(namespace, script_name)
      response = self.class.get(
        "/accounts/#{@account_id}/workers/dispatch/namespaces/#{namespace}/scripts/#{script_name}",
        headers: headers
      )

      if response.success? && response["result"]
        {
          exists: true,
          modified_on: response["result"]["modified_on"]
        }
      else
        {exists: false}
      end
    rescue
      {exists: false}
    end

    def track_deployment_analytics(script_name, namespace)
      # Track deployment for cost monitoring using Analytics API
      # This will be used to calculate per-app costs
      Rails.logger.info "Deployment tracked: #{script_name} in #{namespace}"
      # Additional analytics tracking can be added here
    end

    def headers
      {
        "Authorization" => "Bearer #{@api_token}",
        "Content-Type" => "application/json"
      }
    end

    # Audit logging methods for security and compliance tracking
    def audit_deployment_start(environment, script_name, metadata)
      Rails.logger.info "[WFP_AUDIT] Deployment started: environment=#{environment} script=#{script_name} app_id=#{@app&.id} metadata=#{metadata.to_json}"

      # Track in database for persistent audit trail (not just logs)
      @app&.app_deployments&.create!(
        environment: environment,
        status: "deploying",
        deployment_id: script_name,
        deployment_metadata: {
          initiated_at: Time.current.iso8601,
          initiated_by: "WFP Service",
          metadata: metadata
        }.to_json
      )
    end

    def audit_deployment_failure(environment, script_name, error)
      Rails.logger.error "[WFP_AUDIT] Deployment failed: environment=#{environment} script=#{script_name} error=#{error}"

      if @app
        deployment = @app.app_deployments.where(deployment_id: script_name, environment: environment).last
        deployment&.fail_deployment!(error)
      end
    end

    def audit_deployment_success(environment, script_name, url)
      Rails.logger.info "[WFP_AUDIT] Deployment succeeded: environment=#{environment} script=#{script_name} url=#{url}"

      if @app
        deployment = @app.app_deployments.where(deployment_id: script_name, environment: environment).last
        deployment&.complete_deployment!(url)
      end
    end
  end
end
