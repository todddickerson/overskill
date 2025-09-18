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

  base_uri "https://api.cloudflare.com/client/v4"

  attr_reader :app, :account_id, :api_token, :namespace_id

  # Cloudflare Workers for Platforms configuration
  WFP_SCRIPT_SIZE_LIMIT = 10_000_000  # 10MB limit for Workers
  PREVIEW_WORKER_PREFIX = "preview-"
  PREVIEW_SUBDOMAIN = ENV["WFP_APPS_DOMAIN"] || "overskill.app"

  def initialize(app)
    @app = app
    @account_id = ENV["CLOUDFLARE_ACCOUNT_ID"]
    @api_token = ENV["CLOUDFLARE_API_TOKEN"]
    # Use the same namespace format as WorkersForPlatformsService
    @namespace_id = "overskill-#{Rails.env}-preview"
  end

  # Deploy preview using Workers for Platforms dispatch architecture
  def deploy_preview(&block)
    start_time = Time.current

    Rails.logger.info "[EdgePreview] Starting preview deployment for app #{app.id}"

    # Skip HMR for deployment to avoid binding errors
    ENV["SKIP_HMR_DEPLOYMENT"] = "true"

    # Report initial progress
    block&.call(0.1)  # 10% - Starting build

    # Get app-specific environment variables for build-time injection
    wfp_service = Deployment::WorkersForPlatformsService.new(app)
    app_env_vars = wfp_service.send(:generate_app_specific_environment_variables, app)

    # Build the bundle using optimized FastBuildService with environment variables
    build_result = FastBuildService.new(app).build_full_bundle(app_env_vars)

    unless build_result[:success]
      Rails.logger.error "[EdgePreview] Build failed: #{build_result[:error]}"
      return {success: false, error: build_result[:error] || "Build failed"}
    end

    # Extract ALL bundles (main + chunks) for modern ES module serving
    # Following lovable template pattern: embed all assets in worker
    all_assets = {}
    total_size = 0

    if build_result[:bundle_files].present?
      build_result[:bundle_files].each do |filename, content|
        # Store all JS/CSS assets with proper paths
        asset_path = filename.start_with?("/") ? filename : "/assets/#{filename}"
        all_assets[asset_path] = content
        total_size += content.bytesize
        Rails.logger.info "[EdgePreview] Adding asset: #{asset_path} (#{content.bytesize} bytes)"
      end
    elsif build_result[:main_bundle].present?
      # Fallback to single bundle if that's all we have
      all_assets["/bundle.js"] = build_result[:main_bundle]
      total_size = build_result[:main_bundle].bytesize
    end

    # Only include index.html from app files if not already in bundle_files
    # The built index.html from Vite has the correct script tags
    if !all_assets["/index.html"] && (index_html = app.app_files.find_by(path: "index.html"))
      Rails.logger.warn "[EdgePreview] Using original index.html from app files - this may have incorrect script tags"
      all_assets["/index.html"] = index_html.content
    end

    Rails.logger.info "[EdgePreview] Total assets: #{all_assets.keys.size}, Total size: #{total_size} bytes"

    # Cloudflare Worker limit is 1MB compressed, use 900KB as safe limit for total
    max_total_size = 900.kilobytes

    if total_size > max_total_size
      Rails.logger.warn "[EdgePreview] Assets too large: #{total_size} bytes, attempting minification"

      # Minify all JavaScript assets
      all_assets.transform_values! do |content|
        if content.include?("function") || content.include?("const ") || content.include?("var ")
          minify_bundle_aggressively(content)
        else
          content
        end
      end

      new_total = all_assets.values.sum(&:bytesize)
      if new_total > max_total_size
        Rails.logger.error "[EdgePreview] Even after minification, assets are #{new_total} bytes (max: #{max_total_size})"
        return {
          success: false,
          error: "Assets too large for Cloudflare Worker (#{(new_total / 1024.0).round}KB > 900KB limit). Consider code splitting or external CDN."
        }
      end

      Rails.logger.info "[EdgePreview] Minification successful: #{total_size} → #{new_total} bytes"
    end

    # Generate worker script with ALL assets embedded
    worker_script = generate_preview_worker_with_assets(all_assets)

    # Final check on complete worker script
    if worker_script.bytesize > WFP_SCRIPT_SIZE_LIMIT
      Rails.logger.error "[EdgePreview] Complete worker script too large: #{worker_script.bytesize} bytes"
      return {success: false, error: "Worker script exceeds 10MB limit even after optimization"}
    end

    # Report progress after build
    block&.call(0.5)  # 50% - Deploying to dispatch namespace

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
      deployment = AppDeployment.create_for_environment!(
        app: app,
        environment: "preview",
        deployment_id: deployment_result[:script_name] || SecureRandom.uuid,
        url: preview_url
      )

      # Track build metrics
      # Use the total_size we calculated earlier
      bundle_size = total_size || all_assets.values.sum(&:bytesize) || 0
      deployment.track_build_metrics(
        bundle_size,
        app.app_files.count
      )
      deployment.update!(worker_script_size_bytes: worker_script.bytesize)

      deploy_time = ((Time.current - start_time) * 1000).round
      Rails.logger.info "[EdgePreview] Preview deployed via dispatch in #{deploy_time}ms to #{preview_url}"

      # Report completion
      block&.call(1.0)  # 100% - Complete

      {
        success: true,
        preview_url: preview_url,
        deployment_id: deployment_result[:script_name],
        deploy_time: deploy_time
      }
    else
      Rails.logger.error "[EdgePreview] Dispatch deployment failed: #{deployment_result[:error]}"
      {success: false, error: deployment_result[:error] || "Deployment failed"}
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

  def minify_bundle_aggressively(bundle)
    # Remove all comments, console.logs, excessive whitespace
    minified = bundle
      .gsub(/\/\*[\s\S]*?\*\//m, "")         # Remove block comments
      .gsub(/\/\/.*$/m, "")                  # Remove line comments
      .gsub(/console\.\w+\([^)]*\);?/m, "")  # Remove all console statements
      .gsub(/debugger;?/m, "")               # Remove debugger statements
      .gsub(/\s+/m, " ")                     # Collapse all whitespace to single spaces
      .gsub(/\s*([{}:;,=+\-*\/<>!&|])\s*/m, '\1')  # Remove spaces around operators
      .strip

    Rails.logger.info "[EdgePreview] Aggressive minification: #{bundle.bytesize} → #{minified.bytesize} bytes (#{((1 - minified.bytesize.to_f / bundle.bytesize) * 100).round}% reduction)"
    minified
  end

  # New method to handle multiple assets (chunks + CSS + main bundle)
  def generate_preview_worker_with_assets(assets_map)
    # Encode all assets as base64 to avoid escaping issues
    encoded_assets = {}
    assets_map.each do |path, content|
      encoded_assets[path] = Base64.strict_encode64(content.force_encoding("UTF-8"))
    end

    <<~JS
      // Multi-Asset Preview Worker for App #{app.id}
      // Supports ES modules, chunks, and proper asset serving
      // Generated at #{Time.current.iso8601}

      // Decode base64 assets to UTF-8
      function decodeBase64ToUTF8(base64) {
        const binaryString = atob(base64);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        return new TextDecoder('utf-8').decode(bytes);
      }

      // All embedded assets (JS chunks, CSS, HTML)
      const ENCODED_ASSETS = #{encoded_assets.to_json};
      const ASSETS = {};

      // Decode all assets on worker startup
      for (const [path, encoded] of Object.entries(ENCODED_ASSETS)) {
        ASSETS[path] = decodeBase64ToUTF8(encoded);
      }

      // Main request handler
      export default {
        async fetch(request, env, ctx) {
          const url = new URL(request.url);
          const path = url.pathname;

          // Serve root as index.html
          if (path === '/' || path === '/index.html') {
            const html = ASSETS['/index.html'] || generateDefaultHTML();
            return new Response(html, {
              headers: {
                'Content-Type': 'text/html; charset=utf-8',
                'Cache-Control': 'no-cache'
              }
            });
          }

          // Check if asset exists
          if (ASSETS[path]) {
            return new Response(ASSETS[path], {
              headers: {
                'Content-Type': getContentType(path),
                'Cache-Control': path.includes('/assets/') ?
                  'public, max-age=31536000, immutable' : 'no-cache'
              }
            });
          }

          // 404 for unknown paths
          return new Response('Not Found', { status: 404 });
        }
      };

      function generateDefaultHTML() {
        // Fallback HTML if index.html not found
        return `<!DOCTYPE html>
          <html>
          <head><title>App Preview</title></head>
          <body>
            <div id="root"></div>
            <script type="module" src="/assets/index.js"></script>
          </body>
          </html>`;
      }

      function getContentType(path) {
        const ext = path.split('.').pop();
        const types = {
          'js': 'application/javascript',
          'mjs': 'application/javascript',
          'jsx': 'application/javascript',
          'ts': 'application/javascript',
          'tsx': 'application/javascript',
          'css': 'text/css',
          'html': 'text/html',
          'json': 'application/json',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'gif': 'image/gif',
          'svg': 'image/svg+xml',
          'woff': 'font/woff',
          'woff2': 'font/woff2',
          'ttf': 'font/ttf',
          'eot': 'application/vnd.ms-fontobject'
        };
        return types[ext] || 'text/plain';
      }
    JS
  end

  # Legacy single-bundle method (kept for backward compatibility)
  def generate_preview_worker(bundle_content)
    # Generate optimized worker script with HMR support
    # Use base64 encoding to avoid escaping issues - force UTF-8 encoding
    encoded_bundle = Base64.strict_encode64(bundle_content.force_encoding("UTF-8"))

    <<~JS
      // Preview Worker for App #{app.id}
      // Generated at #{Time.current.iso8601}
      
      // Decode bundle from base64 to avoid escaping issues
      // Use TextDecoder to properly handle UTF-8 encoding (including emojis)
      function decodeBase64ToUTF8(base64) {
        const binaryString = atob(base64);
        const bytes = new Uint8Array(binaryString.length);
        for (let i = 0; i < binaryString.length; i++) {
          bytes[i] = binaryString.charCodeAt(i);
        }
        return new TextDecoder('utf-8').decode(bytes);
      }
      const BUNDLE = decodeBase64ToUTF8("#{encoded_bundle}");
      const HMR_ENABLED = #{ENV["SKIP_HMR_DEPLOYMENT"] != "true"};
      
      // KV namespace for hot updates
      const FILE_UPDATES = {};
      
      #{(ENV["SKIP_HMR_DEPLOYMENT"] != "true") ? <<~HMR : "// HMR disabled for deployment"}
        // ============================================================
        // DEPRECATED: Durable Object HMR Handler
        // ============================================================
        // DECISION (Sep 2025): We chose ActionCable over Durable Objects for HMR
        //
        // Reasons for using ActionCable instead:
        // 1. NO HIBERNATION DELAYS - ActionCable is always hot (50ms updates)
        //    vs Durable Objects with 2s wake-up delay after idle periods
        // 2. SIMPLER ARCHITECTURE - Users already connected to Rails for editing
        //    No need for additional WebSocket to Cloudflare edge
        // 3. COST-FREE - Uses existing Rails infrastructure
        //    vs ~$5/month per 1000 apps with Durable Objects
        // 4. MORE RELIABLE - Single connection path (Editor → Rails → Preview)
        //    vs complex routing (Editor → Rails → Cloudflare → Durable Object)
        // 5. CONSISTENT UX - Predictable 50ms updates regardless of idle time
        //
        // User Experience Impact:
        // - ActionCable: Always instant (50ms) even after 1hr idle
        // - Durable Objects: 30ms when hot, but 2000ms after hibernation
        //
        // The code below is kept for reference but is NOT USED.
        // See app/channels/app_preview_channel.rb for the actual HMR implementation.
        // ============================================================

        // [DEPRECATED] Durable Object class for HMR WebSocket handling
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
            #{(ENV["SKIP_HMR_DEPLOYMENT"] != "true") ? <<~HMRHANDLER : 'return new Response("HMR disabled", { status: 503 });'}
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
        const appHTML = #{(app.app_files.find_by(path: "index.html")&.content || "No index.html found").to_json};
        
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
          .replace('/src/main.tsx', '/bundle.js')
          .replace('src="/src/main.tsx"', 'src="/bundle.js"')
          .replace('<script type="module" crossorigin', '<script type="module"');
        
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
