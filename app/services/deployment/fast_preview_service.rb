module Deployment
  # Fast preview deployment using CDN React and on-the-fly TypeScript compilation
  # Deploys in < 3 seconds without build step
  class FastPreviewService < CloudflarePreviewService
    
    def initialize(app)
      super(app)
    end
    
    # Deploy with instant transformation, no build needed
    def deploy_instant_preview!
      Rails.logger.info "[FastPreview] Deploying instant preview for app #{@app.id}"
      
      return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
      
      worker_name = "preview-#{@app.id}"
      subdomain = "preview-#{@app.id}"
      
      # Generate worker script with transformation capability
      worker_script = generate_fast_preview_worker
      
      # Upload worker
      upload_response = upload_worker(worker_name, worker_script)
      
      return { success: false, error: "Failed to upload worker" } unless upload_response['success']
      
      # Set environment variables
      set_worker_env_vars(worker_name)
      
      # Enable workers.dev subdomain
      enable_workers_dev_subdomain(worker_name)
      
      # Ensure route exists
      ensure_preview_route(subdomain, worker_name)
      
      # URLs
      custom_domain_url = "https://#{subdomain}.overskill.app"
      
      # Update app
      @app.update!(
        preview_url: custom_domain_url,
        preview_updated_at: Time.current,
        deployment_status: 'preview'
      )
      
      { 
        success: true,
        preview_url: custom_domain_url,
        deployment_time: "< 3 seconds",
        message: "Instant preview deployed!"
      }
    rescue => e
      Rails.logger.error "[FastPreview] Deployment failed: #{e.message}"
      { success: false, error: e.message }
    end
    
    private
    
    def generate_fast_preview_worker
      <<~JAVASCRIPT
        // Fast Preview Worker with on-the-fly TypeScript transformation
        // Using module format for better secret handling
        
        export default {
          async fetch(request, env, ctx) {
            return handleRequest(request, env, ctx);
          }
        };
        
        async function handleRequest(request, env, ctx) {
          const url = new URL(request.url)
          let pathname = url.pathname
          
          // API routes
          if (pathname.startsWith('/api/')) {
            return handleApiRequest(request, env, pathname)
          }
          
          // Serve index.html for root and routes
          if (pathname === '/' || !pathname.includes('.')) {
            return serveIndexHtml(env)
          }
          
          // Serve app files
          const file = getFile(pathname)
          if (!file) {
            // Return index for client-side routing
            return serveIndexHtml(env)
          }
          
          // Transform TypeScript/JSX files on the fly
          if (pathname.endsWith('.tsx') || pathname.endsWith('.ts')) {
            const transformed = await transformTypeScript(file)
            return new Response(transformed, {
              headers: {
                'Content-Type': 'application/javascript',
                'Cache-Control': 'no-cache'
              }
            })
          }
          
          // Serve other files as-is
          const contentType = getContentType(pathname)
          return new Response(file, {
            headers: {
              'Content-Type': contentType,
              'Cache-Control': 'no-cache'
            }
          })
        }
        
        // Serve index.html with CDN React and module loading
        function serveIndexHtml(env) {
          const html = getFile('index.html') || generateDefaultHtml()
          
          // Inject CDN scripts and environment variables
          const enhancedHtml = html
            .replace('</head>', getCDNScripts() + '</head>')
            .replace('<body>', '<body>' + getEnvScript(env))
          
          return new Response(enhancedHtml, {
            headers: {
              'Content-Type': 'text/html',
              'Cache-Control': 'no-cache'
            }
          })
        }
        
        // Generate default HTML if not provided
        function generateDefaultHtml() {
          return `<!DOCTYPE html>
            <html lang="en">
            <head>
              <meta charset="UTF-8">
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <title>App Preview</title>
              <script src="https://cdn.tailwindcss.com"></script>
            </head>
            <body>
              <div id="root"></div>
            </body>
            </html>`
        }
        
        // CDN scripts for React and Babel
        function getCDNScripts() {
          return `
            <!-- React via CDN -->
            <script crossorigin src="https://unpkg.com/react@18/umd/react.development.js"></script>
            <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.development.js"></script>
            
            <!-- Babel for JSX transformation -->
            <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
            
            <!-- Import maps for ES modules -->
            <script type="importmap">
            {
              "imports": {
                "react": "https://esm.sh/react@18",
                "react-dom": "https://esm.sh/react-dom@18",
                "react-dom/client": "https://esm.sh/react-dom@18/client",
                "@supabase/supabase-js": "https://esm.sh/@supabase/supabase-js@2",
                "zustand": "https://esm.sh/zustand@4",
                "react-router-dom": "https://esm.sh/react-router-dom@6"
              }
            }
            </script>
            
            <!-- Main app entry -->
            <script type="module">
              // Transform and load main app
              async function loadApp() {
                try {
                  // Fetch the main app file
                  const mainResponse = await fetch('/src/main.tsx')
                  if (!mainResponse.ok) {
                    // Try App.tsx as fallback
                    const appResponse = await fetch('/src/App.tsx')
                    if (appResponse.ok) {
                      const appCode = await appResponse.text()
                      const transformed = Babel.transform(appCode, {
                        presets: ['react', 'typescript'],
                        filename: 'App.tsx'
                      }).code
                      
                      // Create module and execute
                      const module = new Function('React', 'ReactDOM', transformed)
                      module(window.React, window.ReactDOM)
                    }
                  } else {
                    const mainCode = await mainResponse.text()
                    const transformed = Babel.transform(mainCode, {
                      presets: ['react', 'typescript'],
                      filename: 'main.tsx'
                    }).code
                    
                    // Execute the transformed code
                    eval(transformed)
                  }
                } catch (error) {
                  console.error('Failed to load app:', error)
                  document.getElementById('root').innerHTML = 
                    '<div class="p-4 text-red-500">Failed to load app: ' + error.message + '</div>'
                }
              }
              
              // Load app when DOM is ready
              if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', loadApp)
              } else {
                loadApp()
              }
            </script>
          `
        }
        
        // Inject environment variables
        function getEnvScript(env) {
          const publicVars = {}
          
          // Collect public environment variables
          const publicKeys = [
            'VITE_APP_ID',
            'VITE_SUPABASE_URL', 
            'VITE_SUPABASE_ANON_KEY',
            'VITE_ENVIRONMENT'
          ]
          
          for (const key of publicKeys) {
            if (env[key]) {
              publicVars[key] = env[key]
            }
          }
          
          return `
            <script>
              window.__ENV__ = ${JSON.stringify(publicVars)};
              // Make available as import.meta.env
              window.import = window.import || {};
              window.import.meta = window.import.meta || {};
              window.import.meta.env = window.__ENV__;
            </script>
          `
        }
        
        // Simple TypeScript to JavaScript transformation
        async function transformTypeScript(code) {
          // Remove TypeScript type annotations (basic transformation)
          // In production, we'd use SWC or esbuild WASM
          return code
            .replace(/: \w+(\[\])?/g, '') // Remove type annotations
            .replace(/as \w+/g, '') // Remove type assertions
            .replace(/interface \w+ {[^}]*}/g, '') // Remove interfaces
            .replace(/type \w+ = [^;]+;/g, '') // Remove type aliases
            .replace(/<(\w+)>/g, '') // Remove generics
            .replace(/export default/g, 'window.App =') // Export as global
        }
        
        // API request handling
        async function handleApiRequest(request, env, path) {
          // Supabase proxy
          if (path.startsWith('/api/db/')) {
            const supabaseUrl = env.SUPABASE_URL || env.VITE_SUPABASE_URL
            const supabaseKey = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY
            
            if (!supabaseUrl || !supabaseKey) {
              return new Response(
                JSON.stringify({ error: 'Database not configured' }), 
                { status: 503, headers: { 'Content-Type': 'application/json' } }
              )
            }
            
            const supabasePath = path.replace('/api/db', '')
            const targetUrl = supabaseUrl + '/rest/v1' + supabasePath
            
            const proxyRequest = new Request(targetUrl, request)
            proxyRequest.headers.set('apikey', supabaseKey)
            proxyRequest.headers.set('Authorization', `Bearer ${supabaseKey}`)
            
            return fetch(proxyRequest)
          }
          
          return new Response(
            JSON.stringify({ error: 'API endpoint not found' }), 
            { status: 404, headers: { 'Content-Type': 'application/json' } }
          )
        }
        
        // Get file from embedded files
        function getFile(path) {
          const files = #{app_files_as_json}
          
          // Normalize path
          path = path.startsWith('/') ? path.slice(1) : path
          
          return files[path] || null
        }
        
        function getContentType(path) {
          const ext = path.split('.').pop().toLowerCase()
          const types = {
            'html': 'text/html',
            'js': 'application/javascript',
            'jsx': 'application/javascript',
            'ts': 'application/javascript',
            'tsx': 'application/javascript',
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
      JAVASCRIPT
    end
  end
end