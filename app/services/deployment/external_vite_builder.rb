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
    
    def read_build_output(temp_dir)
      dist_dir = temp_dir.join('dist')
      
      unless Dir.exist?(dist_dir)
        raise "Build output directory not found: #{dist_dir}"
      end
      
      # Find the main JavaScript bundle
      js_files = Dir.glob(dist_dir.join('assets', '*.js'))
      
      if js_files.empty?
        raise "No JavaScript bundles found in build output"
      end
      
      # Read the main bundle (usually index-[hash].js)
      main_js_file = js_files.find { |f| f.include?('index') } || js_files.first
      built_code = File.read(main_js_file)
      
      # Also read the HTML for proper injection later
      html_file = dist_dir.join('index.html')
      @built_html = File.read(html_file) if File.exist?(html_file)
      
      Rails.logger.info "[ExternalViteBuilder] Build successful. Output size: #{built_code.bytesize} bytes"
      
      # Wrap in Worker-compatible format
      wrap_for_worker_deployment(built_code)
    end
    
    def wrap_for_worker_deployment(built_code)
      # Wrap the built code in a Cloudflare Worker template
      # This makes it ready for deployment to Workers with secrets injection
      
      <<~JAVASCRIPT
        // App ID: #{@app.id}
        // Built at: #{Time.current.iso8601}
        // Build mode: #{@build_mode || 'development'}
        
        // User's built React app bundle
        #{built_code}
        
        // Cloudflare Worker fetch handler
        export default {
          async fetch(request, env, ctx) {
            // Environment variables injected at runtime:
            // env.SUPABASE_SECRET_KEY - Platform secret (hidden from user)
            // env.SUPABASE_URL - Platform configuration
            // env.APP_ID - Unique app identifier
            // env.OWNER_ID - Team identifier
            // env.CUSTOM_VARS - User's custom variables
            
            const url = new URL(request.url);
            
            // Initialize app configuration with secrets
            const appConfig = {
              supabaseUrl: env.SUPABASE_URL,
              supabaseKey: env.SUPABASE_SECRET_KEY,
              appId: env.APP_ID,
              ownerId: env.OWNER_ID,
              customVars: JSON.parse(env.CUSTOM_VARS || '{}'),
              environment: env.ENVIRONMENT || 'preview'
            };
            
            // Handle API routes
            if (url.pathname.startsWith('/api/')) {
              return handleApiRequest(request, appConfig, env);
            }
            
            // Serve the React app
            return serveReactApp(request, appConfig);
          }
        };
        
        // Serve the React application
        async function serveReactApp(request, config) {
          const html = `#{@built_html || generate_default_html}`;
          
          // Inject runtime configuration
          const configScript = `
            <script>
              window.APP_CONFIG = {
                supabaseUrl: "${config.supabaseUrl}",
                appId: "${config.appId}",
                environment: "${config.environment}",
                customVars: ${JSON.stringify(config.customVars)}
              };
            </script>
          `;
          
          const finalHtml = html.replace('</head>', configScript + '</head>');
          
          return new Response(finalHtml, {
            headers: {
              'Content-Type': 'text/html',
              'Cache-Control': 'public, max-age=3600'
            }
          });
        }
        
        // Handle API requests with Supabase admin access
        async function handleApiRequest(request, config, env) {
          // This function would handle API routes with server-side Supabase access
          // using the secret service key
          return new Response(JSON.stringify({ 
            message: 'API endpoint',
            appId: config.appId 
          }), {
            headers: { 'Content-Type': 'application/json' }
          });
        }
      JAVASCRIPT
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