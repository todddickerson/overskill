# EdgePreviewService - Instant edge preview deployment to Cloudflare Workers
# Deploys compiled bundles to edge in <2s for instant preview updates
# Part of the Fast Deployment Architecture achieving sub-10s preview updates
#
# Performance targets:
# - Preview deployment: <2s
# - Edge propagation: <500ms globally
# - Worker cold start: <50ms

class EdgePreviewService
  include HTTParty
  
  base_uri 'https://api.cloudflare.com/client/v4'
  
  attr_reader :app, :account_id, :api_token, :namespace_id
  
  # Cloudflare Workers for Platforms configuration
  WFP_SCRIPT_SIZE_LIMIT = 10_000_000  # 10MB limit for Workers
  PREVIEW_WORKER_PREFIX = 'preview-'
  PREVIEW_SUBDOMAIN = ENV['WFP_APPS_DOMAIN'] || 'overskill.app'
  
  def initialize(app)
    @app = app
    @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @api_token = ENV['CLOUDFLARE_API_TOKEN']
    # Use the same namespace format as WorkersForPlatformsService
    @namespace_id = "overskill-#{Rails.env}-preview"
  end

  # Deploy preview using Workers for Platforms dispatch architecture
  def deploy_preview(&block)
    start_time = Time.current
    
    Rails.logger.info "[EdgePreview] Starting preview deployment for app #{app.id}"
    
    # Skip HMR for deployment to avoid binding errors
    ENV['SKIP_HMR_DEPLOYMENT'] = 'true'
    
    # Report initial progress
    block.call(0.1) if block  # 10% - Starting build
    
    # Get app-specific environment variables for build-time injection
    wfp_service = Deployment::WorkersForPlatformsService.new(app)
    app_env_vars = wfp_service.send(:generate_app_specific_environment_variables, app)
    
    # Build the bundle using optimized FastBuildService with environment variables
    build_result = FastBuildService.new(app).build_full_bundle(app_env_vars)
    
    unless build_result[:success]
      Rails.logger.error "[EdgePreview] Build failed: #{build_result[:error]}"
      return { success: false, error: build_result[:error] || "Build failed" }
    end
    
    # Generate worker script with the Vite bundle
    worker_script = generate_preview_worker(build_result[:main_bundle] || build_result[:bundle_files].values.first)
    
    # Check script size
    if worker_script.bytesize > WFP_SCRIPT_SIZE_LIMIT
      Rails.logger.error "[EdgePreview] Worker script too large: #{worker_script.bytesize} bytes"
      return { success: false, error: "Bundle exceeds 10MB limit" }
    end
    
    # Report progress after build
    block.call(0.5) if block  # 50% - Deploying to dispatch namespace
    
    # Deploy to dispatch namespace using WorkersForPlatformsService
    wfp_service = Deployment::WorkersForPlatformsService.new(app)
    
    deployment_result = wfp_service.deploy_app(
      worker_script,
      environment: :preview,
      metadata: {
        app_id: app.id,
        version: app.app_versions.maximum(:id) || 1,
        deployed_at: Time.current.iso8601
      }
    )
    
    if deployment_result[:success]
      # Use the URL from dispatch deployment (preview-{obfuscated_id}.overskill.app)
      preview_url = deployment_result[:url]
      
      # Update app with preview URL
      app.update!(
        preview_url: preview_url
      )
      
      # Track deployment in database
      AppDeployment.create_for_environment!(
        app: app,
        environment: 'preview',
        deployment_id: deployment_result[:script_name] || SecureRandom.uuid,
        url: preview_url
      )
      
      deploy_time = ((Time.current - start_time) * 1000).round
      Rails.logger.info "[EdgePreview] Preview deployed via dispatch in #{deploy_time}ms to #{preview_url}"
      
      # Report completion
      block.call(1.0) if block  # 100% - Complete
      
      {
        success: true,
        preview_url: preview_url,
        deployment_id: deployment_result[:script_name],
        deploy_time: deploy_time
      }
    else
      Rails.logger.error "[EdgePreview] Dispatch deployment failed: #{deployment_result[:error]}"
      { success: false, error: deployment_result[:error] || "Deployment failed" }
    end
  end

  # Update single file by redeploying to dispatch namespace
  def update_file(file_path, content)
    Rails.logger.info "[EdgePreview] Updating file #{file_path} via redeploy"
    
    # For dispatch architecture, we need to rebuild and redeploy
    # Individual file updates would require KV storage setup
    # For now, trigger a full redeploy which is still very fast
    deploy_preview
  end


  private


  def generate_preview_worker(bundle_content)
    # Generate optimized worker script with HMR support
    # Use base64 encoding to avoid escaping issues
    encoded_bundle = Base64.strict_encode64(bundle_content)
    
    <<~JS
      // Preview Worker for App #{app.id}
      // Generated at #{Time.current.iso8601}
      
      // Decode bundle from base64 to avoid escaping issues
      const BUNDLE = atob("#{encoded_bundle}");
      const HMR_ENABLED = #{ENV['SKIP_HMR_DEPLOYMENT'] != 'true'};
      
      // KV namespace for hot updates
      const FILE_UPDATES = {};
      
      #{ENV['SKIP_HMR_DEPLOYMENT'] != 'true' ? <<~HMR : '// HMR disabled for deployment'}
      // Durable Object class for HMR WebSocket handling
      export class HMRHandler {
        constructor(state, env) {
          this.state = state;
          this.env = env;
          this.sockets = new Set();
        }
        
        async fetch(request) {
          const upgradeHeader = request.headers.get('Upgrade');
          if (upgradeHeader !== 'websocket') {
            return new Response('Expected websocket', { status: 400 });
          }
          
          const [client, server] = Object.values(new WebSocketPair());
          this.handleSession(server);
          
          return new Response(null, {
            status: 101,
            webSocket: client,
          });
        }
        
        handleSession(socket) {
          socket.accept();
          this.sockets.add(socket);
          
          socket.addEventListener('message', async (event) => {
            const data = JSON.parse(event.data);
            
            if (data.type === 'file_update') {
              // Store update in memory
              FILE_UPDATES[data.path] = data.content;
              
              // Broadcast to all connected clients
              this.broadcast({
                type: 'hmr_update',
                path: data.path,
                content: data.content
              });
            }
          });
          
          socket.addEventListener('close', () => {
            this.sockets.delete(socket);
          });
        }
        
        broadcast(message) {
          const data = JSON.stringify(message);
          this.sockets.forEach(socket => {
            try {
              socket.send(data);
            } catch (e) {
              // Socket might be closing
              this.sockets.delete(socket);
            }
          });
        }
      }
      HMR
      
      // Main request handler
      export default {
        async fetch(request, env, ctx) {
          const url = new URL(request.url);
          
          // Handle WebSocket upgrade for HMR (only if enabled)
          if (url.pathname === '/hmr' && HMR_ENABLED) {
            #{ENV['SKIP_HMR_DEPLOYMENT'] != 'true' ? <<~HMRHANDLER : 'return new Response("HMR disabled", { status: 503 });'}
            if (!env.DO_HMR) {
              return new Response('HMR not configured', { status: 503 });
            }
            const handler = new HMRHandler(env.DO_HMR.get(env.DO_HMR.idFromName('hmr-session')));
            return handler.fetch(request);
            HMRHANDLER
          }
          
          // Handle file requests
          if (url.pathname.startsWith('/src/')) {
            const filePath = url.pathname.substring(1);
            
            // Check for hot updates first
            if (FILE_UPDATES[filePath]) {
              return new Response(FILE_UPDATES[filePath], {
                headers: {
                  'Content-Type': getContentType(filePath),
                  'Cache-Control': 'no-cache'
                }
              });
            }
          }
          
          // Serve the main bundle
          if (url.pathname === '/' || url.pathname === '/index.html') {
            return new Response(generateHTML(), {
              headers: {
                'Content-Type': 'text/html',
                'Cache-Control': 'no-cache'
              }
            });
          }
          
          // Serve the JavaScript bundle
          if (url.pathname === '/bundle.js') {
            return new Response(BUNDLE, {
              headers: {
                'Content-Type': 'application/javascript',
                'Cache-Control': 'no-cache'
              }
            });
          }
          
          // 404 for unknown paths
          return new Response('Not Found', { status: 404 });
        }
      };
      
      function generateHTML() {
        // Use the actual app's index.html with HMR integration
        const appHTML = #{(app.app_files.find_by(path: 'index.html')&.content || 'No index.html found').to_json};
        
        // Insert HMR client before closing head tag and update script src
        // Use server-side environment configuration for HMR
        const hmrEnabled = #{Rails.env.development?};
        const htmlWithHMR = appHTML
          .replace('</head>', 
            '<script>' +
            '  // HMR Client - configured from server environment' +
            '  if (' + hmrEnabled + ') {' +
            '    const ws = new WebSocket("wss://" + window.location.host + "/hmr");' +
            '    ws.onopen = () => console.log("[HMR] Connected");' +
            '    ws.onmessage = (event) => {' +
            '      const data = JSON.parse(event.data);' +
            '      if (data.type === "hmr_update") {' +
            '        console.log("[HMR] Updating", data.path);' +
            '        window.__hmrUpdate && window.__hmrUpdate(data);' +
            '      }' +
            '    };' +
            '    ws.onerror = (error) => console.log("[HMR] Error:", error);' +
            '  } else {' +
            '    console.log("[HMR] Disabled in production");' +
            '  }' +
            '</script>' +
            '</head>')
          .replace('/src/main.tsx', '/bundle.js');
        
        return htmlWithHMR;
      }
      
      function getContentType(path) {
        const ext = path.split('.').pop();
        const types = {
          'js': 'application/javascript',
          'jsx': 'application/javascript',
          'ts': 'application/javascript',
          'tsx': 'application/javascript',
          'css': 'text/css',
          'html': 'text/html',
          'json': 'application/json',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'svg': 'image/svg+xml'
        };
        return types[ext] || 'text/plain';
      }
    JS
  end

end