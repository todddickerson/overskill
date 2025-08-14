module Deployment
  # Manages secrets for Cloudflare Workers using native Cloudflare APIs
  # Keeps infrastructure lean - just Cloudflare + Supabase
  class CloudflareSecretService
    include HTTParty
    base_uri 'https://api.cloudflare.com/client/v4'
    
    def initialize(app)
      @app = app
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @api_token = ENV['CLOUDFLARE_API_TOKEN']
      
      self.class.headers 'Authorization' => "Bearer #{@api_token}" if @api_token
    end
    
    # Deploy app with proper secret management
    def deploy_with_secrets!
      worker_name = "app-#{@app.id}"
      
      # Step 1: Generate wrangler.toml with public vars only
      wrangler_config = generate_wrangler_config
      
      # Step 2: Upload worker script
      worker_script = generate_lean_worker_script
      upload_worker(worker_name, worker_script)
      
      # Step 3: Set secrets via API (not in code)
      set_worker_secrets(worker_name)
      
      # Step 4: Configure routes
      configure_routes(worker_name)
      
      { 
        success: true, 
        url: "https://#{@app.subdomain}.overskill.app",
        message: "Deployed with secure secrets"
      }
    rescue => e
      { success: false, error: e.message }
    end
    
    private
    
    def generate_wrangler_config
      # Only public vars go in wrangler.toml
      # Secrets are set separately via API
      <<~TOML
        name = "app-#{@app.id}"
        main = "worker.js"
        compatibility_date = "2024-01-01"
        
        [vars]
        # Public environment variables (safe for client)
        APP_ID = "#{@app.id}"
        APP_NAME = "#{@app.name}"
        ENVIRONMENT = "production"
        
        # Public API endpoints (not keys)
        SUPABASE_URL = "#{supabase_url_for_app}"
        SUPABASE_ANON_KEY = "#{supabase_anon_key_for_app}"
        
        # R2 bucket bindings for file storage
        [[r2_buckets]]
        binding = "STORAGE"
        bucket_name = "overskill-apps"
        
        # KV namespace for session storage
        [[kv_namespaces]]
        binding = "SESSIONS"
        id = "#{kv_namespace_id}"
      TOML
    end
    
    def generate_lean_worker_script
      <<~JAVASCRIPT
        // Lean Cloudflare Worker - No external dependencies
        // Just Cloudflare services + Supabase
        
        export default {
          async fetch(request, env, ctx) {
            const url = new URL(request.url);
            const path = url.pathname;
            
            // API routes with secret access
            if (path.startsWith('/api/')) {
              return handleSecureApi(request, env, path);
            }
            
            // Serve app files from R2
            return serveFromR2(request, env);
          }
        };
        
        async function handleSecureApi(request, env, path) {
          // Database operations using Supabase
          if (path.startsWith('/api/db/')) {
            // Use SERVICE_KEY from secrets (never exposed)
            const serviceKey = env.SUPABASE_SERVICE_KEY;
            if (!serviceKey) {
              return new Response('Database not configured', { status: 503 });
            }
            
            // Proxy to Supabase with service key
            const supabaseUrl = env.SUPABASE_URL;
            const targetPath = path.replace('/api/db', '/rest/v1');
            const targetUrl = supabaseUrl + targetPath + url.search;
            
            const proxyRequest = new Request(targetUrl, request);
            proxyRequest.headers.set('apikey', serviceKey);
            proxyRequest.headers.set('Authorization', `Bearer ${serviceKey}`);
            
            return fetch(proxyRequest);
          }
          
          // Authentication endpoints
          if (path === '/api/auth/google') {
            const clientSecret = env.GOOGLE_CLIENT_SECRET;
            if (!clientSecret) {
              return new Response('OAuth not configured', { status: 503 });
            }
            return handleGoogleOAuth(request, env.GOOGLE_CLIENT_ID, clientSecret);
          }
          
          // Session management using KV
          if (path === '/api/session') {
            return handleSession(request, env.SESSIONS);
          }
          
          // File uploads to R2
          if (path === '/api/upload') {
            return handleUpload(request, env.STORAGE);
          }
          
          return new Response('Not found', { status: 404 });
        }
        
        async function serveFromR2(request, env) {
          const url = new URL(request.url);
          let key = url.pathname.slice(1);
          
          // Default to index.html
          if (!key || !key.includes('.')) {
            key = 'index.html';
          }
          
          // Try R2 first (for built/uploaded files)
          const object = await env.STORAGE.get(`apps/${env.APP_ID}/${key}`);
          if (object) {
            const headers = new Headers();
            object.writeHttpMetadata(headers);
            headers.set('etag', object.httpEtag);
            headers.set('cache-control', getCacheControl(key));
            
            return new Response(object.body, { headers });
          }
          
          // Fallback to embedded files
          const embeddedFile = getEmbeddedFile(key);
          if (embeddedFile) {
            return new Response(embeddedFile, {
              headers: {
                'content-type': getContentType(key),
                'cache-control': getCacheControl(key)
              }
            });
          }
          
          return new Response('Not found', { status: 404 });
        }
        
        async function handleSession(request, kvStore) {
          const sessionId = getCookie(request, 'session_id');
          
          if (request.method === 'GET') {
            if (!sessionId) return new Response('{}', { status: 200 });
            
            const session = await kvStore.get(sessionId);
            return new Response(session || '{}', {
              headers: { 'content-type': 'application/json' }
            });
          }
          
          if (request.method === 'POST') {
            const newSessionId = crypto.randomUUID();
            const data = await request.json();
            
            await kvStore.put(newSessionId, JSON.stringify(data), {
              expirationTtl: 86400 * 7 // 7 days
            });
            
            return new Response(JSON.stringify({ sessionId: newSessionId }), {
              headers: {
                'content-type': 'application/json',
                'set-cookie': `session_id=${newSessionId}; Path=/; HttpOnly; Secure; SameSite=Strict`
              }
            });
          }
          
          return new Response('Method not allowed', { status: 405 });
        }
        
        async function handleUpload(request, r2Bucket) {
          if (request.method !== 'POST') {
            return new Response('Method not allowed', { status: 405 });
          }
          
          const formData = await request.formData();
          const file = formData.get('file');
          
          if (!file) {
            return new Response('No file provided', { status: 400 });
          }
          
          const key = `uploads/${crypto.randomUUID()}-${file.name}`;
          await r2Bucket.put(key, file.stream());
          
          return new Response(JSON.stringify({ 
            url: `/files/${key}`,
            key: key 
          }), {
            headers: { 'content-type': 'application/json' }
          });
        }
        
        // Embedded files for fast preview
        function getEmbeddedFile(path) {
          const files = #{embedded_files_json};
          return files[path];
        }
        
        function getContentType(path) {
          const ext = path.split('.').pop();
          const types = {
            'html': 'text/html',
            'js': 'application/javascript',
            'css': 'text/css',
            'json': 'application/json',
            'png': 'image/png',
            'jpg': 'image/jpeg',
            'svg': 'image/svg+xml'
          };
          return types[ext] || 'text/plain';
        }
        
        function getCacheControl(path) {
          if (path.includes('.') && path.match(/\.[a-f0-9]{8}\./)) {
            return 'public, max-age=31536000, immutable';
          }
          if (path.endsWith('.html')) {
            return 'no-cache';
          }
          return 'public, max-age=3600';
        }
        
        function getCookie(request, name) {
          const cookies = request.headers.get('cookie');
          if (!cookies) return null;
          
          const match = cookies.match(new RegExp(`${name}=([^;]+)`));
          return match ? match[1] : null;
        }
      JAVASCRIPT
    end
    
    def set_worker_secrets(worker_name)
      # Set secrets via Cloudflare API (not exposed in code)
      secrets = {
        'SUPABASE_SERVICE_KEY' => supabase_service_key_for_app,
        'GOOGLE_CLIENT_SECRET' => ENV['GOOGLE_CLIENT_SECRET'],
        'STRIPE_SECRET_KEY' => ENV['STRIPE_SECRET_KEY'],
        'OPENAI_API_KEY' => ENV['OPENAI_API_KEY']
      }
      
      secrets.each do |key, value|
        next unless value.present?
        
        # Use Cloudflare API to set secret
        response = self.class.put(
          "/accounts/#{@account_id}/workers/scripts/#{worker_name}/secrets",
          body: { 
            name: key,
            text: value,
            type: 'secret_text'
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
        
        Rails.logger.info "Set secret #{key} for worker #{worker_name}"
      end
    end
    
    def upload_worker(worker_name, script)
      # Upload worker script
      response = self.class.put(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        headers: { 'Content-Type' => 'application/javascript' },
        body: script
      )
      
      raise "Failed to upload worker" unless response.success?
    end
    
    def configure_routes(worker_name)
      # Set up custom domain routing
      subdomain = @app.subdomain
      route_pattern = "#{subdomain}.overskill.app/*"
      
      self.class.post(
        "/zones/#{ENV['CLOUDFLARE_ZONE_ID']}/workers/routes",
        body: {
          pattern: route_pattern,
          script: worker_name
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    end
    
    def supabase_url_for_app
      # Get the Supabase URL for this app's shard
      shard = @app.database_shard || DatabaseShard.current_shard
      shard.supabase_url
    end
    
    def supabase_anon_key_for_app
      # Public anon key (safe to expose, RLS protects data)
      shard = @app.database_shard || DatabaseShard.current_shard
      shard.supabase_anon_key
    end
    
    def supabase_service_key_for_app
      # Service key (NEVER expose to client)
      shard = @app.database_shard || DatabaseShard.current_shard
      shard.supabase_service_key
    end
    
    def kv_namespace_id
      # Get or create KV namespace for this app
      ENV['CLOUDFLARE_KV_NAMESPACE_ID'] || create_kv_namespace
    end
    
    def create_kv_namespace
      response = self.class.post(
        "/accounts/#{@account_id}/storage/kv/namespaces",
        body: { title: "overskill-sessions" }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      
      response.parsed_response['result']['id']
    end
    
    def embedded_files_json
      # Embed app files for fast preview
      files = {}
      @app.app_files.each do |file|
        files[file.path] = file.content
      end
      JSON.generate(files)
    end
  end
end