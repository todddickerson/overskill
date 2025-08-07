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
      
      return { success: false, error: "Failed to upload worker: #{upload_response['error']}" } unless upload_response['success']
      
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
        // Using service worker format for Cloudflare compatibility
        
        addEventListener('fetch', event => {
          event.respondWith(handleRequest(event.request, event))
        })
        
        async function handleRequest(request, event) {
          const url = new URL(request.url)
          let pathname = url.pathname
          const env = event.env || {} // Access environment variables
          
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
            
            <!-- Supabase Client -->
            <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
            
            <script>
              // Make Supabase client constructor globally available
              window.createClient = window.supabase.createClient;
              
              // Create mock Heroicons for compatibility
              window.HeroIcons = {
                PlusIcon: ({ className, ...props }) => React.createElement('svg', {
                  className: className,
                  fill: 'none',
                  stroke: 'currentColor',
                  viewBox: '0 0 24 24',
                  ...props
                }, React.createElement('path', {
                  strokeLinecap: 'round',
                  strokeLinejoin: 'round',
                  strokeWidth: 2,
                  d: 'M12 4v16m8-8H4'
                })),
                TrashIcon: ({ className, ...props }) => React.createElement('svg', {
                  className: className,
                  fill: 'none',
                  stroke: 'currentColor',
                  viewBox: '0 0 24 24',
                  ...props
                }, React.createElement('path', {
                  strokeLinecap: 'round',
                  strokeLinejoin: 'round',
                  strokeWidth: 2,
                  d: 'M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16'
                })),
                CheckIcon: ({ className, ...props }) => React.createElement('svg', {
                  className: className,
                  fill: 'none',
                  stroke: 'currentColor',
                  viewBox: '0 0 24 24',
                  ...props
                }, React.createElement('path', {
                  strokeLinecap: 'round',
                  strokeLinejoin: 'round',
                  strokeWidth: 2,
                  d: 'M5 13l4 4L19 7'
                }))
              };
            </script>
            
            <!-- Main app entry -->
            <script>
              // Simple module system for handling React apps
              window.AppModules = {};
              
              async function loadReactApp() {
                try {
                  // Load the main components we need
                  const [App, supabase, analytics] = await Promise.all([
                    loadComponent('/src/App.tsx'),
                    loadLibrary('/src/lib/supabase.ts'),
                    loadLibrary('/src/lib/analytics.ts')
                  ]);
                  
                  // Make supabase and analytics globally available
                  window.supabase = supabase;
                  window.analytics = analytics;
                  
                  // Render the app
                  const root = ReactDOM.createRoot(document.getElementById('root'));
                  root.render(React.createElement(App));
                  
                } catch (error) {
                  console.error('Failed to load React app:', error);
                  document.getElementById('root').innerHTML = 
                    '<div class="p-4 text-red-500 text-center">' +
                    '<h2 class="text-lg font-bold mb-2">App Loading Error</h2>' +
                    '<p class="mb-2">' + error.message + '</p>' +
                    '<details class="mt-4">' +
                    '<summary class="cursor-pointer text-sm">Show Details</summary>' +
                    '<pre class="text-xs mt-2 p-2 bg-gray-100 text-gray-800 overflow-auto">' + 
                    (error.stack || 'No stack trace available') + 
                    '</pre></details></div>';
                }
              }
              
              async function loadComponent(path) {
                const response = await fetch(path);
                const code = await response.text();
                
                // Simple transformation for React components
                const transformedCode = code
                  // Handle React imports
                  .replace(/import React[^;]*from ['"']react['"];?/g, 'const React = window.React;')
                  .replace(/import \\{[^}]*\\} from ['"']react['"];?/g, 'const {useState, useEffect, useCallback, useMemo} = window.React;')
                  
                  // Handle ReactDOM imports  
                  .replace(/import ReactDOM[^;]*from ['"']react-dom\\/client['"];?/g, 'const ReactDOM = window.ReactDOM;')
                  
                  // Handle Heroicons imports (simplified)
                  .replace(/import \\{([^}]*)\\} from ['"']@heroicons\\/react\\/24\\/outline['"];?/g, 'const PlusIcon = window.HeroIcons.PlusIcon; const TrashIcon = window.HeroIcons.TrashIcon; const CheckIcon = window.HeroIcons.CheckIcon;')
                  
                  // Handle local imports (simplified - assume they're available globally)
                  .replace(/import \\{[^}]*\\} from ['"']\\.\\/lib\\/[^'"]*['"];?/g, '// Local import - handled globally')
                  .replace(/import [^\\s]+ from ['"']\\.\\/[^'"]*['"];?/g, '// Local import - handled globally')
                  
                  // Handle CSS imports
                  .replace(/import ['"'][^'"]*\\.css['"];?/g, '// CSS import - styles already loaded')
                  
                  // Remove type annotations and interfaces
                  .replace(/interface [^{]*\\{[^}]*\\}/g, '')
                  .replace(/: [A-Z][a-zA-Z0-9<>\\[\\]|\\s]*(?=[,);=])/g, '')
                  .replace(/as [A-Z][a-zA-Z0-9]*/g, '')
                  
                  // Convert export default to return statement
                  .replace(/export default function ([A-Z]\\w*)/, 'function $1')
                  .replace(/export default ([A-Z]\\w*)/, 'return $1')
                  .replace(/export default/, 'return');
                
                // Create and execute the component function
                const componentFunction = new Function('React', 'useState', 'useEffect', 'useCallback', 'useMemo', 'supabase', 'analytics', 
                  transformedCode + '\\n; return typeof App !== "undefined" ? App : null;');
                  
                return componentFunction(
                  window.React, 
                  window.React.useState, 
                  window.React.useEffect, 
                  window.React.useCallback, 
                  window.React.useMemo,
                  window.supabase,
                  window.analytics
                );
              }
              
              async function loadLibrary(path) {
                const response = await fetch(path);
                const code = await response.text();
                
                // Handle different library types
                if (path.includes('supabase')) {
                  // Handle Supabase library
                  const transformedCode = code
                    .replace(/import \\{[^}]*\\} from ['"']@supabase\\/supabase-js['"];?/g, 'const { createClient } = window.supabase;')
        .replace(/import\\.meta\\.env\\.([A-Z_]+)/g, '(window.ENV && window.ENV.$1) || ""')
                    .replace(/export const ([^\\s=]+)/g, 'const $1')
                    .replace(/export \\{([^}]*)\\}/g, '// Exports: $1');
                  
                  // Execute and return the supabase client
                  eval(transformedCode);
                  return eval(code.includes('export const supabase') ? 'supabase' : 'createClient');
                  
                } else if (path.includes('analytics')) {
                  // Handle analytics library  
                  const transformedCode = code
        .replace(/import\\.meta\\.env\\.([A-Z_]+)/g, '(window.ENV && window.ENV.$1) || ""')
                    .replace(/export const ([^\\s=]+)/g, 'window.$1')
                    .replace(/class (\\w+)/g, 'window.$1 = class $1')
                    .replace(/: [A-Z][a-zA-Z0-9<>\\[\\]|\\s]*(?=[,);=])/g, '') // Remove types
                    .replace(/interface [^{]*\\{[^}]*\\}/g, ''); // Remove interfaces
                  
                  eval(transformedCode);
                  return window.analytics || {};
                  
                } else {
                  // Generic library handler
                  const transformedCode = code
                    .replace(/export const/g, 'window.LibExport =')
                    .replace(/export \\{[^}]*\\}/g, '// Multiple exports handled')
                    .replace(/: [A-Z][a-zA-Z0-9<>\\[\\]|\\s]*(?=[,);=])/g, '') // Remove types
                    .replace(/interface [^{]*\\{[^}]*\\}/g, ''); // Remove interfaces
                  
                  eval(transformedCode);
                  return window.LibExport || {};
                }
              }
              
              // Start the app
              if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', loadReactApp);
              } else {
                loadReactApp();
              }
            </script>
          `
        }
        
        // Inject environment variables
        function getEnvScript(env) {
          const publicVars = {}
          
          // Collect public environment variables
          const publicKeys = [
            'VITE_APP_ID', 'APP_ID',
            'VITE_SUPABASE_URL', 'SUPABASE_URL',
            'VITE_SUPABASE_ANON_KEY', 'SUPABASE_ANON_KEY',
            'VITE_ENVIRONMENT', 'ENVIRONMENT',
            'APP_NAME', 'OWNER_ID'
          ]
          
          for (const key of publicKeys) {
            if (env[key]) {
              publicVars[key] = env[key]
            }
          }
          
          return `
            <!-- OverSkill Debug Helper -->
            <script src="${ENV['BASE_URL'] || 'http://localhost:3000'}/overskill.js"></script>
            
            <script>
              // Set environment variables (compatible with overskill.js)
              window.ENV = ${JSON.stringify(publicVars)};
              window.__ENV__ = window.ENV; // Backward compatibility
              
              // Make available as import.meta.env
              window.import = window.import || {};
              window.import.meta = window.import.meta || {};
              window.import.meta.env = window.ENV;
            </script>
          `
        }
        
        // Simple TypeScript to JavaScript transformation
        async function transformTypeScript(code) {
          // Remove TypeScript type annotations (basic transformation)  
          // In production, we'd use SWC or esbuild WASM
          let transformedCode = code
            .replace(/: \\w+(\\[\\])?/g, '') // Remove type annotations
            .replace(/as \\w+/g, '') // Remove type assertions  
            .replace(/interface \\w+ \\{[^}]*\\}/g, '') // Remove interfaces
            .replace(/type \\w+ = [^;]+;/g, '') // Remove type aliases
            .replace(/<\\w+>/g, '') // Remove generics
            .replace(/export default/g, 'window.App ='); // Export as global
          
          // Ensure proper component return
          transformedCode += '\\n; return typeof App !== "undefined" ? App : null;';
          return transformedCode;
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