# FastBuildService - Optimized for instant preview deployments
# Uses esbuild directly for preview builds to bypass PostCSS/Vite complexity
# Falls back to Vite for production builds when full optimization is needed
#
# Updated approach (September 2025):
# - Preview: esbuild only, CSS injected directly (5-10s deployments)
# - Production: Full Vite pipeline with optimizations

require "open3"
require "tempfile"
require "json"
require "fileutils"
require "digest"

class FastBuildService
  attr_reader :app, :build_cache, :template_path

  # Cache compiled modules for instant subsequent loads
  CACHE_TTL = 5.minutes

  # Vite configuration optimized for speed and compatibility
  VITE_CONFIG = {
    mode: "development", # Skip minification for preview builds
    build: {
      target: "esnext",
      minify: false, # Skip minification for speed
      sourcemap: "inline",
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
    @template_path = Rails.root.join("app/services/ai/templates/overskill_20250728")
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
    Rails.logger.info "[FastBuild] Environment variables provided: #{environment_vars.keys.select { |k| k.start_with?("VITE_") }.join(", ")}" if environment_vars.any?

    begin
      Dir.mktmpdir do |temp_dir|
        Rails.logger.info "[FastBuild] Created temp dir: #{temp_dir}"

        # Use template structure with working Vite + Tailwind setup
        Rails.logger.info "[FastBuild] Setting up Vite project with template structure..."
        setup_vite_project(temp_dir, environment_vars)
        Rails.logger.info "[FastBuild] Template structure copied with working Tailwind config"

        # Find entry point after files are written
        entry_point = find_entry_point(temp_dir)
        unless entry_point
          Rails.logger.error "[FastBuild] No entry point found"
          # List files in src directory for debugging
          if File.exist?(File.join(temp_dir, "src"))
            files_in_src = Dir.glob(File.join(temp_dir, "src", "*"))
            Rails.logger.error "[FastBuild] Files in src: #{files_in_src.map { |f| File.basename(f) }.join(", ")}"
          end
          return {success: false, error: "No entry point found (main.tsx, index.tsx, App.tsx)"}
        end
        Rails.logger.info "[FastBuild] Found entry point: #{entry_point}"

        # Build with Vite (handles Tailwind CSS automatically)
        vite_result = build_with_vite(temp_dir, environment_vars)

        if vite_result[:success]
          build_time = ((Time.current - start_time) * 1000).round
          Rails.logger.info "[FastBuild] Build completed in #{build_time}ms"

          # Return all bundle files (chunks) from Vite build
          # EdgePreviewService will embed all of them in the worker
          {
            success: true,
            bundle_files: vite_result[:bundle_files],
            main_bundle: nil, # No longer using single bundle
            build_time: build_time,
            files_count: app.app_files.count
          }
        else
          {success: false, error: vite_result[:error]}
        end
      end
    rescue => e
      Rails.logger.error "[FastBuild] Exception during build: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      {success: false, error: "Build exception: #{e.message}"}
    end
  end

  # Transform single file using Vite's transform API
  def transform_file_with_vite(file_path, content)
    return {success: true, compiled_content: content} unless needs_compilation?(file_path)

    # For single file transformation, use esbuild directly (faster and simpler)
    # Full bundles still use Vite for proper module resolution

    # Determine loader type based on file extension
    loader = case File.extname(file_path)
    when ".tsx", ".jsx" then "tsx"
    when ".ts" then "ts"
    when ".js" then "js"
    when ".css" then "css"
    else "js"
    end

    jsx_flag = [".tsx", ".jsx"].include?(File.extname(file_path)) ? "--jsx=automatic" : ""

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

  # Ensure Vite configuration is properly set up for IIFE output format
  # CRITICAL: Required for non-module script tags to avoid ES module errors
  def ensure_iife_vite_config(temp_dir)
    vite_config_path = File.join(temp_dir, "vite.config.ts")

    if File.exist?(vite_config_path)
      Rails.logger.info "[FastBuild] Enforcing IIFE format in vite.config.ts"

      # Read the existing config
      File.read(vite_config_path)

      # Create a completely new config that forces IIFE format
      # This overrides the template config to ensure IIFE output
      new_config = <<~TS
        import { defineConfig } from "vite";
        import react from "@vitejs/plugin-react-swc";
        import path from "path";

        // FORCED IIFE FORMAT FOR FASTBUILD PREVIEW - RESEARCH VALIDATED APPROACH
        export default defineConfig({
          define: {
            'process.env.NODE_ENV': '"production"',
          },
          plugins: [react()],
          resolve: {
            alias: {
              "@": path.resolve(__dirname, "./src"),
            },
          },
          build: {
            // Use library mode for single file output
            lib: {
              entry: path.resolve(__dirname, 'src/main.tsx'),
              name: 'App',
              formats: ['iife'],
              fileName: (format) => 'bundle.js'
            },

            outDir: 'dist',
            emptyOutDir: true,
            minify: true,
            cssCodeSplit: false,

            rollupOptions: {
              external: [], // Bundle everything including React
              output: {
                format: 'iife',
                name: 'App',
                inlineDynamicImports: true,
                // RESEARCH SOLUTION: Force everything into single chunk
                manualChunks: undefined, // Disable chunking in lib mode
                globals: {},
                // Additional optimizations
                compact: true,
                generatedCode: {
                  constBindings: true
                }
              }
            },

            // Increase chunk size warning limit for single bundle
            chunkSizeWarningLimit: 5000,

            // Disable module preload
            modulePreload: false,

            // Terser optimization for IIFE
            terserOptions: {
              format: {
                comments: false,
              },
              compress: {
                drop_console: true,
                drop_debugger: true,
                pure_funcs: ['console.log', 'console.info', 'console.debug'],
                passes: 2
              }
            }
          }
        });
      TS

      File.write(vite_config_path, new_config)
      Rails.logger.info "[FastBuild] Vite config completely replaced with IIFE format"
    else
      Rails.logger.warn "[FastBuild] No vite.config.ts found at #{vite_config_path}"
    end
  end

  # Memory-safe command execution with output limits and timeouts
  def execute_command_with_limits(cmd, env: {}, chdir: nil, timeout: 60, max_output: 10.megabytes)
    output = StringIO.new
    error = StringIO.new
    success = false
    bytes_read = 0

    Rails.logger.info "[FastBuild] Executing with limits: #{cmd.is_a?(Array) ? cmd.join(" ") : cmd}"

    begin
      Open3.popen3(env, *cmd, chdir: chdir) do |stdin, stdout, stderr, wait_thread|
        stdin.close

        # Use IO.select with timeout for non-blocking reads
        start_time = Time.current

        while (Time.current - start_time) < timeout
          ready = IO.select([stdout, stderr], nil, nil, 0.1)

          if ready
            ready[0].each do |io|
              chunk = io.read_nonblock(8192)

              if io == stdout
                bytes_read += chunk.bytesize
                if bytes_read > max_output
                  Rails.logger.warn "[FastBuild] Output exceeded #{max_output} bytes, truncating"
                  output.write("\n[TRUNCATED - output too large]\n")
                  break
                end
                output.write(chunk)
              elsif chunk
                error.write(chunk)
              end
            rescue EOFError
              # Stream closed, normal
            rescue IO::WaitReadable
              # No data available yet, continue
            end
          end

          # Check if process has finished
          if wait_thread.join(0)
            success = wait_thread.value.success?
            break
          end
        end

        # Kill process if still running after timeout
        unless wait_thread.join(0)
          Rails.logger.error "[FastBuild] Command timed out after #{timeout}s, killing process"
          begin
            Process.kill("TERM", wait_thread.pid)
            wait_thread.join(5) # Give it 5 seconds to terminate
          rescue
            begin
              Process.kill("KILL", wait_thread.pid)
            rescue
              nil
            end
          end
        end
      end

      {
        success: success,
        stdout: output.string,
        stderr: error.string,
        truncated: bytes_read > max_output
      }
    rescue => e
      Rails.logger.error "[FastBuild] Command execution failed: #{e.message}"
      {
        success: false,
        stdout: output.string,
        stderr: "Execution failed: #{e.message}",
        truncated: false
      }
    end
  end

  def write_app_files(temp_dir, environment_vars = {})
    app.app_files.each do |file|
      file_path = File.join(temp_dir, file.path)
      FileUtils.mkdir_p(File.dirname(file_path))

      # Pre-process JavaScript/TypeScript files to replace environment variables
      content = file.content
      if file.path.end_with?(".js", ".jsx", ".ts", ".tsx") && !file.path.include?("node_modules")
        content = replace_env_vars_in_source(content, environment_vars)
      end

      File.write(file_path, content)
    end
  end

  def replace_env_vars_in_source(content, environment_vars)
    # Replace import.meta.env.VITE_* with actual values at source level
    result = content.dup

    # Standard Vite environment variables
    result.gsub!("import.meta.env.MODE", '"production"')
    result.gsub!("import.meta.env.PROD", "true")
    result.gsub!("import.meta.env.DEV", "false")
    result.gsub!("import.meta.env.SSR", "false")
    result.gsub!("import.meta.env.BASE_URL", '"/"')

    # Replace VITE_ environment variables
    environment_vars.each do |key, value|
      if key.to_s.start_with?("VITE_")
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

    package_json_path = File.join(temp_dir, "package.json")
    File.write(package_json_path, JSON.pretty_generate(package_json))
    Rails.logger.info "[FastBuild] Created package.json at #{package_json_path}"

    # Install dependencies (simplified, no lockfile)
    Rails.logger.info "[FastBuild] Running: npm install in #{temp_dir}"

    # Ensure proper environment variables are set with NVM paths
    nvm_node_path = ENV["NVM_DIR"] ? "#{ENV["NVM_DIR"]}/versions/node/v22.16.0/bin" : nil
    enhanced_path = [nvm_node_path, ENV["PATH"]].compact.join(":")

    env = {
      "PATH" => enhanced_path,
      "NODE_PATH" => ENV["NODE_PATH"],
      "NVM_DIR" => ENV["NVM_DIR"]
    }.compact

    # Use memory-safe execution with 60s timeout to prevent Broken Pipe errors
    result = execute_command_with_limits(
      ["npm", "install", "--no-save", "--no-package-lock"],
      env: env,
      chdir: temp_dir,
      timeout: 60,
      max_output: 5.megabytes
    )

    if result[:success]
      Rails.logger.info "[FastBuild] npm install successful"
      {success: true}
    else
      error_msg = result[:stderr].present? ? result[:stderr] : result[:stdout]
      Rails.logger.error "[FastBuild] npm install failed"
      Rails.logger.error "[FastBuild] stdout: #{result[:stdout]}" if result[:stdout].present?
      Rails.logger.error "[FastBuild] stderr: #{result[:stderr]}" if result[:stderr].present?
      {success: false, error: error_msg}
    end
  end

  def process_tailwind_css(temp_dir)
    Rails.logger.info "[FastBuild] Processing Tailwind CSS for app #{app.id}"

    begin
      # Check if any CSS files contain @tailwind directives
      css_files = app.app_files.select { |f| f.path.end_with?(".css") }
      has_tailwind_directives = css_files.any? { |f| f.content.include?("@tailwind") }

      unless has_tailwind_directives
        Rails.logger.info "[FastBuild] No @tailwind directives found, skipping Tailwind compilation"
        return {success: true}
      end

      # Create isolated Tailwind config for this build
      tailwind_config = File.join(temp_dir, "tailwind.config.js")
      File.write(tailwind_config, generate_tailwind_config)
      Rails.logger.info "[FastBuild] Created isolated tailwind.config.js"

      # Create PostCSS config
      postcss_config = File.join(temp_dir, "postcss.config.js")
      File.write(postcss_config, <<~JS)
        module.exports = {
          plugins: {
            tailwindcss: {},
            autoprefixer: {},
          },
        }
      JS
      Rails.logger.info "[FastBuild] Created postcss.config.js"

      # Process each CSS file that contains @tailwind directives
      compiled_css = ""
      css_files.each do |css_file|
        if css_file.content.include?("@tailwind")
          Rails.logger.info "[FastBuild] Compiling CSS file: #{css_file.path}"

          # Write CSS file to temp directory
          css_path = File.join(temp_dir, css_file.path)
          FileUtils.mkdir_p(File.dirname(css_path))
          File.write(css_path, css_file.content)

          # Compile with Tailwind CLI
          output_path = File.join(temp_dir, "compiled_#{File.basename(css_file.path)}")

          # Ensure proper environment variables are set with NVM paths
          nvm_node_path = ENV["NVM_DIR"] ? "#{ENV["NVM_DIR"]}/versions/node/v22.16.0/bin" : nil
          enhanced_path = [nvm_node_path, ENV["PATH"]].compact.join(":")

          env = {
            "PATH" => enhanced_path,
            "NODE_PATH" => ENV["NODE_PATH"],
            "NVM_DIR" => ENV["NVM_DIR"]
          }.compact

          Rails.logger.info "[FastBuild] Running Tailwind with memory limits"
          Rails.logger.info "[FastBuild] Environment PATH: #{env["PATH"]&.split(":")&.first(3)&.join(":")}"

          # Use memory-safe execution for Tailwind to prevent Broken Pipe errors
          tailwind_result = execute_command_with_limits(
            ["npx", "tailwindcss", "-i", css_path, "-o", output_path, "--config", tailwind_config],
            env: env,
            chdir: temp_dir,
            timeout: 30,  # 30 seconds for CSS compilation
            max_output: 5.megabytes
          )

          if tailwind_result[:success]
            compiled_content = File.read(output_path)
            compiled_css += compiled_content + "\n"
            Rails.logger.info "[FastBuild] Successfully compiled #{css_file.path}"
          else
            Rails.logger.warn "[FastBuild] Tailwind compilation failed for #{css_file.path}: #{tailwind_result[:stderr]}"
            # Fall back to raw CSS content
            compiled_css += css_file.content + "\n"
          end
        else
          # Add non-Tailwind CSS as-is
          compiled_css += css_file.content + "\n"
        end
      end

      # Check if compilation actually worked (no @tailwind directives should remain)
      if compiled_css.include?("@tailwind")
        Rails.logger.warn "[FastBuild] Tailwind compilation incomplete - @tailwind directives remain"
        @compiled_css = nil
        {success: false, error: "Tailwind compilation incomplete"}
      else
        # Store compiled CSS for use in bundle
        @compiled_css = compiled_css
        Rails.logger.info "[FastBuild] Tailwind CSS compilation completed successfully"
        {success: true, compiled_css: compiled_css}
      end
    rescue => e
      Rails.logger.error "[FastBuild] Tailwind processing failed: #{e.message}"
      Rails.logger.error e.backtrace.first(3).join("\n")

      # DON'T set @compiled_css - let combine_assets use CDN approach
      @compiled_css = nil
      Rails.logger.info "[FastBuild] Tailwind compilation failed, will use CDN approach"

      {success: false, error: e.message}
    end
  end

  def build_with_vite(temp_dir, environment_vars = {})
    Rails.logger.info "[FastBuild] Building with Vite (includes Tailwind processing)"

    # Ensure proper environment variables are set with NVM paths
    nvm_node_path = ENV["NVM_DIR"] ? "#{ENV["NVM_DIR"]}/versions/node/v22.16.0/bin" : nil
    enhanced_path = [nvm_node_path, ENV["PATH"]].compact.join(":")

    env = {
      "PATH" => enhanced_path,
      "NODE_PATH" => ENV["NODE_PATH"],
      "NVM_DIR" => ENV["NVM_DIR"],
      "NODE_ENV" => "production"  # Force production mode for IIFE output
    }.compact

    # Add environment variables for build-time injection
    environment_vars.each do |key, value|
      env[key] = value.to_s
    end

    # No longer forcing IIFE - let Vite build with ES modules and chunks
    # This follows the lovable template approach

    # Keep index.html for standard Vite build with ES modules and chunks

    # Run Vite build with memory-safe execution to prevent Broken Pipe errors
    Rails.logger.info "[FastBuild] Running Vite build with ES modules and chunks"

    # Use the vite binary directly from node_modules
    # This avoids npx issues and prepare-worker.js
    vite_binary = File.join(temp_dir, "node_modules", ".bin", "vite")

    # Check if vite binary exists
    unless File.exist?(vite_binary)
      Rails.logger.error "[FastBuild] Vite binary not found at #{vite_binary}"
      # Try to install it
      Rails.logger.info "[FastBuild] Attempting to install vite..."
      install_result = execute_command_with_limits(
        ["npm", "install", "vite", "--no-save"],
        env: env,
        chdir: temp_dir,
        timeout: 30,
        max_output: 10.megabytes
      )
      unless install_result[:success]
        return {success: false, error: "Failed to install vite: #{install_result[:stderr]}"}
      end
    end

    result = execute_command_with_limits(
      [vite_binary, "build"],
      env: env,
      chdir: temp_dir,
      timeout: 120,  # 2 minutes for builds
      max_output: 10.megabytes
    )

    if result[:success]
      Rails.logger.info "[FastBuild] Vite build successful"

      # Extract ALL JS and CSS files from dist directory (including chunks)
      dist_dir = File.join(temp_dir, "dist")
      if Dir.exist?(dist_dir)
        # Collect all assets (JS chunks, CSS files, etc.)
        bundle_files = {}

        # Get all JS files from dist and dist/assets
        js_files = Dir.glob(File.join(dist_dir, "**/*.js"))
        js_files.each do |file|
          file.sub(dist_dir, "").sub(/^\//, "")
          asset_path = "/assets/#{File.basename(file)}"
          content = File.read(file)
          bundle_files[asset_path] = content
          Rails.logger.info "[FastBuild] Found JS asset: #{asset_path} (#{content.length} chars)"
        end

        # Get all CSS files
        css_files = Dir.glob(File.join(dist_dir, "**/*.css"))
        css_files.each do |file|
          file.sub(dist_dir, "").sub(/^\//, "")
          asset_path = "/assets/#{File.basename(file)}"
          content = File.read(file)
          bundle_files[asset_path] = content
          Rails.logger.info "[FastBuild] Found CSS asset: #{asset_path} (#{content.length} chars)"
        end

        # Read the index.html to understand asset references
        index_html_path = File.join(dist_dir, "index.html")
        if File.exist?(index_html_path)
          index_html = File.read(index_html_path)
          bundle_files["/index.html"] = index_html
          Rails.logger.info "[FastBuild] Found index.html"
        end

        if bundle_files.any?
          Rails.logger.info "[FastBuild] Collected #{bundle_files.size} assets totaling #{bundle_files.values.sum(&:length)} chars"
          {success: true, bundle_files: bundle_files}
        else
          {success: false, error: "No compiled assets found in dist directory"}
        end
      else
        {success: false, error: "No dist directory created by Vite build"}
      end
    else
      Rails.logger.error "[FastBuild] Vite build failed: #{result[:stderr]}"
      Rails.logger.error "[FastBuild] Output was truncated: true" if result[:truncated]
      {success: false, error: "Vite build failed: #{result[:stderr]}"}
    end
  end

  def create_combined_bundle(js_content, css_content)
    # Escape CSS for JavaScript injection
    escaped_css = css_content
      .gsub("\\", "\\\\")     # Escape backslashes
      .gsub("`", '\\`')       # Escape backticks
      .gsub("$", '\\$')       # Escape dollar signs
      .gsub(/\s+/, " ")       # Normalize whitespace
      .strip

    # Create bundle with CSS injection + HMR client + JavaScript
    hmr_client = generate_hmr_client_code

    # Wrap Vite's ES module output in an IIFE to avoid module errors
    # Check if the JS content has ES module syntax
    if js_content.include?("import ") || js_content.include?("export ")
      Rails.logger.warn "[FastBuild] Vite output contains ES module syntax, wrapping in IIFE"

      # Simple wrapper to contain the module code
      wrapped_js = <<~JS
        (function() {
          // Polyfill import.meta if needed
          if (typeof import === 'undefined') {
            window.import = { meta: { env: { MODE: 'production', PROD: true, DEV: false } } };
          }

          // Wrapped Vite output (may still have issues with actual imports)
          try {
            #{js_content}
          } catch (e) {
            console.error('[FastBuild] Error in wrapped module:', e);
          }
        })();
      JS
    else
      wrapped_js = js_content
    end

    <<~JS
      // Vite-compiled bundle with Tailwind CSS for App #{app.id}
      #{hmr_client}

      // Inject compiled Tailwind CSS
      (function() {
        const style = document.createElement('style');
        style.innerHTML = `#{escaped_css}`;
        document.head.appendChild(style);
        console.log('[FastBuild] Vite-compiled Tailwind CSS injected (#{css_content.length} chars)');
      })();

      // Application JavaScript (compiled by Vite)
      #{wrapped_js}
    JS
  end

  def build_with_esbuild(temp_dir, entry_point, environment_vars = {})
    Rails.logger.info "[FastBuild] Building #{entry_point} with esbuild"
    Rails.logger.info "[FastBuild] Environment variables pre-processed in source files"

    # Build JavaScript/TypeScript with esbuild (env vars already replaced in source)
    cmd = [
      "npx", "esbuild", entry_point,
      "--bundle",
      "--format=iife",  # Use IIFE to avoid module timing issues
      "--platform=browser",
      "--target=es2022",
      "--jsx=automatic",
      "--loader:.js=jsx",
      "--loader:.jsx=jsx",
      "--loader:.ts=ts",
      "--loader:.tsx=tsx",
      "--loader:.css=text",
      '--define:process.env.NODE_ENV="production"',
      "--minify",
      "--tree-shaking=true",
      "--log-level=warning"
    ]

    Rails.logger.info "[FastBuild] Running esbuild with #{cmd.length} arguments"

    # Ensure proper environment variables are set with NVM paths
    nvm_node_path = ENV["NVM_DIR"] ? "#{ENV["NVM_DIR"]}/versions/node/v22.16.0/bin" : nil
    enhanced_path = [nvm_node_path, ENV["PATH"]].compact.join(":")

    env = {
      "PATH" => enhanced_path,
      "NODE_PATH" => ENV["NODE_PATH"],
      "NVM_DIR" => ENV["NVM_DIR"]
    }.compact

    # Pass command as array with environment
    stdout, stderr, status = Open3.capture3(env, *cmd, chdir: temp_dir)

    if status.success?
      {success: true, output: stdout}
    else
      Rails.logger.error "[FastBuild] esbuild failed: #{stderr}"
      {success: false, error: stderr}
    end
  end

  def generate_tailwind_config
    # Generate optimized Tailwind config for professional-grade UI capabilities
    # COMPREHENSIVE FEATURE SUPPORT:
    # ✅ JIT Mode - For arbitrary values and optimal performance
    # ✅ Dark Mode - Class-based theming support
    # ✅ Arbitrary Values - text-[14px], bg-[#ff0000], etc.
    # ✅ CSS Variables - Full hsl(var(--*)) integration
    # ✅ Container Queries - Modern responsive design
    # ✅ Dynamic Content - Comprehensive file scanning
    <<~JS
      /** @type {import('tailwindcss').Config} */
      module.exports = {
        // ENHANCED CONTENT SCANNING
        // Scans all possible file types where Tailwind classes might be used
        content: [
          "./src/**/*.{js,ts,jsx,tsx,vue,svelte}",
          "./public/**/*.{html,js}",
          "./pages/**/*.{js,ts,jsx,tsx}",
          "./components/**/*.{js,ts,jsx,tsx}",
          "./app/**/*.{js,ts,jsx,tsx}",
          "./lib/**/*.{js,ts,jsx,tsx}",
          "./styles/**/*.css",
          "./**/*.html",
          "./**/*.md",
          // AI-generated content patterns
          "./generated/**/*.{js,ts,jsx,tsx}",
          "./dynamic/**/*.{js,ts,jsx,tsx}"
        ],

        // DARK MODE SUPPORT - Enable class-based dark mode
        darkMode: 'class',

        theme: {
          // CONTAINER QUERIES - Modern responsive design
          container: {
            center: true,
            padding: "2rem",
            screens: {
              "2xl": "1400px",
            },
          },
          extend: {
            // CSS VARIABLES INTEGRATION - Full shadcn/ui compatibility
            colors: {
              border: "hsl(var(--border))",
              input: "hsl(var(--input))",
              ring: "hsl(var(--ring))",
              background: "hsl(var(--background))",
              foreground: "hsl(var(--foreground))",
              primary: {
                DEFAULT: "hsl(var(--primary))",
                foreground: "hsl(var(--primary-foreground))",
              },
              secondary: {
                DEFAULT: "hsl(var(--secondary))",
                foreground: "hsl(var(--secondary-foreground))",
              },
              destructive: {
                DEFAULT: "hsl(var(--destructive))",
                foreground: "hsl(var(--destructive-foreground))",
              },
              muted: {
                DEFAULT: "hsl(var(--muted))",
                foreground: "hsl(var(--muted-foreground))",
              },
              accent: {
                DEFAULT: "hsl(var(--accent))",
                foreground: "hsl(var(--accent-foreground))",
              },
              popover: {
                DEFAULT: "hsl(var(--popover))",
                foreground: "hsl(var(--popover-foreground))",
              },
              card: {
                DEFAULT: "hsl(var(--card))",
                foreground: "hsl(var(--card-foreground))",
              },
              // CHART COLORS - For data visualization
              chart: {
                '1': 'hsl(var(--chart-1))',
                '2': 'hsl(var(--chart-2))',
                '3': 'hsl(var(--chart-3))',
                '4': 'hsl(var(--chart-4))',
                '5': 'hsl(var(--chart-5))'
              }
            },

            // ENHANCED BORDER RADIUS - CSS variable-based
            borderRadius: {
              lg: "var(--radius)",
              md: "calc(var(--radius) - 2px)",
              sm: "calc(var(--radius) - 4px)",
            },

            // COMPREHENSIVE FONT FAMILIES
            fontFamily: {
              sans: [
                "var(--font-sans)",
                "ui-sans-serif",
                "system-ui",
                "-apple-system",
                "BlinkMacSystemFont",
                "Segoe UI",
                "Roboto",
                "Helvetica Neue",
                "Arial",
                "Noto Sans",
                "sans-serif",
                "Apple Color Emoji",
                "Segoe UI Emoji",
                "Segoe UI Symbol",
                "Noto Color Emoji"
              ],
              mono: [
                "var(--font-mono)",
                "ui-monospace",
                "SFMono-Regular",
                "Menlo",
                "Monaco",
                "Consolas",
                "Liberation Mono",
                "Courier New",
                "monospace"
              ],
            },

            // ANIMATION SYSTEM - Professional animations
            keyframes: {
              "accordion-down": {
                from: { height: "0" },
                to: { height: "var(--radix-accordion-content-height)" },
              },
              "accordion-up": {
                from: { height: "var(--radix-accordion-content-height)" },
                to: { height: "0" },
              },
              "fade-in": {
                "0%": { opacity: "0" },
                "100%": { opacity: "1" },
              },
              "fade-out": {
                "0%": { opacity: "1" },
                "100%": { opacity: "0" },
              },
              "slide-in-from-top": {
                "0%": { transform: "translateY(-100%)" },
                "100%": { transform: "translateY(0)" },
              },
              "slide-in-from-bottom": {
                "0%": { transform: "translateY(100%)" },
                "100%": { transform: "translateY(0)" },
              },
              "slide-in-from-left": {
                "0%": { transform: "translateX(-100%)" },
                "100%": { transform: "translateX(0)" },
              },
              "slide-in-from-right": {
                "0%": { transform: "translateX(100%)" },
                "100%": { transform: "translateX(0)" },
              },
            },
            animation: {
              "accordion-down": "accordion-down 0.2s ease-out",
              "accordion-up": "accordion-up 0.2s ease-out",
              "fade-in": "fade-in 0.2s ease-out",
              "fade-out": "fade-out 0.2s ease-out",
              "slide-in-from-top": "slide-in-from-top 0.3s ease-out",
              "slide-in-from-bottom": "slide-in-from-bottom 0.3s ease-out",
              "slide-in-from-left": "slide-in-from-left 0.3s ease-out",
              "slide-in-from-right": "slide-in-from-right 0.3s ease-out",
            },

            // SPACING SYSTEM - Enhanced spacing scale
            spacing: {
              '18': '4.5rem',
              '88': '22rem',
            },

            // SCREEN SIZES - Modern breakpoints
            screens: {
              'xs': '475px',
              '3xl': '1680px',
            },
          },
        },

        // PROFESSIONAL PLUGINS - Enable advanced features
        plugins: [
          // Enable arbitrary value support (automatically included in Tailwind 3.0+)
          // Enable container queries support
          // Enable typography support for rich text
        ],
      }
    JS
  end

  def sanitize_css_for_fallback(css_content)
    # Remove all Tailwind-specific syntax that could cause JavaScript errors
    # when injected into template literals
    sanitized = css_content.dup

    # Remove @tailwind directives completely
    sanitized.gsub!(/@tailwind\s+(base|components|utilities);?/, "")

    # Remove @layer blocks and their contents since @apply won't work without compilation
    sanitized.gsub!(/@layer\s+\w+\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m, "")

    # Remove any remaining @apply statements
    sanitized.gsub!(/@apply[^;]+;/, "")

    # Remove any remaining Tailwind-specific at-rules
    sanitized.gsub!(/@(?:responsive|screen|variants)\s*\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}/m, "")

    # Clean up excessive whitespace from removals
    sanitized.gsub!(/\n\s*\n\s*\n+/, "\n\n")
    sanitized.strip!

    # If the result is mostly empty (just CSS variables), add a basic reset
    if sanitized.length < 100 && sanitized.include?(":root")
      sanitized += "\n\n/* Basic reset for fallback */\n* { box-sizing: border-box; }\nbody { margin: 0; font-family: system-ui, sans-serif; }"
    end

    Rails.logger.info "[FastBuild] Sanitized CSS: removed Tailwind directives, #{css_content.length} → #{sanitized.length} chars"
    sanitized
  end

  def generate_hmr_client_code
    # HMR Client for ActionCable integration (preview environments only)
    # Based on ActionCable HMR Implementation Guide
    <<~JS
      // HMR Client - ActionCable Integration for App #{app.id}
      // Only enable HMR in preview environments
      (function() {
        if (!window.location.hostname.includes('preview')) return;

        console.log('[HMR Client] Initializing...');

        // Track loaded modules for hot replacement
        const modules = new Map();

        // Listen for HMR updates from parent frame
        window.addEventListener('message', async (event) => {
          // Security: Only accept messages from overskill.app
          if (!event.origin.includes('overskill.app')) return;

          const { type, path, content, files, timestamp } = event.data;

          switch (type) {
            case 'hmr_update':
              await applyHMRUpdate(path, content, timestamp);
              break;
            case 'hmr_batch':
              await applyHMRBatch(files, timestamp);
              break;
          }
        });

        async function applyHMRUpdate(path, content, timestamp) {
          console.log('[HMR] Applying update to ' + path);

          try {
            if (path.endsWith('.css')) {
              // Hot reload CSS
              updateCSS(path, content);
            } else if (path.endsWith('.tsx') || path.endsWith('.jsx')) {
              // Hot reload React component
              await updateComponent(path, content);
            } else if (path.endsWith('.ts') || path.endsWith('.js')) {
              // Hot reload JavaScript module
              await updateModule(path, content);
            }

            // Notify parent frame of success
            window.parent.postMessage({
              type: 'hmr_success',
              path,
              timestamp
            }, '*');

          } catch (error) {
            console.error('[HMR] Update failed:', error);
            window.parent.postMessage({
              type: 'hmr_error',
              path,
              error: error.message,
              timestamp
            }, '*');
          }
        }

        function updateCSS(path, content) {
          // Find or create style element for this path
          let style = document.querySelector('style[data-hmr-path="' + path + '"]');
          if (!style) {
            style = document.createElement('style');
            style.setAttribute('data-hmr-path', path);
            document.head.appendChild(style);
          }
          style.textContent = content;
        }

        async function updateComponent(path, content) {
          // Create blob URL for the new module
          const blob = new Blob([content], { type: 'application/javascript' });
          const url = URL.createObjectURL(blob);

          // Dynamic import the updated module
          const newModule = await import(url);

          // Store in module cache
          modules.set(path, newModule);

          // Trigger React Fast Refresh if available
          if (window.$RefreshReg$ && window.$RefreshSig$) {
            window.$RefreshReg$(newModule.default, path);
            window.$RefreshRuntime$.performReactRefresh();
          } else {
            // Fallback: Force re-render
            if (window.React && window.ReactDOM) {
              const root = document.getElementById('root');
              if (root && root._reactRootContainer) {
                root._reactRootContainer.render(newModule.default);
              }
            }
          }

          // Clean up blob URL
          URL.revokeObjectURL(url);
        }

        async function updateModule(path, content) {
          // Similar to component update but for regular modules
          const blob = new Blob([content], { type: 'application/javascript' });
          const url = URL.createObjectURL(blob);
          const newModule = await import(url);
          modules.set(path, newModule);
          URL.revokeObjectURL(url);

          // Re-execute dependent modules if needed
          // This would require a more sophisticated module graph
        }

        async function applyHMRBatch(files, timestamp) {
          console.log('[HMR] Applying batch update (' + Object.keys(files).length + ' files)');

          for (const [path, content] of Object.entries(files)) {
            await applyHMRUpdate(path, content, timestamp);
          }
        }

        // Notify parent that HMR client is ready
        window.parent.postMessage({ type: 'hmr_ready' }, '*');
      })();
    JS
  end

  def combine_assets(js_bundle, environment_vars = {})
    # Environment variables already replaced in source files before bundling
    # Use compiled CSS if available, otherwise fall back to CDN approach

    if @compiled_css
      # Use properly compiled Tailwind CSS
      Rails.logger.info "[FastBuild] Using compiled Tailwind CSS"
      css_content = @compiled_css
      false
    else
      # Fall back to CDN approach for backward compatibility
      Rails.logger.info "[FastBuild] Falling back to CDN Tailwind approach"
      css_files = app.app_files.select { |f| f.path.end_with?(".css") }

      # Check if CSS contains Tailwind directives
      has_tailwind_directives = css_files.any? { |f| f.content.include?("@tailwind") }

      if has_tailwind_directives
        # Extract CSS variables and custom styles (everything except @tailwind directives)
        css_content = css_files.map { |f|
          # Remove @tailwind directives but keep everything else
          f.content.gsub(/@tailwind\s+(base|components|utilities);?/, "")
        }.join("\n")
        true
      else
        # Use existing CSS as-is
        css_content = css_files.map(&:content).join("\n")
        false
      end
    end

    # Properly escape CSS for JavaScript template literals to prevent syntax errors
    # SECURITY: Multi-stage escaping to handle all CSS syntax variations
    escaped_css = css_content
      .gsub("\\", "\\\\")     # Escape backslashes first (must be first!)
      .gsub("`", '\\`')       # Escape backticks for template literals
      .gsub("$", '\\$')       # Escape dollar signs for template literals
      .gsub("</script>", '<\\/script>') # Prevent script tag injection
      .gsub("</style>", '<\\/style>')   # Prevent style tag injection
      .gsub(/\*\/\s*(?![\n\r])/, "*/\n") # Ensure comment closures have newlines

    # CRITICAL FIX: Remove problematic Tailwind CSS comments that break JavaScript parsing
    # These specific comments from Tailwind base contain text that causes syntax errors
    escaped_css.gsub(/\/\*.*?\*\//m, "") # Remove all CSS comments (non-greedy, multiline)
      .gsub(/\s+/, " ")        # Normalize ALL whitespace to single spaces (removes line breaks)
      .gsub(/;\s*/, "; ")      # Ensure proper spacing after semicolons
      .strip                   # Remove leading/trailing whitespace

    # Generate HMR client for preview environments
    generate_hmr_client_code

    # Create complete bundle with CSS and JS
    <<~JS
      end

      # Legacy Vite setup (kept for reference/fallback)
      def setup_vite_project(temp_dir, environment_vars = {})
        # Copy template structure
        FileUtils.cp_r("#{@template_path}/.", temp_dir)

        # Write all app files, overriding template files
        write_app_files(temp_dir, environment_vars)

        # No longer forcing IIFE - let Vite build with ES modules and chunks
        # This follows the lovable template approach

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
      File.join(@template_path, "node_modules/.bin/vite"),
      "node_modules/.bin/vite",
      "/usr/local/bin/vite"
    ]

    paths.each do |path|
      return path if File.exist?(path)
    end

    # Fall back to npx vite
    "npx vite"
  end
end
