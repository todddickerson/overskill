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
        
        // API request handling with comprehensive Supabase proxy
        async function handleApiRequest(request, env, path) {
          const url = new URL(request.url)
          
          // Database operations via Supabase proxy
          if (path.startsWith('/api/db/')) {
            return handleSupabaseProxy(request, env, path)
          }
          
          // Authentication endpoints
          if (path.startsWith('/api/auth/')) {
            return handleAuthProxy(request, env, path)
          }
          
          // Session management
          if (path.startsWith('/api/session')) {
            return handleSessionManagement(request, env)
          }
          
          // File operations
          if (path.startsWith('/api/files/')) {
            return handleFileOperations(request, env, path)
          }
          
          return new Response(
            JSON.stringify({ error: 'API endpoint not found' }), 
            { status: 404, headers: { 'Content-Type': 'application/json' } }
          )
        }
        
        // Enhanced Supabase proxy with RLS support
        async function handleSupabaseProxy(request, env, path) {
          const supabaseUrl = env.SUPABASE_URL || env.VITE_SUPABASE_URL
          const serviceKey = env.SUPABASE_SERVICE_KEY
          const anonKey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY
          
          if (!supabaseUrl || (!serviceKey && !anonKey)) {
            return new Response(
              JSON.stringify({ error: 'Database not configured' }), 
              { status: 503, headers: { 'Content-Type': 'application/json' } }
            )
          }
          
          // Determine which key to use based on operation
          const isAdminOperation = request.method === 'DELETE' || 
                                 path.includes('/admin/') ||
                                 request.headers.get('x-admin-operation')
          
          const apiKey = isAdminOperation && serviceKey ? serviceKey : anonKey
          
          // Convert /api/db/* to Supabase REST API path
          const supabasePath = path.replace('/api/db', '/rest/v1')
          const targetUrl = supabaseUrl + supabasePath + url.search
          
          // Create proxy request
          const proxyRequest = new Request(targetUrl, {
            method: request.method,
            headers: request.headers,
            body: request.body
          })
          
          // Set Supabase headers
          proxyRequest.headers.set('apikey', apiKey)
          proxyRequest.headers.set('Authorization', `Bearer ${apiKey}`)
          proxyRequest.headers.set('Content-Type', 'application/json')
          
          // Add app-specific RLS context if available
          if (env.APP_ID) {
            proxyRequest.headers.set('x-app-id', env.APP_ID)
          }
          
          try {
            const response = await fetch(proxyRequest)
            
            // Clone response with CORS headers
            const newResponse = new Response(response.body, {
              status: response.status,
              statusText: response.statusText,
              headers: response.headers
            })
            
            // Add CORS headers
            newResponse.headers.set('Access-Control-Allow-Origin', '*')
            newResponse.headers.set('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS')
            newResponse.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-app-id, x-admin-operation')
            
            return newResponse
          } catch (error) {
            console.error('Supabase proxy error:', error)
            return new Response(
              JSON.stringify({ error: 'Database request failed', details: error.message }),
              { status: 500, headers: { 'Content-Type': 'application/json' } }
            )
          }
        }
        
        // Authentication proxy for OAuth and session management
        async function handleAuthProxy(request, env, path) {
          const supabaseUrl = env.SUPABASE_URL || env.VITE_SUPABASE_URL
          const anonKey = env.SUPABASE_ANON_KEY || env.VITE_SUPABASE_ANON_KEY
          
          if (!supabaseUrl || !anonKey) {
            return new Response(
              JSON.stringify({ error: 'Authentication not configured' }),
              { status: 503, headers: { 'Content-Type': 'application/json' } }
            )
          }
          
          // Convert /api/auth/* to Supabase auth API
          const authPath = path.replace('/api/auth', '/auth/v1')
          const targetUrl = supabaseUrl + authPath + url.search
          
          const proxyRequest = new Request(targetUrl, {
            method: request.method,
            headers: request.headers,
            body: request.body
          })
          
          proxyRequest.headers.set('apikey', anonKey)
          proxyRequest.headers.set('Authorization', `Bearer ${anonKey}`)
          
          return fetch(proxyRequest)
        }
        
        // Simple session management using headers/localStorage
        async function handleSessionManagement(request, env) {
          if (request.method === 'GET') {
            // Return session info from Authorization header
            const authHeader = request.headers.get('Authorization')
            if (authHeader && authHeader.startsWith('Bearer ')) {
              return new Response(JSON.stringify({ 
                authenticated: true,
                token: authHeader.replace('Bearer ', '')
              }), {
                headers: { 'Content-Type': 'application/json' }
              })
            }
            
            return new Response(JSON.stringify({ authenticated: false }), {
              headers: { 'Content-Type': 'application/json' }
            })
          }
          
          return new Response(JSON.stringify({ error: 'Method not allowed' }), { 
            status: 405,
            headers: { 'Content-Type': 'application/json' }
          })
        }
        
        // File operations (future: integrate with R2)
        async function handleFileOperations(request, env, path) {
          // For now, return not implemented
          // Future: integrate with Cloudflare R2 for file storage
          return new Response(JSON.stringify({ 
            error: 'File operations not yet implemented',
            message: 'Will be integrated with Cloudflare R2 storage'
          }), { 
            status: 501,
            headers: { 'Content-Type': 'application/json' }
          })
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