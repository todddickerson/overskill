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
    
    # Upload worker script with latest files
    worker_script = generate_worker_script
    upload_response = upload_worker(worker_name, worker_script)
    
    # Set environment variables
    set_worker_env_vars(worker_name)
    
    return { success: false, error: "Failed to upload preview worker" } unless upload_response['success']
    
    # Try to enable workers.dev subdomain (non-critical if it fails)
    enable_workers_dev_subdomain(worker_name)
    
    # Ensure route exists for auto-preview domain (using overskill.app for now)
    ensure_preview_route(preview_subdomain, worker_name)
    
    # Get both URLs
    workers_dev_url = "https://#{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
    custom_domain_url = "https://#{preview_subdomain}.overskill.app"
    
    # Update app with preview URLs
    # Use custom domain now that wildcard DNS is configured
    preview_url = custom_domain_url
    
    @app.update!(
      preview_url: preview_url,
      preview_updated_at: Time.current
    )
    
    { 
      success: true, 
      preview_url: preview_url,
      custom_domain_url: custom_domain_url,
      note: "Using workers.dev URL. To use custom domain, add DNS CNAME: #{preview_subdomain} -> #{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
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
  
  def set_worker_env_vars(worker_name)
    return unless @app.app_env_vars.any?
    
    env_vars = @app.env_vars_for_deployment
    
    # Cloudflare Workers API to set environment variables
    # Note: This is simplified - actual implementation may need to batch these
    env_vars.each do |key, value|
      Rails.logger.info "Would set env var #{key} for worker #{worker_name}"
      # TODO: Implement actual Cloudflare API call when API is available
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
            // Inject public environment variables
            const publicEnvVars = getPublicEnvVars(env)
            const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`
            
            // Inject env vars before </head> or <body>
            let modifiedHtml = htmlContent
            if (htmlContent.includes('</head>')) {
              modifiedHtml = htmlContent.replace('</head>', envScript + '</head>')
            } else if (htmlContent.includes('<body>')) {
              modifiedHtml = htmlContent.replace('<body>', '<body>' + envScript)
            } else {
              modifiedHtml = envScript + htmlContent
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
  
  def app_files_as_json
    files_hash = {}
    @app.app_files.each do |file|
      files_hash[file.path] = file.content
    end
    JSON.generate(files_hash)
  end
  
  def upload_worker(worker_name, script)
    response = self.class.put(
      "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
      headers: { 'Content-Type' => 'application/javascript' },
      body: script
    )
    
    JSON.parse(response.body)
  end
  
  def enable_workers_dev_subdomain(worker_name)
    # Enable the workers.dev subdomain for the worker
    # Note: This endpoint requires account-level permissions and may not work with API tokens
    begin
      response = self.class.patch(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}/subdomain",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({ enabled: true })
      )
      
      if response.code == 200
        Rails.logger.info "Enabled workers.dev subdomain for #{worker_name}"
      else
        # Log the error but don't fail the deployment
        # The worker is still accessible via custom domain
        Rails.logger.warn "Failed to enable workers.dev subdomain: #{response.body}"
        Rails.logger.info "Worker is still accessible via custom domain"
      end
    rescue => e
      # Don't fail if subdomain enabling fails - worker still works via custom domain
      Rails.logger.warn "Could not enable workers.dev subdomain (non-critical): #{e.message}"
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