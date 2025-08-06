module Deployment
  # Service to deploy built React apps to Cloudflare Workers
  # Handles built files from Vite, serves them efficiently
  class CloudflareBuiltAppService < CloudflarePreviewService
    
    def initialize(app, built_files = nil)
      super(app)
      @built_files = built_files || app.app_files.where("path LIKE ?", "dist/%")
    end
    
    private
    
    # Override to generate worker script for built apps
    def generate_worker_script
      <<~JAVASCRIPT
        // Cloudflare Worker for built React app
        addEventListener('fetch', event => {
          event.respondWith(handleRequest(event.request, event))
        })
        
        async function handleRequest(request, event) {
          const url = new URL(request.url)
          let pathname = url.pathname
          const env = event.env || {}
          
          // API proxy endpoints
          if (pathname.startsWith('/api/')) {
            return handleApiRequest(request, env, pathname)
          }
          
          // Serve index.html for root and client routes
          if (pathname === '/' || !pathname.includes('.')) {
            pathname = '/index.html'
          }
          
          // Remove /dist prefix if present
          pathname = pathname.replace(/^\\/dist\\//, '/')
          
          // Get the file
          const file = getFile(pathname)
          
          if (!file) {
            // Try index.html for 404s (client-side routing)
            const indexFile = getFile('/index.html')
            if (indexFile) {
              return new Response(injectEnvVars(indexFile, env), {
                headers: {
                  'Content-Type': 'text/html',
                  'Cache-Control': 'no-cache'
                }
              })
            }
            return new Response('Not found', { status: 404 })
          }
          
          // Determine content type
          const contentType = getContentType(pathname)
          
          // Inject env vars for HTML
          let content = file
          if (contentType === 'text/html') {
            content = injectEnvVars(file, env)
          }
          
          // Return the file with appropriate headers
          return new Response(content, {
            headers: {
              'Content-Type': contentType,
              'Cache-Control': getCacheControl(pathname),
              'Access-Control-Allow-Origin': '*'
            }
          })
        }
        
        // Handle API requests with secret env vars
        async function handleApiRequest(request, env, path) {
          // Supabase proxy
          if (path.startsWith('/api/db/')) {
            const supabaseUrl = env.SUPABASE_URL || env.VITE_SUPABASE_URL
            const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY
            
            if (!supabaseUrl || !supabaseKey) {
              return new Response(
                JSON.stringify({ error: 'Database not configured' }), 
                { 
                  status: 503,
                  headers: { 'Content-Type': 'application/json' }
                }
              )
            }
            
            // Remove /api/db prefix and proxy to Supabase
            const supabasePath = path.replace('/api/db', '')
            const targetUrl = supabaseUrl + '/rest/v1' + supabasePath + request.url.search
            
            const proxyRequest = new Request(targetUrl, request)
            proxyRequest.headers.set('apikey', supabaseKey)
            proxyRequest.headers.set('Authorization', `Bearer ${supabaseKey}`)
            
            return fetch(proxyRequest)
          }
          
          // Auth endpoints
          if (path.startsWith('/api/auth/')) {
            return handleAuthRequest(request, env, path)
          }
          
          // Analytics endpoint
          if (path === '/api/analytics/track') {
            // Forward to Rails mothership
            const railsUrl = env.RAILS_API_URL || 'https://overskill.app'
            return fetch(railsUrl + '/api/v1/analytics/track', request)
          }
          
          return new Response(
            JSON.stringify({ error: 'API endpoint not found' }), 
            { 
              status: 404,
              headers: { 'Content-Type': 'application/json' }
            }
          )
        }
        
        // Handle authentication
        async function handleAuthRequest(request, env, path) {
          if (path === '/api/auth/google') {
            const clientId = env.GOOGLE_CLIENT_ID
            const clientSecret = env.GOOGLE_CLIENT_SECRET
            
            if (!clientId || !clientSecret) {
              return new Response(
                JSON.stringify({ error: 'Google OAuth not configured' }),
                { status: 503, headers: { 'Content-Type': 'application/json' } }
              )
            }
            
            // Implement OAuth flow
            // ... OAuth implementation
          }
          
          return new Response(
            JSON.stringify({ error: 'Auth endpoint not implemented' }),
            { status: 501, headers: { 'Content-Type': 'application/json' } }
          )
        }
        
        // Inject public environment variables into HTML
        function injectEnvVars(html, env) {
          const publicVars = {}
          
          // Collect public env vars
          const publicKeys = [
            'VITE_APP_ID',
            'VITE_SUPABASE_URL',
            'VITE_SUPABASE_ANON_KEY',
            'VITE_ENVIRONMENT',
            'VITE_API_BASE_URL'
          ]
          
          for (const key of publicKeys) {
            if (env[key]) {
              publicVars[key] = env[key]
            }
          }
          
          // Also include any env var starting with VITE_PUBLIC_
          for (const key in env) {
            if (key.startsWith('VITE_PUBLIC_')) {
              publicVars[key] = env[key]
            }
          }
          
          // Inject as global window object
          const envScript = `
            <script>
              window.__ENV__ = ${JSON.stringify(publicVars)};
              // Make available to import.meta.env
              if (typeof window !== 'undefined') {
                window.import = window.import || {};
                window.import.meta = window.import.meta || {};
                window.import.meta.env = Object.assign(
                  window.import.meta.env || {},
                  window.__ENV__
                );
              }
            </script>
          `
          
          // Inject before </head> or after <head>
          if (html.includes('</head>')) {
            return html.replace('</head>', envScript + '</head>')
          } else if (html.includes('<head>')) {
            return html.replace('<head>', '<head>' + envScript)
          } else {
            // Inject at beginning
            return envScript + html
          }
        }
        
        // Get file from embedded files object
        function getFile(path) {
          // Normalize path
          path = path.startsWith('/') ? path.slice(1) : path
          
          // Try with dist/ prefix
          const files = #{built_files_as_json}
          
          // Try exact match
          if (files[path]) return files[path]
          
          // Try with dist/ prefix
          if (files['dist/' + path]) return files['dist/' + path]
          
          // Try without dist/ prefix if path has it
          if (path.startsWith('dist/')) {
            const withoutDist = path.replace('dist/', '')
            if (files[withoutDist]) return files[withoutDist]
          }
          
          return null
        }
        
        function getContentType(path) {
          const ext = path.split('.').pop().toLowerCase()
          const types = {
            'html': 'text/html',
            'js': 'application/javascript',
            'mjs': 'application/javascript',
            'css': 'text/css',
            'json': 'application/json',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
            'gif': 'image/gif',
            'svg': 'image/svg+xml',
            'ico': 'image/x-icon',
            'woff': 'font/woff',
            'woff2': 'font/woff2',
            'ttf': 'font/ttf',
            'otf': 'font/otf'
          }
          return types[ext] || 'text/plain'
        }
        
        function getCacheControl(path) {
          // Assets with hashes can be cached forever
          if (path.includes('.') && path.match(/\\.[a-f0-9]{8}\\./)) {
            return 'public, max-age=31536000, immutable'
          }
          
          // HTML should not be cached
          if (path.endsWith('.html') || path === '/') {
            return 'no-cache, no-store, must-revalidate'
          }
          
          // Other assets can be cached for a day
          return 'public, max-age=86400'
        }
      JAVASCRIPT
    end
    
    def built_files_as_json
      files_hash = {}
      
      @built_files.each do |file|
        # Store with normalized path
        path = file.path.sub(/^dist\//, '')
        files_hash[path] = file.content
        
        # Also store with dist/ prefix for compatibility
        files_hash[file.path] = file.content
      end
      
      JSON.generate(files_hash)
    end
    
    # Override to use production deployment
    def deploy_production!
      return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
      
      worker_name = "app-#{@app.id}"
      subdomain = generate_app_subdomain
      
      # Upload worker script
      worker_script = generate_worker_script
      upload_response = upload_worker(worker_name, worker_script)
      
      return { success: false, error: "Failed to upload worker" } unless upload_response['success']
      
      # Set environment variables
      set_worker_env_vars(worker_name)
      
      # Enable workers.dev subdomain
      enable_workers_dev_subdomain(worker_name)
      
      # Set up custom domain route
      ensure_preview_route(subdomain, worker_name)
      
      # URLs
      workers_dev_url = "https://#{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
      custom_domain_url = "https://#{subdomain}.overskill.app"
      
      # Update app
      @app.update!(
        deployment_url: custom_domain_url,
        deployed_at: Time.current,
        deployment_status: 'deployed',
        status: 'published'
      )
      
      { 
        success: true,
        deployment_url: custom_domain_url,
        workers_dev_url: workers_dev_url,
        message: "App deployed successfully!"
      }
    rescue => e
      Rails.logger.error "Production deployment failed: #{e.message}"
      { success: false, error: e.message }
    end
  end
end