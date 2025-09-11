# FastBuildService - Optimized for instant preview deployments
# Uses esbuild directly for preview builds to bypass PostCSS/Vite complexity
# Falls back to Vite for production builds when full optimization is needed
#
# Updated approach (September 2025):
# - Preview: esbuild only, CSS injected directly (5-10s deployments)
# - Production: Full Vite pipeline with optimizations

require 'open3'
require 'tempfile'
require 'json'
require 'fileutils'
require 'digest'

class FastBuildService
  attr_reader :app, :build_cache, :template_path

  # Cache compiled modules for instant subsequent loads
  CACHE_TTL = 5.minutes
  
  # Vite configuration optimized for speed and compatibility
  VITE_CONFIG = {
    mode: 'development', # Skip minification for preview builds
    build: {
      target: 'esnext',
      minify: false, # Skip minification for speed
      sourcemap: 'inline',
      rollupOptions: {
        external: [], # Bundle everything for Workers
        output: {
          inlineDynamicImports: true # Single file for Workers
        }
      }
    },
    server: {
      hmr: true,
      port: 0 # Use random available port
    }
  }.freeze

  def initialize(app)
    @app = app
    @build_cache = Rails.cache
    @template_path = Rails.root.join('app/services/ai/templates/overskill_20250728')
    @vite_path = find_vite_binary
  end

  # Build a single file asynchronously using Vite's transform API
  def build_file_async(file_path, content, &block)
    cache_key = "vite_build:#{app.id}:#{file_path}:#{Digest::MD5.hexdigest(content)}"
    
    # Check cache first
    cached = build_cache.read(cache_key)
    if cached
      Rails.logger.info "[FastBuild] Cache hit for #{file_path}"
      block.call(cached)
      return
    end
    
    # Run build in background thread for non-blocking operation
    Thread.new do
      Rails.application.executor.wrap do
        result = transform_file_with_vite(file_path, content)
        
        # Cache successful builds
        if result[:success]
          build_cache.write(cache_key, result, expires_in: CACHE_TTL)
        end
        
        block.call(result)
      end
    end
  end

  # Start Vite dev server for HMR (Hot Module Replacement)
  def start_hmr_server
    start_time = Time.current
    
    Rails.logger.info "[FastBuild] Starting Vite HMR server for app #{app.id}"
    
    Dir.mktmpdir do |temp_dir|
      # Copy app files to temp directory with proper structure
      setup_vite_project(temp_dir)
      
      # Start Vite dev server
      cmd = "cd #{temp_dir} && #{@vite_path} --port 0 --host 0.0.0.0 --mode development"
      
      # Run Vite in background and capture the dev server URL
      stdout, stderr, status = Open3.capture3(cmd, timeout: 10)
      
      if status.success?
        # Extract dev server URL from Vite output
        server_url = extract_server_url(stdout)
        
        start_time_ms = ((Time.current - start_time) * 1000).round
        Rails.logger.info "[FastBuild] Vite HMR server started in #{start_time_ms}ms: #{server_url}"
        
        {
          success: true,
          server_url: server_url,
          temp_dir: temp_dir,
          start_time: start_time_ms
        }
      else
        Rails.logger.error "[FastBuild] Failed to start Vite server: #{stderr}"
        {
          success: false,
          error: stderr
        }
      end
    end
  end

  # Build for preview deployment (fast, bypasses PostCSS complexity)
  def build_full_bundle(environment_vars = {})
    start_time = Time.current
    
    Rails.logger.info "[FastBuild] Building preview bundle with esbuild for app #{app.id}"
    Rails.logger.info "[FastBuild] Environment variables provided: #{environment_vars.keys.select { |k| k.start_with?('VITE_') }.join(', ')}" if environment_vars.any?
    
    begin
      Dir.mktmpdir do |temp_dir|
      Rails.logger.info "[FastBuild] Created temp dir: #{temp_dir}"
      
      # Write app files with environment variable replacement
      write_app_files(temp_dir, environment_vars)
      Rails.logger.info "[FastBuild] Wrote #{app.app_files.count} files to temp dir with env vars replaced"
      
      # Install minimal dependencies for esbuild
      Rails.logger.info "[FastBuild] Installing dependencies..."
      install_result = install_minimal_deps(temp_dir)
      unless install_result[:success]
        Rails.logger.error "[FastBuild] Dependency installation failed: #{install_result[:error]}"
        return { success: false, error: install_result[:error] || "Dependency installation failed" }
      end
      Rails.logger.info "[FastBuild] Dependencies installed successfully"
      
      # Find entry point
      entry_point = find_entry_point(temp_dir)
      unless entry_point
        Rails.logger.error "[FastBuild] No entry point found"
        # List files in src directory for debugging
        if File.exist?(File.join(temp_dir, 'src'))
          files_in_src = Dir.glob(File.join(temp_dir, 'src', '*'))
          Rails.logger.error "[FastBuild] Files in src: #{files_in_src.map { |f| File.basename(f) }.join(', ')}"
        end
        return { success: false, error: "No entry point found (main.tsx, index.tsx, App.tsx)" }
      end
      Rails.logger.info "[FastBuild] Found entry point: #{entry_point}"
      
      # Process CSS through Tailwind first
      Rails.logger.info "[FastBuild] Processing Tailwind CSS..."
      css_result = process_tailwind_css(temp_dir)
      unless css_result[:success]
        Rails.logger.warn "[FastBuild] Tailwind processing failed, continuing with raw CSS"
      end
      
      # Build JavaScript with esbuild
      js_result = build_with_esbuild(temp_dir, entry_point, environment_vars)
      
      if js_result[:success]
        # Combine JS and CSS with environment variables
        final_bundle = combine_assets(js_result[:output], environment_vars)
        
        build_time = ((Time.current - start_time) * 1000).round
        Rails.logger.info "[FastBuild] Build completed in #{build_time}ms"
        
        {
          success: true,
          bundle_files: { 'index.js' => final_bundle },
          main_bundle: final_bundle,
          build_time: build_time,
          files_count: app.app_files.count
        }
      else
        { success: false, error: js_result[:error] }
      end
      end
    rescue => e
      Rails.logger.error "[FastBuild] Exception during build: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, error: "Build exception: #{e.message}" }
    end
  end

  # Transform single file using Vite's transform API
  def transform_file_with_vite(file_path, content)
    return { success: true, compiled_content: content } unless needs_compilation?(file_path)
    
    # For single file transformation, use esbuild directly (faster and simpler)
    # Full bundles still use Vite for proper module resolution
    
    # Determine loader type based on file extension
    loader = case File.extname(file_path)
             when '.tsx', '.jsx' then 'tsx'
             when '.ts' then 'ts'
             when '.js' then 'js'
             when '.css' then 'css'
             else 'js'
             end
    
    jsx_flag = ['.tsx', '.jsx'].include?(File.extname(file_path)) ? '--jsx=automatic' : ''
    
    # Use stdin to pass content to esbuild
    cmd = "npx esbuild --loader=#{loader} --format=esm --target=es2020 #{jsx_flag}".strip
    stdout, stderr, status = Open3.capture3(cmd, stdin_data: content)
    
    if status.success?
      {
        success: true,
        compiled_content: stdout,
        source_map: nil # esbuild can generate source maps if needed
      }
    else
      Rails.logger.error "[FastBuild] Transform failed for #{file_path}: #{stderr}"
      {
        success: false,
        error: stderr
      }
    end
  end

  # Incremental build for file changes (leverages Vite's dependency graph)
  def incremental_build(changed_files)
    start_time = Time.current
    
    Rails.logger.info "[FastBuild] Incremental build for #{changed_files.size} files"
    
    results = changed_files.map do |file_path|
      file = app.app_files.find_by(path: file_path)
      next unless file
      
      transform_file_with_vite(file_path, file.content)
    end.compact
    
    build_time = ((Time.current - start_time) * 1000).round
    Rails.logger.info "[FastBuild] Incremental build completed in #{build_time}ms"
    
    {
      success: results.all? { |r| r[:success] },
      results: results,
      build_time: build_time
    }
  end

  private

  def write_app_files(temp_dir, environment_vars = {})
    app.app_files.each do |file|
      file_path = File.join(temp_dir, file.path)
      FileUtils.mkdir_p(File.dirname(file_path))
      
      # Pre-process JavaScript/TypeScript files to replace environment variables
      content = file.content
      if file.path.end_with?('.js', '.jsx', '.ts', '.tsx') && !file.path.include?('node_modules')
        content = replace_env_vars_in_source(content, environment_vars)
      end
      
      File.write(file_path, content)
    end
  end
  
  def replace_env_vars_in_source(content, environment_vars)
    # Replace import.meta.env.VITE_* with actual values at source level
    result = content.dup
    
    # Standard Vite environment variables
    result.gsub!('import.meta.env.MODE', '"production"')
    result.gsub!('import.meta.env.PROD', 'true')
    result.gsub!('import.meta.env.DEV', 'false')
    result.gsub!('import.meta.env.SSR', 'false')
    result.gsub!('import.meta.env.BASE_URL', '"/"')
    
    # Replace VITE_ environment variables
    environment_vars.each do |key, value|
      if key.to_s.start_with?('VITE_')
        # Replace import.meta.env.KEY with the actual value
        pattern = "import.meta.env.#{key}"
        replacement = JSON.generate(value.to_s)
        result.gsub!(pattern, replacement)
      end
    end
    
    result
  end
  
  def find_entry_point(temp_dir)
    %w[src/main.tsx src/index.tsx src/App.tsx index.tsx main.tsx App.tsx].each do |path|
      full_path = File.join(temp_dir, path)
      return path if File.exist?(full_path)
    end
    nil
  end
  
  def install_minimal_deps(temp_dir)
    Rails.logger.info "[FastBuild] Installing minimal dependencies"
    
    # Create a minimal package.json with only essential deps
    package_json = {
      name: "app-#{app.id}",
      version: "1.0.0", 
      type: "module",
      dependencies: {
        "react" => "^18.3.1",
        "react-dom" => "^18.3.1",
        "react-router-dom" => "^6.28.1",
        "@tanstack/react-query" => "^5.64.0",
        "@supabase/supabase-js" => "^2.48.0",
        "next-themes" => "^0.4.4",
        "sonner" => "^1.7.2",
        "@radix-ui/react-slot" => "^1.1.1",
        "@radix-ui/react-progress" => "^1.1.1",
        "@radix-ui/react-toast" => "^1.2.4",
        "@radix-ui/react-dialog" => "^1.1.4",
        "@radix-ui/react-tabs" => "^1.1.2",
        "@radix-ui/react-select" => "^2.1.3",
        "@radix-ui/react-label" => "^2.1.1",
        "@radix-ui/react-checkbox" => "^1.1.3",
        "@radix-ui/react-separator" => "^1.1.7",
        "@radix-ui/react-dropdown-menu" => "^2.1.15",
        "@radix-ui/react-avatar" => "^1.1.10",
        "@radix-ui/react-switch" => "^1.2.5",
        "recharts" => "^2.13.3",
        "class-variance-authority" => "^0.7.1",
        "clsx" => "^2.1.1",
        "tailwind-merge" => "^2.6.0",
        "lucide-react" => "^0.469.0"
      },
      devDependencies: {
        "esbuild" => "^0.24.2",
        "@types/react" => "^18.3.18",
        "@types/react-dom" => "^18.3.0",
        "typescript" => "^5.8.3",
        "tailwindcss" => "^3.4.1",
        "postcss" => "^8.4.35",
        "autoprefixer" => "^10.4.17"
      }
    }
    
    package_json_path = File.join(temp_dir, 'package.json')
    File.write(package_json_path, JSON.pretty_generate(package_json))
    Rails.logger.info "[FastBuild] Created package.json at #{package_json_path}"
    
    # Install dependencies (simplified, no lockfile)
    cmd = "npm install --no-save --no-package-lock"
    Rails.logger.info "[FastBuild] Running: npm install in #{temp_dir}"
    
    stdout, stderr, status = Open3.capture3(cmd, chdir: temp_dir)
    
    if status.success?
      Rails.logger.info "[FastBuild] npm install successful"
      { success: true }
    else
      error_msg = stderr.present? ? stderr : stdout
      Rails.logger.error "[FastBuild] npm install failed with status #{status.exitstatus}"
      Rails.logger.error "[FastBuild] stdout: #{stdout}" if stdout.present?
      Rails.logger.error "[FastBuild] stderr: #{stderr}" if stderr.present?
      { success: false, error: error_msg }
    end
  end
  
  def process_tailwind_css(temp_dir)
    Rails.logger.info "[FastBuild] Processing CSS with Tailwind"
    
    # Create Tailwind config if it doesn't exist
    tailwind_config = File.join(temp_dir, 'tailwind.config.js')
    unless File.exist?(tailwind_config)
      File.write(tailwind_config, <<~JS)
        module.exports = {
          content: [
            "./src/**/*.{js,jsx,ts,tsx}",
            "./index.html"
          ],
          theme: {
            extend: {},
          },
          plugins: [],
        }
      JS
    end
    
    # Create PostCSS config
    postcss_config = File.join(temp_dir, 'postcss.config.js')
    File.write(postcss_config, <<~JS)
      module.exports = {
        plugins: {
          tailwindcss: {},
          autoprefixer: {},
        },
      }
    JS
    
    # Process index.css through Tailwind
    index_css_path = File.join(temp_dir, 'src', 'index.css')
    output_css_path = File.join(temp_dir, 'src', 'index.compiled.css')
    
    if File.exist?(index_css_path)
      cmd = "npx tailwindcss -i #{index_css_path} -o #{output_css_path} --minify"
      Rails.logger.info "[FastBuild] Running: #{cmd}"
      
      stdout, stderr, status = Open3.capture3(cmd, chdir: temp_dir)
      
      if status.success?
        # Replace original CSS with compiled version
        File.write(index_css_path, File.read(output_css_path))
        Rails.logger.info "[FastBuild] Tailwind CSS compiled successfully"
        { success: true }
      else
        Rails.logger.error "[FastBuild] Tailwind compilation failed: #{stderr}"
        { success: false, error: stderr }
      end
    else
      Rails.logger.warn "[FastBuild] No index.css found to process"
      { success: true }
    end
  end
  
  def build_with_esbuild(temp_dir, entry_point, environment_vars = {})
    Rails.logger.info "[FastBuild] Building #{entry_point} with esbuild"
    Rails.logger.info "[FastBuild] Environment variables pre-processed in source files"
    
    # Build JavaScript/TypeScript with esbuild (env vars already replaced in source)
    cmd = [
      'npx', 'esbuild', entry_point,
      '--bundle',
      '--format=iife',  # Use IIFE to avoid module timing issues
      '--platform=browser',
      '--target=es2022',
      '--jsx=automatic',
      '--loader:.js=jsx',
      '--loader:.jsx=jsx',
      '--loader:.ts=ts',
      '--loader:.tsx=tsx', 
      '--loader:.css=text',
      '--define:process.env.NODE_ENV="production"',
      '--minify',
      '--tree-shaking=true',
      '--log-level=warning'
    ]
    
    Rails.logger.info "[FastBuild] Running esbuild with #{cmd.length} arguments"
    
    # Pass command as array
    stdout, stderr, status = Open3.capture3(*cmd, chdir: temp_dir)
    
    if status.success?
      { success: true, output: stdout }
    else
      Rails.logger.error "[FastBuild] esbuild failed: #{stderr}"
      { success: false, error: stderr }
    end
  end
  
  def combine_assets(js_bundle, environment_vars = {})
    # Environment variables already replaced in source files before bundling
    # Check if we have processed CSS, otherwise use CDN Tailwind
    css_files = app.app_files.select { |f| f.path.end_with?('.css') }
    
    # Check if CSS contains Tailwind directives
    has_tailwind_directives = css_files.any? { |f| f.content.include?('@tailwind') }
    
    if has_tailwind_directives
      # Extract CSS variables and custom styles (everything except @tailwind directives)
      css_content = css_files.map { |f| 
        # Remove @tailwind directives but keep everything else
        f.content.gsub(/@tailwind\s+(base|components|utilities);?/, '')
      }.join("\n")
      tailwind_cdn = true
    else
      # Use existing CSS as-is
      css_content = css_files.map(&:content).join("\n")
      tailwind_cdn = false
    end
    
    # Escape CSS for JavaScript string
    escaped_css = css_content.gsub('`', '\\`').gsub('$', '\\$')
    
    # Create complete bundle with CSS and JS
    if tailwind_cdn
      <<~JS
        // FastBuild Preview Bundle for App #{app.id}
        
        // Load CSS variables and Tailwind
        (function() {
          // FIRST: Inject CSS variables and custom styles
          const customCSS = `#{escaped_css}`;
          if (customCSS.trim()) {
            const style = document.createElement('style');
            style.innerHTML = customCSS;
            document.head.appendChild(style);
            console.log('[FastBuild] CSS variables injected');
          }
          
          // THEN: Configure Tailwind with custom colors
          window.tailwindConfig = {
            theme: {
              extend: {
                colors: {
                  background: 'hsl(var(--background))',
                  foreground: 'hsl(var(--foreground))',
                  card: 'hsl(var(--card))',
                  'card-foreground': 'hsl(var(--card-foreground))',
                  popover: 'hsl(var(--popover))',
                  'popover-foreground': 'hsl(var(--popover-foreground))',
                  primary: 'hsl(var(--primary))',
                  'primary-foreground': 'hsl(var(--primary-foreground))',
                  secondary: 'hsl(var(--secondary))',
                  'secondary-foreground': 'hsl(var(--secondary-foreground))',
                  muted: 'hsl(var(--muted))',
                  'muted-foreground': 'hsl(var(--muted-foreground))',
                  accent: 'hsl(var(--accent))',
                  'accent-foreground': 'hsl(var(--accent-foreground))',
                  destructive: 'hsl(var(--destructive))',
                  'destructive-foreground': 'hsl(var(--destructive-foreground))',
                  border: 'hsl(var(--border))',
                  input: 'hsl(var(--input))',
                  ring: 'hsl(var(--ring))',
                }
              }
            }
          };
          
          // FINALLY: Load Tailwind CDN
          const script = document.createElement('script');
          script.src = 'https://cdn.tailwindcss.com';
          script.onload = function() {
            console.log('[FastBuild] Tailwind CSS loaded from CDN with custom config');
            
            // Generate custom utility classes for CSS variable colors
            const customUtilities = document.createElement('style');
            customUtilities.innerHTML = \`
              /* Custom Utilities for CSS Variable Colors */
              /* Background Colors */
              .bg-background { background-color: hsl(var(--background)) !important; }
              .bg-foreground { background-color: hsl(var(--foreground)) !important; }
              .bg-card { background-color: hsl(var(--card)) !important; }
              .bg-popover { background-color: hsl(var(--popover)) !important; }
              .bg-primary { background-color: hsl(var(--primary)) !important; }
              .bg-secondary { background-color: hsl(var(--secondary)) !important; }
              .bg-muted { background-color: hsl(var(--muted)) !important; }
              .bg-accent { background-color: hsl(var(--accent)) !important; }
              .bg-destructive { background-color: hsl(var(--destructive)) !important; }
              
              /* Text Colors */
              .text-foreground { color: hsl(var(--foreground)) !important; }
              .text-card-foreground { color: hsl(var(--card-foreground)) !important; }
              .text-popover-foreground { color: hsl(var(--popover-foreground)) !important; }
              .text-primary { color: hsl(var(--primary)) !important; }
              .text-primary-foreground { color: hsl(var(--primary-foreground)) !important; }
              .text-secondary-foreground { color: hsl(var(--secondary-foreground)) !important; }
              .text-muted-foreground { color: hsl(var(--muted-foreground)) !important; }
              .text-accent-foreground { color: hsl(var(--accent-foreground)) !important; }
              .text-destructive { color: hsl(var(--destructive)) !important; }
              .text-destructive-foreground { color: hsl(var(--destructive-foreground)) !important; }
              
              /* Border Colors */
              .border-border { border-color: hsl(var(--border)) !important; }
              .border-input { border-color: hsl(var(--input)) !important; }
              .border-primary { border-color: hsl(var(--primary)) !important; }
              .border-secondary { border-color: hsl(var(--secondary)) !important; }
              .border-destructive { border-color: hsl(var(--destructive)) !important; }
              .border-muted { border-color: hsl(var(--muted)) !important; }
              
              /* Ring Colors */
              .ring-ring { --tw-ring-color: hsl(var(--ring)) !important; }
              .ring-primary { --tw-ring-color: hsl(var(--primary)) !important; }
              .ring-destructive { --tw-ring-color: hsl(var(--destructive)) !important; }
              
              /* Focus Ring Colors */
              .focus\\\\:ring-ring:focus { --tw-ring-color: hsl(var(--ring)) !important; }
              .focus\\\\:ring-primary:focus { --tw-ring-color: hsl(var(--primary)) !important; }
              
              /* Hover Variants */
              .hover\\\\:bg-primary:hover { background-color: hsl(var(--primary)) !important; }
              .hover\\\\:bg-secondary:hover { background-color: hsl(var(--secondary)) !important; }
              .hover\\\\:bg-muted:hover { background-color: hsl(var(--muted)) !important; }
              .hover\\\\:bg-accent:hover { background-color: hsl(var(--accent)) !important; }
              .hover\\\\:bg-destructive:hover { background-color: hsl(var(--destructive)) !important; }
              .hover\\\\:text-accent-foreground:hover { color: hsl(var(--accent-foreground)) !important; }
              
              /* Dark Mode Variants */
              .dark .dark\\\\:bg-background { background-color: hsl(var(--background)) !important; }
              .dark .dark\\\\:bg-card { background-color: hsl(var(--card)) !important; }
              .dark .dark\\\\:bg-popover { background-color: hsl(var(--popover)) !important; }
              .dark .dark\\\\:bg-muted { background-color: hsl(var(--muted)) !important; }
              .dark .dark\\\\:text-foreground { color: hsl(var(--foreground)) !important; }
              .dark .dark\\\\:text-muted-foreground { color: hsl(var(--muted-foreground)) !important; }
              .dark .dark\\\\:border-border { border-color: hsl(var(--border)) !important; }
              
              /* Chart Colors */
              .bg-chart-1 { background-color: hsl(var(--chart-1)) !important; }
              .bg-chart-2 { background-color: hsl(var(--chart-2)) !important; }
              .bg-chart-3 { background-color: hsl(var(--chart-3)) !important; }
              .bg-chart-4 { background-color: hsl(var(--chart-4)) !important; }
              .bg-chart-5 { background-color: hsl(var(--chart-5)) !important; }
              
              /* Additional Common Patterns */
              .divide-border > :not([hidden]) ~ :not([hidden]) { border-color: hsl(var(--border)) !important; }
              .ring-offset-background { --tw-ring-offset-color: hsl(var(--background)) !important; }
              
              /* Opacity Variants */
              .bg-background\\\\/50 { background-color: hsl(var(--background) / 0.5) !important; }
              .bg-background\\\\/80 { background-color: hsl(var(--background) / 0.8) !important; }
              .bg-background\\\\/95 { background-color: hsl(var(--background) / 0.95) !important; }
              .bg-muted\\\\/50 { background-color: hsl(var(--muted) / 0.5) !important; }
              .bg-accent\\\\/50 { background-color: hsl(var(--accent) / 0.5) !important; }
              
              /* Placeholder Colors */
              .placeholder\\\\:text-muted-foreground::placeholder { color: hsl(var(--muted-foreground)) !important; }
            \`;
            document.head.appendChild(customUtilities);
            console.log('[FastBuild] Custom utilities injected for CSS variable colors');
          };
          document.head.appendChild(script);
        })();
        
        // Application JavaScript (env vars replaced at source level)
        #{js_bundle}
      JS
    else
      <<~JS
        // FastBuild Preview Bundle for App #{app.id}
        
        // Inject CSS styles
        (function() {
          const style = document.createElement('style');
          style.innerHTML = `#{escaped_css}`;
          document.head.appendChild(style);
        })();
        
        // Application JavaScript (env vars replaced at source level)
        #{js_bundle}
      JS
    end
  end

  # Legacy Vite setup (kept for reference/fallback)
  def setup_vite_project(temp_dir)
    # Copy template structure
    FileUtils.cp_r("#{@template_path}/.", temp_dir)
    
    # Write all app files, overriding template files
    write_app_files(temp_dir)
    
    # Ensure package.json exists with proper dependencies
    package_json_path = File.join(temp_dir, 'package.json')
    if File.exist?(package_json_path)
      Rails.logger.info "[FastBuild] Using existing package.json from template"
    else
      File.write(package_json_path, generate_minimal_package_json)
    end
    
    # Ensure vite.config.ts exists
    vite_config_path = File.join(temp_dir, 'vite.config.ts')
    unless File.exist?(vite_config_path)
      File.write(vite_config_path, generate_vite_config)
    end
    
    # Install dependencies quickly (using existing node_modules if available)
    if File.exist?(File.join(@template_path, 'node_modules'))
      Rails.logger.info "[FastBuild] Copying node_modules from template"
      # Use dereference_root option to handle symlinks properly
      FileUtils.cp_r(File.join(@template_path, 'node_modules'), temp_dir, remove_destination: true)
    else
      Rails.logger.info "[FastBuild] Installing dependencies"
      system("cd #{temp_dir} && npm ci --silent")
    end
  end

  def create_transform_project(temp_dir, file_path, content)
    # Create minimal project for single file transformation
    File.write(File.join(temp_dir, 'package.json'), generate_minimal_package_json)
    File.write(File.join(temp_dir, 'vite.config.ts'), generate_vite_config)
    File.write(File.join(temp_dir, File.basename(file_path)), content)
  end

  def generate_transform_script(file_path)
    # Node.js script that uses Vite's transform API
    <<~JS
      import { createServer } from 'vite';
      import fs from 'fs';

      async function transform() {
        const server = await createServer({
          configFile: './vite.config.ts',
          logLevel: 'error'
        });

        try {
          const content = fs.readFileSync('#{File.basename(file_path)}', 'utf-8');
          const result = await server.transformRequest('#{file_path}');
          
          console.log(JSON.stringify({
            code: result.code,
            map: result.map
          }));
        } finally {
          await server.close();
        }
      }

      transform().catch(console.error);
    JS
  end

  def generate_vite_config
    # Generate Vite config optimized for fast builds
    <<~TS
      import { defineConfig } from "vite";
      import react from "@vitejs/plugin-react-swc";
      import path from "path";

      export default defineConfig({
        plugins: [react()],
        resolve: {
          alias: {
            "@": path.resolve(__dirname, "./src"),
          },
        },
        build: {
          target: 'esnext',
          minify: false,
          sourcemap: 'inline',
          rollupOptions: {
            output: {
              inlineDynamicImports: true
            }
          }
        },
        optimizeDeps: {
          force: true
        }
      });
    TS
  end

  def generate_minimal_package_json
    # Minimal package.json for Vite transformation
    {
      name: "fast-build-temp",
      version: "1.0.0",
      type: "module",
      scripts: {
        build: "vite build",
        dev: "vite"
      },
      dependencies: {
        "react" => "^18.3.1",
        "react-dom" => "^18.3.1"
      },
      devDependencies: {
        "@vitejs/plugin-react-swc" => "^3.11.0",
        "vite" => "^6.0.7",
        "typescript" => "^5.8.3"
      }
    }.to_json
  end

  def read_built_files(dist_dir)
    files = {}
    
    Dir.glob("#{dist_dir}/**/*").each do |file_path|
      next if File.directory?(file_path)
      
      relative_path = file_path.sub("#{dist_dir}/", "")
      files[relative_path] = File.read(file_path)
    end
    
    files
  end

  def extract_server_url(vite_output)
    # Extract the dev server URL from Vite's startup output
    match = vite_output.match(/Local:\s+(http:\/\/[^\s]+)/)
    match ? match[1] : "http://localhost:5173"
  end

  def needs_compilation?(file_path)
    %w[.ts .tsx .js .jsx .vue .svelte].include?(File.extname(file_path))
  end

  def find_vite_binary
    # Try common locations for Vite
    paths = [
      File.join(@template_path, 'node_modules/.bin/vite'),
      'node_modules/.bin/vite',
      '/usr/local/bin/vite'
    ]
    
    paths.each do |path|
      return path if File.exist?(path)
    end
    
    # Fall back to npx vite
    'npx vite'
  end
end