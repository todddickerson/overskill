# Service for managing Cloudflare preview workers that auto-update with changes
class Deployment::CloudflarePreviewService
  include HTTParty
  
  base_uri 'https://api.cloudflare.com/client/v4'
  
  def initialize(app)
    @app = app
    @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @api_key = ENV['CLOUDFLARE_API_KEY']
    @api_token = ENV['CLOUDFLARE_API_TOKEN']
    @email = ENV['CLOUDFLARE_EMAIL']
    @zone_id = ENV['CLOUDFLARE_ZONE_ID'] || ENV['CLOUDFLARE_ZONE'] # For overskill.app domain
    
    # Use API Token if available, otherwise use Global API Key
    if @api_token.present?
      self.class.headers 'Authorization' => "Bearer #{@api_token}"
    elsif @api_key.present? && @email.present?
      self.class.headers({
        'X-Auth-Email' => @email,
        'X-Auth-Key' => @api_key
      })
    end
  end
  
  # Create or update the auto-preview worker
  def update_preview!
    return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
    
    worker_name = "preview-#{@app.id}"
    preview_subdomain = "preview-#{@app.id}" # Use preview-{uuid} as subdomain
    
    # Ensure database tables exist before building
    ensure_database_tables_exist!
    
    # Build app with Vite first
    Rails.logger.info "[CloudflarePreview] Building app #{@app.id} with Vite"
    build_service = Deployment::ViteBuildService.new(@app)
    build_result = build_service.build_app!
    
    return { success: false, error: "Build failed: #{build_result[:error]}" } unless build_result[:success]
    
    # Upload worker script with built files
    worker_script = generate_worker_script_with_built_files(build_result[:files])
    upload_response = upload_worker(worker_name, worker_script)
    
    # Set environment variables
    set_worker_env_vars(worker_name)
    
    return { success: false, error: "Failed to upload preview worker" } unless upload_response['success']
    
    # Enable workers.dev subdomain for preview access
    enable_workers_dev_subdomain(worker_name)
    
    # Only create custom domain route if not using workers.dev
    use_workers_dev = ENV['USE_WORKERS_DEV_FOR_PREVIEW'] == 'true' || ENV['OVERSKILL_DOMAIN_DOWN'] == 'true'
    unless use_workers_dev
      # Ensure route exists for auto-preview domain (using overskill.app)
      ensure_preview_route(preview_subdomain, worker_name)
    end
    
    # Get both URLs
    workers_dev_url = "https://#{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
    custom_domain_url = "https://#{preview_subdomain}.overskill.app"
    
    # Update app with preview URLs
    # Use workers.dev URL when custom domain is down or disabled
    use_workers_dev = ENV['USE_WORKERS_DEV_FOR_PREVIEW'] == 'true' || ENV['OVERSKILL_DOMAIN_DOWN'] == 'true'
    preview_url = use_workers_dev ? workers_dev_url : custom_domain_url
    
    @app.update!(
      preview_url: preview_url,
      preview_updated_at: Time.current
    )
    
    note = use_workers_dev ? 
      "Using workers.dev URL (overskill.app is down)" : 
      "Using custom domain #{custom_domain_url}"
    
    { 
      success: true, 
      preview_url: preview_url,
      workers_dev_url: workers_dev_url,
      custom_domain_url: custom_domain_url,
      note: note
    }
  rescue => e
    Rails.logger.error "Preview update failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  # Deploy to staging (preview--app-name.overskill.app)
  def deploy_staging!
    staging_subdomain = "preview--#{generate_app_subdomain}"
    deploy_to_environment(:staging, staging_subdomain)
  end
  
  # Deploy to production (app-name.overskill.app)
  def deploy_production!
    production_subdomain = generate_app_subdomain
    deploy_to_environment(:production, production_subdomain)
  end
  
  private
  
  def set_worker_env_vars(worker_name, environment = :preview)
    # Set environment variables via Cloudflare API
    all_env_vars = build_env_vars_for_app(environment)
    
    # Cloudflare API expects both plaintext vars and secrets in specific format
    plaintext_bindings = []
    secret_bindings = []
    
    all_env_vars.each do |key, value|
      # SUPABASE_ANON_KEY is public (for browser), SERVICE_KEY is secret (for server)
      if (key.include?('SECRET') || key.include?('SERVICE_KEY') || key.include?('PRIVATE')) && !key.include?('ANON_KEY')
        # Treat as secret
        secret_bindings << { name: key, type: 'secret_text' }
        # Secrets need to be set separately via PATCH endpoint
        set_worker_secret(worker_name, key, value)
      else
        # Treat as plaintext (including SUPABASE_ANON_KEY)
        plaintext_bindings << { 
          name: key, 
          type: 'plain_text',
          text: value
        }
      end
    end
    
    # Update worker with env var bindings
    if plaintext_bindings.any?
      update_worker_env_vars(worker_name, plaintext_bindings)
    end
    
    Rails.logger.info "[CloudflarePreview] Set #{plaintext_bindings.size} env vars and #{secret_bindings.size} secrets"
  end
  
  def build_env_vars_for_app(environment = :preview)
    vars = {}
    
    # System vars
    vars['APP_ID'] = @app.id.to_s
    vars['APP_NAME'] = @app.name
    vars['ENVIRONMENT'] = environment.to_s
    
    # Set deployed timestamp based on environment
    case environment
    when :preview
      vars['DEPLOYED_AT'] = @app.preview_updated_at&.iso8601 || Time.current.iso8601
      vars['BUILD_ID'] = @app.build_id || "preview-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
    when :staging
      vars['DEPLOYED_AT'] = @app.staging_deployed_at&.iso8601 || Time.current.iso8601
      vars['BUILD_ID'] = @app.build_id || "staging-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
    when :production
      vars['DEPLOYED_AT'] = @app.deployed_at&.iso8601 || Time.current.iso8601
      vars['BUILD_ID'] = @app.build_id || "production-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
    else
      vars['DEPLOYED_AT'] = Time.current.iso8601
      vars['BUILD_ID'] = @app.build_id || "#{environment}-#{Time.current.strftime('%Y%m%d-%H%M%S')}"
    end
    
    # Supabase configuration (from app's shard)
    # Temporarily skip database shard access due to association issue
    # TODO: Fix database shard association circular reference
    # if @app.database_shard
    #   vars['SUPABASE_URL'] = @app.database_shard.supabase_url
    #   vars['SUPABASE_ANON_KEY'] = @app.database_shard.supabase_anon_key
    #   vars['SUPABASE_SERVICE_KEY'] = @app.database_shard.supabase_service_key
    # end
    
    # Use fallback Supabase config from environment for testing
    vars['SUPABASE_URL'] = ENV['SUPABASE_URL'] if ENV['SUPABASE_URL']
    vars['SUPABASE_ANON_KEY'] = ENV['SUPABASE_ANON_KEY'] if ENV['SUPABASE_ANON_KEY']
    vars['SUPABASE_SERVICE_KEY'] = ENV['SUPABASE_SERVICE_KEY'] if ENV['SUPABASE_SERVICE_KEY']
    
    # Add auth settings if present
    if @app.app_auth_setting
      auth_config = @app.app_auth_setting.to_frontend_config
      vars['AUTH_VISIBILITY'] = auth_config[:visibility].to_s
      vars['AUTH_REQUIRES_AUTH'] = auth_config[:requires_auth].to_s
      vars['AUTH_ALLOW_SIGNUPS'] = auth_config[:allow_signups].to_s
      vars['AUTH_ALLOW_ANONYMOUS'] = auth_config[:allow_anonymous].to_s
      vars['AUTH_REQUIRE_EMAIL_VERIFICATION'] = auth_config[:require_email_verification].to_s
      vars['AUTH_ALLOWED_PROVIDERS'] = auth_config[:allowed_providers].to_json
      vars['AUTH_ALLOWED_EMAIL_DOMAINS'] = auth_config[:allowed_email_domains].to_json
    end
    
    # Custom app env vars (but don't override system vars)
    @app.env_vars_for_deployment.each do |key, value|
      vars[key] = value unless ['APP_ID', 'ENVIRONMENT', 'DEPLOYED_AT', 'BUILD_ID'].include?(key)
    end
    
    # OAuth secrets (from Rails env)
    vars['GOOGLE_CLIENT_ID'] = ENV['GOOGLE_CLIENT_ID'] if ENV['GOOGLE_CLIENT_ID']
    vars['GOOGLE_CLIENT_SECRET'] = ENV['GOOGLE_CLIENT_SECRET'] if ENV['GOOGLE_CLIENT_SECRET']
    
    vars
  end
  
  def set_worker_secret(worker_name, key, value)
    # Set individual secret via PATCH endpoint
    begin
      response = self.class.patch(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}/secrets",
        body: {
          name: key,
          text: value,
          type: 'secret_text'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      Rails.logger.info "[CloudflarePreview] Set secret #{key} for worker #{worker_name}"
    rescue => e
      Rails.logger.warn "[CloudflarePreview] Failed to set secret #{key}: #{e.message}"
    end
  end
  
  def update_worker_env_vars(worker_name, bindings)
    # Update worker metadata with environment variable bindings
    begin
      metadata = {
        bindings: bindings,
        compatibility_date: '2024-01-01',
        main_module: 'worker.js'
      }
      
      # This might need adjustment based on Cloudflare's exact API
      response = self.class.patch(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        body: {
          metadata: metadata
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      Rails.logger.info "[CloudflarePreview] Updated env vars for worker #{worker_name}"
    rescue => e
      Rails.logger.warn "[CloudflarePreview] Failed to update env vars: #{e.message}"
    end
  end
  
  def ensure_database_tables_exist!
    Rails.logger.info "[CloudflarePreview] Ensuring database tables exist for app #{@app.id}"
    
    begin
      # Use the automatic table creation service
      table_service = Supabase::AutoTableService.new(@app)
      result = table_service.ensure_tables_exist!
      
      if result[:success] && result[:tables].any?
        Rails.logger.info "[CloudflarePreview] Tables ready: #{result[:tables].join(', ')}"
      end
    rescue => e
      Rails.logger.warn "[CloudflarePreview] Could not ensure tables: #{e.message}"
      # Continue with deployment - tables will be created on first use
    end
  end
  
  def credentials_present?
    @account_id.present? && @zone_id.present? && 
      (@api_token.present? || (@api_key.present? && @email.present?))
  end
  
  def generate_app_subdomain
    base_name = @app.name.downcase
                         .gsub(/[^a-z0-9\-]/, '-')
                         .gsub(/-+/, '-')
                         .gsub(/^-|-$/, '')
    
    # Ensure uniqueness if needed
    base_name.presence || "app-#{@app.id}"
  end
  
  def deploy_to_environment(environment, subdomain)
    return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
    
    worker_name = "#{environment}-#{@app.id}"
    
    # Upload worker script with latest files
    worker_script = generate_worker_script
    upload_response = upload_worker(worker_name, worker_script)
    
    # Set environment variables
    set_worker_env_vars(worker_name, environment)
    
    return { success: false, error: "Failed to upload #{environment} worker" } unless upload_response['success']
    
    # Enable workers.dev subdomain
    enable_workers_dev_subdomain(worker_name)
    
    # Ensure route exists for the environment
    ensure_preview_route(subdomain, worker_name)
    
    # Get both URLs
    workers_dev_url = "https://#{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
    custom_domain_url = "https://#{subdomain}.overskill.app"
    
    # Update app with deployment info based on environment
    case environment
    when :staging
      @app.update!(
        staging_url: custom_domain_url,
        staging_deployed_at: Time.current
      )
    when :production
      @app.update!(
        deployment_url: custom_domain_url,
        deployed_at: Time.current,
        deployment_status: 'deployed'
      )
    end
    
    { 
      success: true, 
      message: custom_domain_url,
      deployment_url: custom_domain_url,
      workers_dev_url: workers_dev_url,
      environment: environment
    }
  rescue => e
    Rails.logger.error "#{environment.to_s.capitalize} deployment failed: #{e.message}"
    { success: false, error: e.message }
  end

  def generate_worker_script_with_built_files(built_files)
    # Worker script that serves pre-built Vite files
    # Include environment variables directly in script for simplicity
    env_vars_js = build_env_vars_for_app(:preview).to_json
    
    <<~JAVASCRIPT
      // Environment variables embedded at build time
      const ENV_VARS = #{env_vars_js};

      addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request))
      })

      async function handleRequest(request) {
        const url = new URL(request.url)
        const pathname = url.pathname
        const env = ENV_VARS // Use embedded environment variables
        
        // Handle API routes that need secret env vars
        if (pathname.startsWith('/api/')) {
          return handleApiRequest(request, env)
        }
        
        // Try to serve static files first (JS, CSS, images, etc.)
        if (pathname !== '/' && pathname !== '/index.html') {
          const cleanPath = pathname.startsWith('/') ? pathname.slice(1) : pathname
          const file = getBuiltFile(cleanPath)
          if (file) {
            return serveBuiltFile(cleanPath)
          }
        }
        
        // For all other routes (including root), serve index.html for React Router
        // This includes: /, /login, /signup, /dashboard, etc.
        const indexHtml = getBuiltFile('index.html')
        if (indexHtml) {
          // Inject environment variables into HTML
          const publicEnvVars = getPublicEnvVars(env)
          const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`
          
          // Add version meta tags
          const versionMeta = `
            <meta name="overskill-app-id" content="${env.APP_ID}">
            <meta name="overskill-app-name" content="${env.APP_NAME}">
            <meta name="overskill-environment" content="${env.ENVIRONMENT}">
            <meta name="overskill-deployed-at" content="${env.DEPLOYED_AT || new Date().toISOString()}">
            <meta name="overskill-build-id" content="${env.BUILD_ID || 'unknown'}">
            <meta name="overskill-version" content="${Date.now()}">
          `
          
          // Inject into HTML
          let modifiedHtml = indexHtml.content
          if (indexHtml.content.includes('</head>')) {
            modifiedHtml = indexHtml.content.replace('</head>', versionMeta + envScript + '</head>')
          } else if (indexHtml.content.includes('<body>')) {
            modifiedHtml = indexHtml.content.replace('<body>', '<body>' + versionMeta + envScript)
          } else {
            modifiedHtml = versionMeta + envScript + indexHtml.content
          }
          
          return new Response(modifiedHtml, {
            headers: {
              'Content-Type': 'text/html',
              'X-Frame-Options': 'ALLOWALL'
            }
          })
        }
        
        return new Response('File not found', { status: 404 })
      }
      
      function getBuiltFile(path) {
        const files = #{built_files_as_json(built_files)}
        return files[path]
      }

      async function serveBuiltFile(path) {
        try {
          const files = #{built_files_as_json(built_files)}
          const file = files[path]
          
          if (!file) {
            return new Response('File not found', { status: 404 })
          }
          
          let content = file.content
          
          // Handle binary files
          if (file.binary) {
            // Decode base64 for binary files
            const binaryString = atob(content)
            const bytes = new Uint8Array(binaryString.length)
            for (let i = 0; i < binaryString.length; i++) {
              bytes[i] = binaryString.charCodeAt(i)
            }
            content = bytes
          }
          
          return new Response(content, {
            headers: {
              'Content-Type': file.content_type,
              'Cache-Control': 'public, max-age=31536000', // Cache built assets for 1 year
              'Access-Control-Allow-Origin': '*',
              'X-Frame-Options': 'ALLOWALL'
            }
          })
        } catch (error) {
          return new Response('Internal Server Error', { status: 500 })
        }
      }

      // Get only public environment variables (safe for client)
      function getPublicEnvVars(env) {
        const publicVars = {}
        const publicKeys = ['APP_ID', 'ENVIRONMENT', 'API_BASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']
        
        // Add any env vars starting with PUBLIC_
        for (const key in env) {
          if (publicKeys.includes(key) || key.startsWith('PUBLIC_') || key.startsWith('VITE_')) {
            publicVars[key] = env[key]
          }
        }
        
        return publicVars
      }
      
      // Handle API requests with access to secret env vars
      async function handleApiRequest(request, env) {
        const url = new URL(request.url)
        const path = url.pathname
        
        // Proxy to Supabase with service key
        if (path.startsWith('/api/supabase')) {
          const supabaseUrl = env.SUPABASE_URL
          const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY
          
          if (!supabaseUrl || !supabaseKey) {
            return new Response(JSON.stringify({ error: 'Database not configured' }), { 
              status: 503,
              headers: { 'Content-Type': 'application/json' }
            })
          }
          
          // Proxy the request
          const targetUrl = supabaseUrl + path.replace('/api/supabase', '')
          const proxyRequest = new Request(targetUrl, request)
          proxyRequest.headers.set('apikey', supabaseKey)
          proxyRequest.headers.set('Authorization', `Bearer ${supabaseKey}`)
          
          return fetch(proxyRequest)
        }
        
        return new Response(JSON.stringify({ error: 'API endpoint not found' }), { 
          status: 404,
          headers: { 'Content-Type': 'application/json' }
        })
      }
    JAVASCRIPT
  end

  def generate_worker_script
    # Worker script with environment variable support
    <<~JAVASCRIPT
      addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request, event))
      })

      async function handleRequest(request, event) {
        const url = new URL(request.url)
        const pathname = url.pathname
        const env = event.env || {} // Access environment variables
        
        // Handle API routes that need secret env vars
        if (pathname.startsWith('/api/')) {
          return handleApiRequest(request, env)
        }
        
        // Handle root path
        if (pathname === '/') {
          const htmlContent = await getFile('index.html')
          if (htmlContent) {
            // Inject public environment variables and version info
            const publicEnvVars = getPublicEnvVars(env)
            const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`
            
            // Add version meta tags with deployment tracking info
            const versionMeta = `
              <meta name="overskill-app-id" content="${env.APP_ID}">
              <meta name="overskill-app-name" content="${env.APP_NAME}">
              <meta name="overskill-environment" content="${env.ENVIRONMENT}">
              <meta name="overskill-deployed-at" content="${env.DEPLOYED_AT || new Date().toISOString()}">
              <meta name="overskill-build-id" content="${env.BUILD_ID || 'unknown'}">
              <meta name="overskill-version" content="${Date.now()}">
            `
            
            // Inject version meta and env vars
            let modifiedHtml = htmlContent
            if (htmlContent.includes('</head>')) {
              modifiedHtml = htmlContent.replace('</head>', versionMeta + envScript + '</head>')
            } else if (htmlContent.includes('<body>')) {
              modifiedHtml = htmlContent.replace('<body>', '<body>' + versionMeta + envScript)
            } else {
              modifiedHtml = versionMeta + envScript + htmlContent
            }
            
            return new Response(modifiedHtml, {
              headers: {
                'Content-Type': 'text/html',
                'X-Frame-Options': 'ALLOWALL'
              }
            })
          }
          return new Response('File not found', { status: 404 })
        }
        
        // Handle special files that might be requested
        if (pathname === '/overskill.js') {
          return new Response('// Overskill debug helper (empty)', {
            headers: {
              'Content-Type': 'application/javascript',
              'Cache-Control': 'no-cache'
            }
          })
        }
        
        // Serve static files
        const cleanPath = pathname.startsWith('/') ? pathname.slice(1) : pathname
        const contentType = getContentType(cleanPath)
        
        return serveFile(cleanPath, contentType)
      }
      
      function getFile(path) {
        const files = #{app_files_as_json}
        return files[path]
      }

      async function serveFile(path, contentType) {
        try {
          const files = #{app_files_as_json}
          const fileContent = files[path]
          
          if (!fileContent) {
            return new Response('File not found', { status: 404 })
          }
          
          return new Response(fileContent, {
            headers: {
              'Content-Type': contentType,
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Access-Control-Allow-Origin': '*',
              'X-Frame-Options': 'ALLOWALL'
            }
          })
        } catch (error) {
          return new Response('Internal Server Error', { status: 500 })
        }
      }

      function getContentType(path) {
        const ext = path.split('.').pop().toLowerCase()
        const types = {
          'html': 'text/html',
          'js': 'application/javascript',
          'mjs': 'application/javascript',
          'ts': 'application/javascript',
          'tsx': 'application/javascript',
          'jsx': 'application/javascript',
          'css': 'text/css',
          'json': 'application/json',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'gif': 'image/gif',
          'svg': 'image/svg+xml',
          'ico': 'image/x-icon'
        }
        return types[ext] || 'text/plain'
      }
      
      // Get only public environment variables (safe for client)
      function getPublicEnvVars(env) {
        const publicVars = {}
        const publicKeys = ['APP_ID', 'ENVIRONMENT', 'API_BASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']
        
        // Add any env vars starting with PUBLIC_
        for (const key in env) {
          if (publicKeys.includes(key) || key.startsWith('PUBLIC_')) {
            publicVars[key] = env[key]
          }
        }
        
        return publicVars
      }
      
      // Handle API requests with access to secret env vars
      async function handleApiRequest(request, env) {
        const url = new URL(request.url)
        const path = url.pathname
        
        // Proxy to Supabase with service key
        if (path.startsWith('/api/supabase')) {
          const supabaseUrl = env.SUPABASE_URL
          const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY
          
          if (!supabaseUrl || !supabaseKey) {
            return new Response(JSON.stringify({ error: 'Database not configured' }), { 
              status: 503,
              headers: { 'Content-Type': 'application/json' }
            })
          }
          
          // Proxy the request
          const targetUrl = supabaseUrl + path.replace('/api/supabase', '')
          const proxyRequest = new Request(targetUrl, request)
          proxyRequest.headers.set('apikey', supabaseKey)
          proxyRequest.headers.set('Authorization', `Bearer ${supabaseKey}`)
          
          return fetch(proxyRequest)
        }
        
        return new Response(JSON.stringify({ error: 'API endpoint not found' }), { 
          status: 404,
          headers: { 'Content-Type': 'application/json' }
        })
      }
    JAVASCRIPT
  end
  
  def built_files_as_json(built_files)
    # Convert built files hash to JSON for embedding in Worker script
    begin
      JSON.generate(built_files)
    rescue JSON::GeneratorError => e
      Rails.logger.error "JSON generation error for built files: #{e.message}"
      "{}"
    end
  end

  def app_files_as_json
    files_hash = {}
    @app.app_files.each do |file|
      # Ensure file content is properly handled for JSON embedding
      content = file.content.to_s
      
      # Remove problematic characters that can cause Cloudflare Workers to fail
      # Replace emojis and other non-ASCII characters with safe alternatives
      sanitized_content = content.gsub(/[^\x20-\x7E\n\r\t]/) do |char|
        case char
        when '📝' then '// TODO:'
        when '🎯' then '// GOAL:'
        when '✅' then '// DONE:'
        when '❌' then '// ERROR:'
        when '🚀' then '// LAUNCH:'
        else ''  # Remove other non-ASCII characters
        end
      end
      
      files_hash[file.path] = sanitized_content
    end
    
    # Use safe JSON generation that properly escapes content
    begin
      JSON.generate(files_hash)
    rescue JSON::GeneratorError => e
      Rails.logger.error "JSON generation error for app #{@app.id}: #{e.message}"
      # Return empty object if JSON generation fails
      "{}"
    end
  end
  
  def upload_worker(worker_name, script)
    # Try uploading as a regular service worker first
    # Cloudflare should auto-detect the format based on the script content
    response = self.class.put(
      "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
      headers: { 
        'Content-Type' => 'application/javascript'
      },
      body: script
    )
    
    Rails.logger.debug "[CloudflarePreview] Upload response: #{response.code} - #{response.body[0..200]}..."
    
    if response.success?
      begin
        parsed_response = JSON.parse(response.body)
        # Convert Cloudflare format to our expected format
        if parsed_response['success']
          { 'success' => true, 'result' => parsed_response['result'] }
        else
          { 'success' => false, 'error' => parsed_response['errors']&.first&.dig('message') || 'Upload failed' }
        end
      rescue JSON::ParserError => e
        Rails.logger.error "[CloudflarePreview] Failed to parse response: #{e.message}"
        { 'success' => false, 'error' => 'Invalid JSON response' }
      end
    else
      Rails.logger.error "[CloudflarePreview] Upload failed: #{response.code} - #{response.body}"
      
      # Try to parse error details
      begin
        error_details = JSON.parse(response.body)
        error_message = error_details['errors']&.first&.dig('message') || "Upload failed with status #{response.code}"
      rescue
        error_message = "Upload failed with status #{response.code}: #{response.body[0..200]}"
      end
      
      { 'success' => false, 'error' => error_message }
    end
  end
  
  def enable_workers_dev_subdomain(worker_name)
    # Enable the workers.dev subdomain for the worker
    begin
      # First check if workers.dev is already enabled for this account
      account_response = self.class.get("/accounts/#{@account_id}/workers/subdomain")
      
      if account_response.success?
        subdomain_enabled = account_response.parsed_response.dig("result", "enabled")
        
        if !subdomain_enabled
          # Enable workers.dev for the account if not already enabled
          enable_response = self.class.put(
            "/accounts/#{@account_id}/workers/subdomain",
            headers: { 'Content-Type' => 'application/json' },
            body: JSON.generate({ 
              enabled: true,
              name: @account_id.gsub('_', '-')  # Ensure valid subdomain format
            })
          )
          
          if enable_response.success?
            Rails.logger.info "[CloudflarePreview] Enabled workers.dev subdomain for account"
          else
            Rails.logger.warn "[CloudflarePreview] Failed to enable account subdomain: #{enable_response.body}"
          end
        end
      end
      
      # Now enable subdomain for the specific worker script
      response = self.class.patch(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}/subdomain",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({ enabled: true })
      )
      
      if response.success? || response.code == 200
        Rails.logger.info "[CloudflarePreview] Enabled workers.dev subdomain for worker #{worker_name}"
        true
      else
        Rails.logger.warn "[CloudflarePreview] Could not enable worker subdomain: #{response.body}"
        false
      end
    rescue => e
      Rails.logger.warn "[CloudflarePreview] Workers.dev subdomain setup error: #{e.message}"
      false
    end
  end
  
  def ensure_preview_route(subdomain, worker_name)
    route_pattern = "#{subdomain}.overskill.app/*"
    
    # Check if route exists
    routes_response = self.class.get("/zones/#{@zone_id}/workers/routes")
    routes = JSON.parse(routes_response.body)['result'] || []
    
    existing_route = routes.find { |r| r['pattern'] == route_pattern }
    
    if existing_route
      # Update existing route
      self.class.put(
        "/zones/#{@zone_id}/workers/routes/#{existing_route['id']}",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          pattern: route_pattern,
          script: worker_name
        })
      )
    else
      # Create new route
      self.class.post(
        "/zones/#{@zone_id}/workers/routes",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          pattern: route_pattern,
          script: worker_name
        })
      )
    end
  end
  
end