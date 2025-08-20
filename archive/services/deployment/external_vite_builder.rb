module Deployment
  class ExternalViteBuilder
    include ActiveSupport::Benchmarkable
    
    # Class-level mutex to prevent concurrent chdir operations
    BUILD_MUTEX = Mutex.new
    
    def initialize(app)
      @app = app
      @temp_dir = nil
    end
    
    def build_for_preview
      Rails.logger.info "[ExternalViteBuilder] Starting fast preview build for app ##{@app.id}"
      
      execute_build do |temp_dir|
        # Fast build with minimal optimization
        built_files = build_with_mode(temp_dir, 'development')
        
        # Return the actual built files instead of wrapped code
        built_files
      end
    end
    
    def build_for_preview_with_r2
      Rails.logger.info "[ExternalViteBuilder] Starting preview build with R2 asset offloading for app ##{@app.id}"
      
      begin
        # Run the actual Vite build and get built files
        build_result = build_for_preview
        return build_result unless build_result[:success]
        
        # The build_for_preview returns the actual built files as a hash
        built_files = build_result[:built_code]
        
        # Separate large assets from code files  
        code_files = {}
        large_assets = {}
        
        built_files.each do |path, content|
          # Images and media go to R2 if >50KB
          if path.match?(/\.(jpg|jpeg|png|gif|webp|mp4|webm|pdf|zip)$/i) && content.bytesize > 50_000
            large_assets[path] = content
          else
            # Everything else stays in Worker (HTML, JS, CSS, small images)
            code_files[path] = content
          end
        end
        
        # Upload large assets to R2
        r2_asset_urls = {}
        if large_assets.any?
          r2_service = Deployment::R2AssetService.new(@app)
          
          # Format for R2AssetService
          assets_for_upload = {}
          large_assets.each do |path, content|
            assets_for_upload[path] = {
              content: content,
              binary: true,
              content_type: detect_content_type(path)
            }
          end
          
          r2_result = r2_service.upload_assets(assets_for_upload)
          r2_asset_urls = r2_result[:asset_urls] || {}
          
          Rails.logger.info "[ExternalViteBuilder] Uploaded #{large_assets.count} large assets to R2"
        end
        
        Rails.logger.info "[ExternalViteBuilder] Build complete: #{code_files.count} code files, #{large_assets.count} R2 assets"
        
        {
          success: true,
          built_code: code_files,
          r2_asset_urls: r2_asset_urls,
          size_stats: {
            code_files: code_files.count,
            r2_assets: large_assets.count,
            total_code_size: code_files.values.sum(&:bytesize),
            total_r2_size: large_assets.values.sum(&:bytesize)
          }
        }
      rescue => e
        Rails.logger.error "[ExternalViteBuilder] R2 build failed: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    def get_index_html_content
      # Get the index.html from app files and fix script references
      index_file = @app.app_files.find_by(path: 'index.html')
      html_content = index_file&.content || default_html_template
      
      # Replace development script references with built script
      # Change /src/main.tsx to /index.js for the Worker
      html_content = html_content.gsub('/src/main.tsx', '/index.js')
      
      html_content
    end
    
    def default_html_template
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <title>App</title>
        </head>
        <body>
          <div id="root"></div>
          <script type="module" src="/index.js"></script>
        </body>
        </html>
      HTML
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
        
        # Validate component imports before building (skip validation for certain UI library files)
        if should_validate_imports?
          validator = Validation::ComponentImportValidator.new(@app)
          unless validator.validate!
            # Filter out errors from UI library files which may have complex import patterns
            real_errors = validator.errors.reject { |e| e[:file].include?('components/ui/') }
            if real_errors.any?
              error_messages = real_errors.map { |e| "#{e[:file]}: #{e[:message]}" }
              raise "Component import validation failed:\n#{error_messages.join("\n")}"
            else
              Rails.logger.info "[ExternalViteBuilder] Skipping UI library import validation errors"
            end
          end
        end
        
        # Execute the build process
        built_code = yield(@temp_dir)
        
        # Return build result
        {
          success: true,
          built_code: built_code,
          build_time: Time.current - start_time,
          output_size: built_code.is_a?(Hash) ? built_code.values.sum(&:bytesize) : built_code.bytesize,
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
      # Include process ID and random string to ensure uniqueness even with concurrent builds
      unique_id = "#{Process.pid}_#{SecureRandom.hex(4)}"
      temp_path = Rails.root.join('tmp', 'builds', "app_#{@app.id}_#{Time.current.to_i}_#{unique_id}")
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
          "@vitejs/plugin-react-swc": "^3.11.0",
          typescript: "^5.3.0",
          vite: "^5.0.0",
          tailwindcss: "^3.4.0",
          autoprefixer: "^10.4.0",
          postcss: "^8.4.0"
        }
      }
      
      File.write(@temp_dir.join('package.json'), JSON.pretty_generate(package_json))
    end
    
    def build_vite_environment_variables
      # Vite requires variables to be prefixed with VITE_ to be available in client code
      vite_env = {}
      
      # App-specific variables that Vite can access
      vite_env['VITE_APP_ID'] = @app.id.to_s
      vite_env['VITE_ENVIRONMENT'] = Rails.env
      
      # Supabase configuration (public keys safe for client-side)
      vite_env['VITE_SUPABASE_URL'] = ENV['SUPABASE_URL'] || 'https://your-project.supabase.co'
      vite_env['VITE_SUPABASE_ANON_KEY'] = ENV['SUPABASE_ANON_KEY'] || 'your-anon-key'
      
      # Add user's custom environment variables with VITE_ prefix if they don't already have it
      if @app.respond_to?(:app_env_vars)
        begin
          user_vars = if @app.app_env_vars.column_names.include?('var_type')
            @app.app_env_vars.where(var_type: ['user_defined', 'system_default']).pluck(:key, :value).to_h
          else
            @app.app_env_vars.pluck(:key, :value).to_h
          end
          
          user_vars.each do |key, value|
            # Only include non-secret variables (no API keys, tokens, etc.)
            unless key.downcase.include?('secret') || key.downcase.include?('key') || key.downcase.include?('token')
              vite_key = key.start_with?('VITE_') ? key : "VITE_#{key}"
              vite_env[vite_key] = value
            end
          end
        rescue => e
          Rails.logger.warn "[ExternalViteBuilder] Could not load user env vars: #{e.message}"
        end
      end
      
      Rails.logger.info "[ExternalViteBuilder] Setting Vite environment variables: #{vite_env.keys.join(', ')}"
      vite_env
    end
    
    def build_with_mode(temp_dir, mode)
      # Use absolute paths instead of chdir to avoid conflicts
      Rails.logger.info "[ExternalViteBuilder] Building in directory: #{temp_dir}"
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
      
      # Install dependencies using --prefix to specify directory
      install_output = `cd "#{temp_dir}" && #{npm_path} install 2>&1`
      install_result = $?.success?
        
      unless install_result
        Rails.logger.error "[ExternalViteBuilder] npm install failed with exit code: #{$?.exitstatus}"
        Rails.logger.error "[ExternalViteBuilder] npm install output: #{install_output}"
        raise "npm install failed: #{install_output.lines.last(5).join}"
      end
      
      Rails.logger.info "[ExternalViteBuilder] Dependencies installed successfully"
      
      Rails.logger.info "[ExternalViteBuilder] Running Vite build (#{mode} mode)..."
      
      # Set up environment variables for Vite build
      vite_env = build_vite_environment_variables
      
      # Run the appropriate build command with cd instead of chdir
      build_command = mode == 'production' ? "#{npm_path} run build" : "#{npm_path} run build:preview"
      full_command = "cd \"#{temp_dir}\" && #{build_command}"
      
      # Capture both stdout and stderr for better error reporting
      require 'open3'
      stdout, stderr, status = Open3.capture3(vite_env, full_command)
      
      unless status.success?
        Rails.logger.error "[ExternalViteBuilder] Vite build failed with exit code: #{status.exitstatus}"
        Rails.logger.error "[ExternalViteBuilder] Build stdout: #{stdout}"
        Rails.logger.error "[ExternalViteBuilder] Build stderr: #{stderr}"
        raise "Vite build failed: #{stderr.presence || stdout}"
      end
      
      # Read the built JavaScript bundle
      read_build_output(temp_dir)
    end
    
    def build_with_incremental_mode(temp_dir, changed_files)
      Rails.logger.info "[ExternalViteBuilder] Incremental build for #{changed_files.count} changed files"
      
      Rails.logger.info "[ExternalViteBuilder] Installing dependencies..."
      
      # Get npm path
      npm_path = `which npm`.strip
      if npm_path.empty?
        npm_path = ['/usr/local/bin/npm', '/opt/homebrew/bin/npm'].find { |p| File.exist?(p) }
      end
      
      # Use cached npm install if available
      install_output = `cd "#{temp_dir}" && #{npm_path} install 2>&1`
      install_result = $?.success?
        
      unless install_result
        Rails.logger.error "[ExternalViteBuilder] npm install failed: #{install_output}"
        raise "npm install failed: #{install_output.lines.last(3).join}"
      end
      
      Rails.logger.info "[ExternalViteBuilder] Running incremental Vite build..."
      
      # Use Vite's incremental build capabilities with cd instead of chdir
      build_command = "#{npm_path} run build:preview"
      full_command = "cd \"#{temp_dir}\" && #{build_command}"
      
      # Capture both stdout and stderr for better error reporting
      require 'open3'
      stdout, stderr, status = Open3.capture3(full_command)
      
      unless status.success?
        Rails.logger.error "[ExternalViteBuilder] Incremental Vite build failed with exit code: #{status.exitstatus}"
        Rails.logger.error "[ExternalViteBuilder] Build stdout: #{stdout}"
        Rails.logger.error "[ExternalViteBuilder] Build stderr: #{stderr}"
        raise "Incremental Vite build failed: #{stderr.presence || stdout}"
      end
      
      # Read the build output
      read_build_output(temp_dir)
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
    
    def should_validate_imports?
      # Always validate in production/staging builds
      return true if Rails.env.production? || Rails.env.staging?
      
      # In development, check if validation is explicitly enabled
      ENV['VALIDATE_COMPONENT_IMPORTS'].present? || @app.status == 'generating'
    end
    
    def read_build_output(temp_dir)
      dist_dir = temp_dir.join('dist')
      
      unless Dir.exist?(dist_dir)
        raise "Build output directory not found: #{dist_dir}"
      end
      
      # Collect all built files from dist/
      built_files = {}
      
      Dir.glob(dist_dir.join('**/*')).each do |file_path|
        next if File.directory?(file_path)
        
        # Get relative path from dist/
        relative_path = file_path.sub(dist_dir.to_s + '/', '')
        content = File.read(file_path)
        built_files[relative_path] = content
        
        Rails.logger.info "[ExternalViteBuilder] Built file: #{relative_path} (#{(content.bytesize / 1024.0).round(1)} KB)"
      end
      
      Rails.logger.info "[ExternalViteBuilder] Build successful. Total files: #{built_files.count}"
      
      # Return the actual built files
      built_files
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
      
      # Get app version info for health checks
      app_version_id = @app.app_versions.last&.id || 'unknown'
      app_version_number = @app.app_versions.last&.version_number || '1.0.0'
      
      # Hybrid Worker code with asset serving
      worker_code = <<~JAVASCRIPT
        // App ID: #{@app.id} | Built: #{Time.current.iso8601} | Mode: hybrid
        // Architecture: CSS embedded, JS assets served with correct MIME types
        
        // Deployment metadata
        const DEPLOYMENT_INFO = {
          appId: '#{@app.id}',
          versionId: '#{app_version_id}',
          versionNumber: '#{app_version_number}',
          deployedAt: '#{Time.current.iso8601}',
          buildMode: 'hybrid',
          assetCount: #{external_assets.count}
        };
        
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
            showOverskillBadge: #{@app.show_overskill_badge.nil? ? 'true' : @app.show_overskill_badge},
            remixUrl: '#{@app.remix_url}',
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
          
          // Handle health check endpoint for deployment verification
          if (url.pathname === '/_health' || url.pathname === '/api/health') {
            return new Response(JSON.stringify({
              status: 'healthy',
              deployment: DEPLOYMENT_INFO,
              timestamp: new Date().toISOString(),
              config: {
                appId: config.appId,
                environment: config.environment,
                hasSupabase: !!config.supabaseUrl
              }
            }), {
              headers: { 
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache, no-store, must-revalidate'
              }
            });
          }
          
          // Handle deployment info endpoint
          if (url.pathname === '/_deployment' || url.pathname === '/api/deployment') {
            return new Response(JSON.stringify(DEPLOYMENT_INFO), {
              headers: { 
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache, no-store, must-revalidate'
              }
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
          // CRITICAL: Inject env vars as both window.APP_CONFIG and window.env for compatibility
          const envScript = `
            <script>
              // Inject environment variables for the app
              window.APP_CONFIG = ${JSON.stringify(config)};
              window.env = {
                VITE_SUPABASE_URL: '${config.supabaseUrl}',
                VITE_SUPABASE_ANON_KEY: '${config.supabaseAnonKey}',
                VITE_APP_ID: '${config.appId}',
                VITE_OWNER_ID: '${config.appId}',
                VITE_ENVIRONMENT: '${config.environment}'
              };
              // Also make them available on import.meta.env for runtime access
              if (typeof window !== 'undefined' && !window.import) {
                window.import = { meta: { env: window.env } };
              }
            </script>
          `;
          const finalHtml = HTML_CONTENT.replace('</head>', envScript + '</head>');
          
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
    
    def detect_content_type(path)
      ext = File.extname(path).downcase
      case ext
      when '.html' then 'text/html'
      when '.js', '.mjs' then 'application/javascript'
      when '.css' then 'text/css'
      when '.json' then 'application/json'
      when '.jpg', '.jpeg' then 'image/jpeg'
      when '.png' then 'image/png'
      when '.gif' then 'image/gif'
      when '.svg' then 'image/svg+xml'
      when '.woff' then 'font/woff'
      when '.woff2' then 'font/woff2'
      else 'text/plain'
      end
    end
  end
end