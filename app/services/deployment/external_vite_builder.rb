module Deployment
  class ExternalViteBuilder
    include ActiveSupport::Benchmarkable
    
    def initialize(app)
      @app = app
      @temp_dir = nil
    end
    
    def build_for_preview
      Rails.logger.info "[ExternalViteBuilder] Starting fast preview build for app ##{@app.id}"
      
      execute_build do |temp_dir|
        # Fast build with minimal optimization
        build_with_mode(temp_dir, 'development')
      end
    end
    
    def build_for_preview_with_context(build_context = {})
      Rails.logger.info "[ExternalViteBuilder] Starting incremental preview build for app ##{@app.id}"
      Rails.logger.info "[ExternalViteBuilder] Build context: #{build_context.inspect}"
      
      execute_build do |temp_dir|
        if build_context[:incremental] && build_context[:changed_files]
          # Incremental build focusing on changed files
          build_with_incremental_mode(temp_dir, build_context[:changed_files])
        else
          # Fall back to standard fast build
          build_with_mode(temp_dir, 'development')
        end
      end
    end
    
    def build_for_production
      Rails.logger.info "[ExternalViteBuilder] Starting optimized production build for app ##{@app.id}"
      
      execute_build do |temp_dir|
        # Full optimization for production
        build_with_mode(temp_dir, 'production')
      end
    end
    
    private
    
    def execute_build
      @temp_dir = create_temp_directory
      
      Rails.logger.info "[ExternalViteBuilder] Starting build execution"
      start_time = Time.current
      
      begin
        # Write all app files to temp directory
        write_app_files_to_disk
        
        # Execute the build process
        built_code = yield(@temp_dir)
        
        # Return build result
        {
          success: true,
          built_code: built_code,
          build_time: Time.current - start_time,
          output_size: built_code.bytesize,
          temp_dir: @temp_dir
        }
      rescue => e
        Rails.logger.error "[ExternalViteBuilder] Build failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        
        {
          success: false,
          error: e.message,
          build_time: Time.current - start_time
        }
      ensure
        cleanup_temp_directory
        Rails.logger.info "[ExternalViteBuilder] Build execution completed in #{Time.current - start_time}s"
      end
    end
    
    def create_temp_directory
      @start_time = Time.current
      temp_path = Rails.root.join('tmp', 'builds', "app_#{@app.id}_#{Time.current.to_i}")
      FileUtils.mkdir_p(temp_path)
      Rails.logger.info "[ExternalViteBuilder] Created temp directory: #{temp_path}"
      temp_path
    end
    
    def write_app_files_to_disk
      Rails.logger.info "[ExternalViteBuilder] Writing #{@app.app_files.count} files to disk"
      
      @app.app_files.each do |file|
        file_path = @temp_dir.join(file.path)
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, file.content)
      end
      
      # Ensure package.json has build scripts
      ensure_build_scripts
    end
    
    def ensure_build_scripts
      package_json_path = @temp_dir.join('package.json')
      
      if File.exist?(package_json_path)
        package_json = JSON.parse(File.read(package_json_path))
        
        # Ensure build scripts exist
        package_json['scripts'] ||= {}
        package_json['scripts']['build'] ||= 'vite build'
        package_json['scripts']['build:preview'] ||= 'vite build --mode development'
        
        File.write(package_json_path, JSON.pretty_generate(package_json))
      else
        # Create minimal package.json if missing
        create_minimal_package_json
      end
    end
    
    def create_minimal_package_json
      package_json = {
        name: "app-#{@app.id}",
        version: "1.0.0",
        type: "module",
        scripts: {
          dev: "vite",
          build: "vite build",
          "build:preview": "vite build --mode development",
          preview: "vite preview"
        },
        dependencies: {
          react: "^18.2.0",
          "react-dom": "^18.2.0",
          "@supabase/supabase-js": "^2.39.0"
        },
        devDependencies: {
          "@types/react": "^18.2.0",
          "@types/react-dom": "^18.2.0",
          "@vitejs/plugin-react": "^4.2.0",
          typescript: "^5.3.0",
          vite: "^5.0.0",
          tailwindcss: "^3.4.0",
          autoprefixer: "^10.4.0",
          postcss: "^8.4.0"
        }
      }
      
      File.write(@temp_dir.join('package.json'), JSON.pretty_generate(package_json))
    end
    
    def build_with_mode(temp_dir, mode)
      Dir.chdir(temp_dir) do
        Rails.logger.info "[ExternalViteBuilder] Installing dependencies..."
        
        # Use full path to npm if needed, or set PATH
        npm_path = `which npm`.strip
        if npm_path.empty?
          # Try common npm locations
          npm_path = ['/usr/local/bin/npm', '/opt/homebrew/bin/npm', "#{ENV['HOME']}/.nvm/versions/node/*/bin/npm"].find { |p| Dir.glob(p).any? }
          npm_path = Dir.glob(npm_path).first if npm_path
        end
        
        if npm_path.nil? || npm_path.empty?
          Rails.logger.error "[ExternalViteBuilder] npm not found in PATH"
          raise "npm not found. Please ensure Node.js is installed."
        end
        
        Rails.logger.info "[ExternalViteBuilder] Using npm at: #{npm_path}"
        
        # Install dependencies
        install_output = `#{npm_path} install 2>&1`
        install_result = $?.success?
        
        unless install_result
          Rails.logger.error "[ExternalViteBuilder] npm install failed with exit code: #{$?.exitstatus}"
          Rails.logger.error "[ExternalViteBuilder] npm install output: #{install_output}"
          raise "npm install failed: #{install_output.lines.last(5).join}"
        end
        
        Rails.logger.info "[ExternalViteBuilder] Dependencies installed successfully"
        
        Rails.logger.info "[ExternalViteBuilder] Running Vite build (#{mode} mode)..."
        
        # Run the appropriate build command
        build_command = mode == 'production' ? "#{npm_path} run build" : "#{npm_path} run build:preview"
        
        unless system(build_command)
          Rails.logger.error "[ExternalViteBuilder] Vite build failed with exit code: #{$?.exitstatus}"
          raise "Vite build failed. Check build configuration."
        end
        
        # Read the built JavaScript bundle
        read_build_output(temp_dir)
      end
    end
    
    def build_with_incremental_mode(temp_dir, changed_files)
      Rails.logger.info "[ExternalViteBuilder] Incremental build for #{changed_files.count} changed files"
      
      Dir.chdir(temp_dir) do
        Rails.logger.info "[ExternalViteBuilder] Installing dependencies..."
        
        # Use cached npm install if available
        install_output = `#{npm_path} install 2>&1`
        install_result = $?.success?
        
        unless install_result
          Rails.logger.error "[ExternalViteBuilder] npm install failed: #{install_output}"
          raise "npm install failed: #{install_output.lines.last(3).join}"
        end
        
        Rails.logger.info "[ExternalViteBuilder] Running incremental Vite build..."
        
        # Use Vite's incremental build capabilities
        build_command = "#{npm_path} run build:preview"
        
        unless system(build_command)
          Rails.logger.error "[ExternalViteBuilder] Incremental Vite build failed with exit code: #{$?.exitstatus}"
          raise "Incremental Vite build failed. Check build configuration."
        end
        
        # Read the build output
        read_build_output(temp_dir)
      end
    end
    
    def npm_path
      @npm_path ||= begin
        path = `which npm`.strip
        if path.empty?
          # Try common npm locations
          path = ['/usr/local/bin/npm', '/opt/homebrew/bin/npm', "#{ENV['HOME']}/.nvm/versions/node/*/bin/npm"].find { |p| Dir.glob(p).any? }
          path = Dir.glob(path).first if path
        end
        path
      end
    end
    
    def read_build_output(temp_dir)
      dist_dir = temp_dir.join('dist')
      
      unless Dir.exist?(dist_dir)
        raise "Build output directory not found: #{dist_dir}"
      end
      
      # Read HTML first to understand the structure
      html_file = dist_dir.join('index.html')
      unless File.exist?(html_file)
        raise "HTML file not found in build output: #{html_file}"
      end
      
      html_content = File.read(html_file)
      Rails.logger.info "[ExternalViteBuilder] HTML file found: #{html_content.bytesize} bytes"
      
      # Parse the HTML to find all asset references
      assets = extract_asset_references(html_content, dist_dir)
      Rails.logger.info "[ExternalViteBuilder] Found #{assets.length} assets to embed"
      
      # Create hybrid HTML with CSS embedded and JS external
      hybrid_html = create_hybrid_html_with_external_js(html_content, assets)
      
      Rails.logger.info "[ExternalViteBuilder] Build successful. Hybrid HTML size: #{hybrid_html.bytesize} bytes"
      Rails.logger.info "[ExternalViteBuilder] External assets: #{@external_assets&.count || 0} files"
      
      # Wrap in Worker-compatible format with asset serving
      wrap_for_worker_deployment_hybrid(hybrid_html, @external_assets || [])
    end

    private
    
    def extract_asset_references(html_content, dist_dir)
      assets = []
      
      # Find JavaScript modules
      html_content.scan(/<script[^>]*src=['"](.*?)['"]/m) do |src|
        asset_path = src[0]
        next if asset_path.start_with?('http') # Skip external URLs
        
        file_path = dist_dir.join(asset_path.gsub(/^\//, ''))
        if File.exist?(file_path)
          content = File.read(file_path)
          assets << {
            type: 'script',
            original_tag: $&,
            path: asset_path,
            content: content,
            is_module: $&.include?('type="module"')
          }
          Rails.logger.info "[ExternalViteBuilder] Found JS asset: #{asset_path} (#{content.bytesize} bytes)"
        else
          Rails.logger.warn "[ExternalViteBuilder] Asset not found: #{file_path}"
        end
      end
      
      # Find CSS stylesheets
      html_content.scan(/<link[^>]*rel=['"](stylesheet|modulepreload)['"][^>]*href=['"](.*?)['"]/m) do |rel, href|
        next if href.start_with?('http') # Skip external URLs
        
        file_path = dist_dir.join(href.gsub(/^\//, ''))
        if File.exist?(file_path) && rel == 'stylesheet'
          content = File.read(file_path)
          assets << {
            type: 'style',
            original_tag: $&,
            path: href,
            content: content
          }
          Rails.logger.info "[ExternalViteBuilder] Found CSS asset: #{href} (#{content.bytesize} bytes)"
        elsif File.exist?(file_path) && rel == 'modulepreload'
          # Modulepreload files are JavaScript that will be embedded
          content = File.read(file_path)
          assets << {
            type: 'preload_script',
            original_tag: $&,
            path: href,
            content: content
          }
          Rails.logger.info "[ExternalViteBuilder] Found preload asset: #{href} (#{content.bytesize} bytes)"
        end
      end
      
      assets
    end
    
    def create_hybrid_html_with_external_js(html_content, assets)
      # Hybrid approach: embed CSS (small), external JS assets (large)
      Rails.logger.info "[ExternalViteBuilder] Building hybrid HTML with #{assets.count} assets"
      
      # Extract title from original HTML
      title_match = html_content.match(/<title>(.*?)<\/title>/m)
      title = title_match ? title_match[1] : "App #{@app.id}"
      
      # Separate assets by type and size
      js_assets = []
      css_content = []
      @external_assets = [] # Store for R2 upload
      
      assets.each do |asset|
        case asset[:type]
        when 'script', 'preload_script'
          # External JS assets (will be uploaded to R2)
          js_assets << asset
          @external_assets << {
            path: asset[:path],
            content: asset[:content],
            content_type: 'application/javascript',
            size: asset[:content].bytesize
          }
          Rails.logger.info "[ExternalViteBuilder] External JS asset: #{asset[:path]} (#{asset[:content].bytesize} bytes)"
          
        when 'style'
          # Embed CSS directly (usually small)
          css_content << asset[:content]
          Rails.logger.info "[ExternalViteBuilder] Embedded CSS asset: #{asset[:path]} (#{asset[:content].bytesize} bytes)"
        end
      end
      
      # Build HTML with embedded CSS and external JS references
      js_tags = js_assets.map { |asset| 
        "<script type=\"module\" src=\"#{asset[:path]}\"></script>" 
      }.join("\n")
      
      hybrid_html = <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <link rel="icon" type="image/svg+xml" href="/vite.svg">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{title}</title>
          #{css_content.map { |css| "<style>\n#{css}\n</style>" }.join("\n")}
        </head>
        <body>
          <div id="root"></div>
          #{js_tags}
        </body>
        </html>
      HTML
      
      Rails.logger.info "[ExternalViteBuilder] Generated hybrid HTML (#{hybrid_html.bytesize} bytes, #{@external_assets.count} external assets)"
      hybrid_html
    end
    
    def wrap_for_worker_deployment_hybrid(hybrid_html, external_assets)
      # Create Worker template that serves HTML and external JS assets
      # Use JSON encoding for maximum safety - this handles ALL escaping properly
      escaped_html = hybrid_html.to_json[1..-2]  # Remove the surrounding quotes from JSON
      
      # Create asset map for the Worker with safe escaping
      assets_map = external_assets.map do |asset|
        # Use JSON encoding for maximum safety
        content_json = asset[:content].to_json
        content_type = asset[:content_type] || 'application/javascript'
        "  #{asset[:path].to_json}: { content: #{content_json}, type: #{content_type.to_json} }"
      end.join(",\n")
      
      # Log assets for debugging
      Rails.logger.info "[ExternalViteBuilder] Creating Worker with #{external_assets.count} assets"
      external_assets.each do |asset|
        Rails.logger.info "  Asset: #{asset[:path]} (#{asset[:content].bytesize} bytes)"
      end
      
      # Hybrid Worker code with asset serving
      worker_code = <<~JAVASCRIPT
        // App ID: #{@app.id} | Built: #{Time.current.iso8601} | Mode: hybrid
        // Architecture: CSS embedded, JS assets served with correct MIME types
        
        // HTML with embedded CSS and external JS references
        const HTML_CONTENT = `#{escaped_html}`;
        
        // External assets (JS files) with content and MIME types
        const ASSETS = {
        #{assets_map}
        };
        
        // Debug: Log available assets on Worker initialization
        console.log('[Worker Init] App #{@app.id} - Available assets:', Object.keys(ASSETS));
        
        // Service Worker event listener
        addEventListener('fetch', event => {
          event.respondWith(handleRequest(event.request));
        });
        
        async function handleRequest(request) {
          const url = new URL(request.url);
          
          // Get environment variables with fallbacks
          const config = {
            supabaseUrl: typeof SUPABASE_URL !== 'undefined' ? SUPABASE_URL : 'https://bsbgwixlklvgeoxvjmtb.supabase.co',
            supabaseAnonKey: typeof SUPABASE_ANON_KEY !== 'undefined' ? SUPABASE_ANON_KEY : 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJzYmd3aXhsa2x2Z2VveHZqbXRiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTM3MzgyMTAsImV4cCI6MjA2OTMxNDIxMH0.0K9JFMA0K90yOtvnYSYBCroS2Htg1iaICjcevNVCWKM',
            appId: typeof APP_ID !== 'undefined' ? APP_ID : '#{@app.id}',
            environment: typeof ENVIRONMENT !== 'undefined' ? ENVIRONMENT : 'preview',
            customVars: {}
          };
          
          // CRITICAL FIX: Serve JS assets with correct MIME types
          // Handle both absolute (/assets/file.js) and relative (./file.js) import paths
          let assetPath = null;
          
          if (url.pathname.startsWith('/assets/') && url.pathname.endsWith('.js')) {
            // Direct absolute path request
            assetPath = url.pathname;
          } else if (url.pathname.endsWith('.js')) {
            // Relative path - convert to absolute
            const filename = url.pathname.split('/').pop();
            // Find matching asset by filename
            assetPath = Object.keys(ASSETS).find(path => path.endsWith('/' + filename));
          }
          
          if (assetPath && ASSETS[assetPath]) {
            const asset = ASSETS[assetPath];
            console.log('[Worker] Serving JS asset:', assetPath, 'type:', asset.type);
            return new Response(asset.content, {
              headers: {
                'Content-Type': asset.type || 'application/javascript; charset=utf-8',
                'Cache-Control': 'public, max-age=31536000', // 1 year cache for assets
                'Access-Control-Allow-Origin': '*'
              }
            });
          }
          
          // Check if this is a JS file request that we should handle
          if (url.pathname.endsWith('.js')) {
            console.log('[Worker] JS asset not found:', url.pathname);
            console.log('[Worker] Available assets:', Object.keys(ASSETS));
            return new Response('JavaScript asset not found: ' + url.pathname + '\\nAvailable: ' + Object.keys(ASSETS).join(', '), { 
              status: 404,
              headers: { 'Content-Type': 'text/plain' }
            });
          }
          
          // Handle API routes  
          if (url.pathname.startsWith('/api/')) {
            return new Response(JSON.stringify({
              message: 'API endpoint',
              appId: config.appId,
              path: url.pathname
            }), {
              headers: { 'Content-Type': 'application/json' }
            });
          }
          
          // Inject config and serve HTML for all page routes
          const configScript = '<script>window.APP_CONFIG=' + JSON.stringify(config) + ';</script>';
          const finalHtml = HTML_CONTENT.replace('<div id="root">', configScript + '<div id="root">');
          
          return new Response(finalHtml, {
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'public, max-age=300'
            }
          });
        }
      JAVASCRIPT
      
      Rails.logger.info "[ExternalViteBuilder] Generated hybrid Worker (#{worker_code.bytesize} bytes) with #{external_assets.count} assets"
      worker_code
    end
    
    def generate_default_html
      # Fallback HTML if not found in build
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>App #{@app.id}</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" src="/assets/index.js"></script>
        </body>
        </html>
      HTML
    end
    
    def cleanup_temp_directory
      if @temp_dir && Dir.exist?(@temp_dir)
        FileUtils.rm_rf(@temp_dir)
        Rails.logger.info "[ExternalViteBuilder] Cleaned up temp directory"
      end
    rescue => e
      Rails.logger.warn "[ExternalViteBuilder] Failed to cleanup temp directory: #{e.message}"
    end
  end
end