# Monkey patch for CloudflarePreviewService to integrate R2 asset offloading
module Patches
  module CloudflarePreviewServiceR2Patch
    extend ActiveSupport::Concern
    
    # This patch extends Deployment::CloudflarePreviewService
    def self.apply!
      Deployment::CloudflarePreviewService.prepend(self)
    end
    
    # Override deploy_to_environment to use R2 assets
    def deploy_to_environment_with_r2(environment, subdomain)
      return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
      
      worker_name = "#{environment}-#{@app.id}"
      
      # First, build the app if needed
      Rails.logger.info "[CloudflareR2] Building app for deployment..."
      builder = Deployment::ViteBuildService.new(@app)
      build_result = builder.build_app!
      
      unless build_result[:success]
        return { success: false, error: "Build failed: #{build_result[:error]}" }
      end
      
      # Upload assets to R2
      Rails.logger.info "[CloudflareR2] Uploading assets to R2..."
      r2_service = Deployment::R2AssetService.new(@app)
      r2_result = r2_service.upload_assets(build_result[:files])
      
      Rails.logger.info "[CloudflareR2] Uploaded #{r2_result[:stats][:uploaded_count]} assets to R2"
      
      # Filter out image files from the Worker script
      code_files = {}
      build_result[:files].each do |path, content|
        # Only include code files (JS, CSS, HTML) in Worker
        if path.match?(/\.(html|js|mjs|css|json|xml|txt|map)$/i)
          code_files[path] = content
        end
      end
      
      Rails.logger.info "[CloudflareR2] Including #{code_files.keys.count} code files in Worker"
      
      # Generate Worker script with R2 asset URLs
      worker_script = generate_worker_script_with_r2_and_code(code_files, r2_result[:asset_urls] || {})
      
      # Check Worker size
      worker_size = worker_script.bytesize
      worker_size_mb = (worker_size / 1024.0 / 1024.0).round(2)
      Rails.logger.info "[CloudflareR2] Worker script size: #{worker_size_mb} MB"
      
      if worker_size > 10 * 1024 * 1024  # 10MB limit
        return { 
          success: false, 
          error: "Worker script too large: #{worker_size_mb} MB (limit: 10MB)"
        }
      end
      
      # Upload worker script
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
      custom_domain_url = "https://#{subdomain}.#{@base_domain}"
      
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
        environment: environment,
        worker_size: worker_size_mb,
        r2_assets_count: r2_result[:stats][:uploaded_count]
      }
    rescue => e
      Rails.logger.error "#{environment.to_s.capitalize} deployment failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      { success: false, error: e.message }
    end
    
    # Alias the original method and use the new one
    alias_method :deploy_to_environment_original, :deploy_to_environment
    alias_method :deploy_to_environment, :deploy_to_environment_with_r2
    
    # Generate Worker script with code files embedded and R2 asset URLs
    def generate_worker_script_with_r2_and_code(code_files, asset_urls)
      # Convert code files to JSON for embedding
      code_files_json = JSON.generate(code_files)
      asset_urls_json = JSON.generate(asset_urls)
      
      <<~JAVASCRIPT
        // Code files embedded in Worker
        const CODE_FILES = #{code_files_json};
        
        // Asset URLs in R2
        const ASSET_URLS = #{asset_urls_json};
        
        addEventListener('fetch', event => {
          event.respondWith(handleRequest(event.request, event))
        })
        
        async function handleRequest(request, event) {
          const url = new URL(request.url)
          const pathname = url.pathname
          const env = event.env || {}
          
          // Handle API routes
          if (pathname.startsWith('/api/')) {
            return handleApiRequest(request, env)
          }
          
          // Clean path for lookups
          const cleanPath = pathname === '/' ? 'index.html' : pathname.slice(1)
          
          // Check if this is an asset in R2
          if (ASSET_URLS[cleanPath]) {
            // Redirect to R2 URL with cache headers
            return Response.redirect(ASSET_URLS[cleanPath], 301)
          }
          
          // Check if this is a code file
          if (CODE_FILES[cleanPath]) {
            const content = CODE_FILES[cleanPath]
            const contentType = getContentType(cleanPath)
            
            // Special handling for index.html
            if (cleanPath === 'index.html') {
              // Inject environment variables
              const publicEnvVars = getPublicEnvVars(env)
              const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`
              
              let modifiedHtml = content
              if (content.includes('</head>')) {
                modifiedHtml = content.replace('</head>', envScript + '</head>')
              } else if (content.includes('<body>')) {
                modifiedHtml = content.replace('<body>', '<body>' + envScript)
              } else {
                modifiedHtml = envScript + content
              }
              
              return new Response(modifiedHtml, {
                headers: {
                  'Content-Type': contentType,
                  'Cache-Control': 'no-cache',
                  'X-Frame-Options': 'ALLOWALL'
                }
              })
            }
            
            // Serve other code files
            return new Response(content, {
              headers: {
                'Content-Type': contentType,
                'Cache-Control': 'public, max-age=86400',
                'Access-Control-Allow-Origin': '*'
              }
            })
          }
          
          // For all other routes, serve index.html (SPA routing)
          const indexHtml = CODE_FILES['index.html']
          if (indexHtml) {
            const publicEnvVars = getPublicEnvVars(env)
            const envScript = `<script>window.ENV = ${JSON.stringify(publicEnvVars)};</script>`
            
            let modifiedHtml = indexHtml
            if (indexHtml.includes('</head>')) {
              modifiedHtml = indexHtml.replace('</head>', envScript + '</head>')
            } else {
              modifiedHtml = envScript + indexHtml
            }
            
            return new Response(modifiedHtml, {
              headers: {
                'Content-Type': 'text/html',
                'Cache-Control': 'no-cache',
                'X-Frame-Options': 'ALLOWALL'
              }
            })
          }
          
          return new Response('Not found', { status: 404 })
        }
        
        function getContentType(path) {
          const ext = path.split('.').pop().toLowerCase()
          const types = {
            'html': 'text/html',
            'js': 'application/javascript',
            'mjs': 'application/javascript',
            'css': 'text/css',
            'json': 'application/json',
            'xml': 'application/xml',
            'txt': 'text/plain',
            'map': 'application/json'
          }
          return types[ext] || 'text/plain'
        }
        
        function getPublicEnvVars(env) {
          const publicVars = {}
          const publicKeys = ['APP_ID', 'ENVIRONMENT', 'API_BASE_URL', 'SUPABASE_URL', 'SUPABASE_ANON_KEY']
          
          for (const key in env) {
            if (publicKeys.includes(key) || key.startsWith('PUBLIC_') || key.startsWith('VITE_')) {
              publicVars[key] = env[key]
            }
          }
          
          return publicVars
        }
        
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
    
    # Override staging deploy to use R2
    def deploy_staging!
      staging_subdomain = "preview--#{@app.subdomain}"
      deploy_to_environment_with_r2(:staging, staging_subdomain)
    end
    
    # Override production deploy to use R2  
    def deploy_production!
      production_subdomain = @app.subdomain
      deploy_to_environment_with_r2(:production, production_subdomain)
    end
  end
end