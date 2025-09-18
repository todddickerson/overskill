# FastBuildService - Server-side ESBuild compilation for instant preview updates
# Compiles TypeScript/React code in <100ms for HMR without full deployment
# Part of the Fast Deployment Architecture achieving sub-10s preview updates
#
# Performance targets:
# - Single file compilation: <100ms
# - Full app bundle: <2s
# - Incremental builds: <500ms

require "open3"
require "tempfile"
require "json"

class FastBuildService
  attr_reader :app, :build_cache

  # Cache compiled modules for instant subsequent loads
  CACHE_TTL = 5.minutes

  # ESBuild configuration optimized for speed
  ESBUILD_OPTIONS = {
    bundle: true,
    format: "esm",
    target: "es2020",
    jsx: "automatic",
    jsxImportSource: "react",
    sourcemap: "inline",
    minify: false, # Skip minification for preview builds
    treeShaking: false, # Skip tree shaking for speed
    splitting: false, # Disable code splitting for preview
    platform: "browser",
    loader: {
      ".tsx": "tsx",
      ".ts": "ts",
      ".jsx": "jsx",
      ".js": "js",
      ".css": "css",
      ".png": "dataurl",
      ".jpg": "dataurl",
      ".svg": "text"
    }
  }.freeze

  def initialize(app)
    @app = app
    @build_cache = Rails.cache
    @esbuild_path = find_esbuild_binary
  end

  # Build a single file asynchronously with caching
  def build_file_async(file_path, content, &block)
    cache_key = "fast_build:#{app.id}:#{file_path}:#{Digest::MD5.hexdigest(content)}"

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
        result = compile_file(file_path, content)

        # Cache successful builds
        if result[:success]
          build_cache.write(cache_key, result, expires_in: CACHE_TTL)
        end

        block.call(result)
      end
    end
  end

  # Compile a single component for HMR
  def compile_component(content, &block)
    Thread.new do
      Rails.application.executor.wrap do
        start_time = Time.current

        # Create temp file for ESBuild
        temp_file = Tempfile.new(["component", ".tsx"])
        temp_file.write(wrap_component_for_hmr(content))
        temp_file.close

        begin
          # Run ESBuild with optimized settings
          output = run_esbuild(temp_file.path, component_mode: true)

          if output[:success]
            Rails.logger.info "[FastBuild] Component compiled in #{((Time.current - start_time) * 1000).round}ms"
            block.call({
              success: true,
              compiled_code: output[:code],
              source_map: output[:source_map]
            })
          else
            block.call({
              success: false,
              error: output[:error]
            })
          end
        ensure
          temp_file.unlink
        end
      end
    end
  end

  # Build entire app bundle for initial preview
  def build_full_bundle
    start_time = Time.current

    Rails.logger.info "[FastBuild] Building full bundle for app #{app.id}"

    # Create temp directory structure
    Dir.mktmpdir do |temp_dir|
      # Write all app files to temp directory
      app.app_files.each do |file|
        file_path = File.join(temp_dir, file.path)
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, file.content)
      end

      # Add package.json if not present
      package_json_path = File.join(temp_dir, "package.json")
      unless File.exist?(package_json_path)
        File.write(package_json_path, generate_package_json)
      end

      # Add entry point
      entry_point = File.join(temp_dir, "src/main.tsx")
      unless File.exist?(entry_point)
        File.write(entry_point, generate_entry_point)
      end

      # Run ESBuild
      output = run_esbuild(entry_point, {
        outdir: File.join(temp_dir, "dist"),
        full_bundle: true
      })

      if output[:success]
        # Read compiled files
        bundle_path = File.join(temp_dir, "dist/main.js")
        bundle_content = File.read(bundle_path) if File.exist?(bundle_path)

        build_time = ((Time.current - start_time) * 1000).round
        Rails.logger.info "[FastBuild] Full bundle built in #{build_time}ms"

        {
          success: true,
          bundle: bundle_content,
          build_time: build_time,
          files_count: app.app_files.count
        }
      else
        {
          success: false,
          error: output[:error]
        }
      end
    end
  end

  # Incremental build for file changes
  def incremental_build(changed_files)
    start_time = Time.current

    Rails.logger.info "[FastBuild] Incremental build for #{changed_files.size} files"

    results = changed_files.map do |file_path|
      file = app.app_files.find_by(path: file_path)
      next unless file

      compile_file(file_path, file.content)
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

  def compile_file(file_path, content)
    # Skip non-compilable files
    return {success: true, compiled_content: content} unless needs_compilation?(file_path)

    Tempfile.create(["build", File.extname(file_path)]) do |temp_file|
      temp_file.write(content)
      temp_file.close

      output = run_esbuild(temp_file.path)

      if output[:success]
        {
          success: true,
          compiled_content: output[:code],
          source_map: output[:source_map]
        }
      else
        {
          success: false,
          error: output[:error]
        }
      end
    end
  end

  def run_esbuild(input_path, options = {})
    cmd_options = ESBUILD_OPTIONS.dup

    # Adjust options based on mode
    if options[:component_mode]
      cmd_options[:bundle] = false
      cmd_options[:format] = "esm"
    elsif options[:full_bundle]
      cmd_options[:bundle] = true
      cmd_options[:splitting] = true
      cmd_options[:outdir] = options[:outdir]
    end

    # Build command line arguments
    args = build_esbuild_args(cmd_options)

    # Execute ESBuild
    stdout, stderr, status = Open3.capture3(
      @esbuild_path,
      input_path,
      *args
    )

    if status.success?
      {
        success: true,
        code: stdout,
        source_map: extract_source_map(stdout)
      }
    else
      Rails.logger.error "[FastBuild] ESBuild error: #{stderr}"
      {
        success: false,
        error: stderr
      }
    end
  rescue => e
    Rails.logger.error "[FastBuild] Build failed: #{e.message}"
    {
      success: false,
      error: e.message
    }
  end

  def build_esbuild_args(options)
    args = []

    options.each do |key, value|
      case value
      when true
        args << "--#{key.to_s.tr("_", "-")}"
      when false
        # Skip false boolean options
      when Hash
        # Handle loader options
        value.each do |ext, loader|
          args << "--loader:#{ext}=#{loader}"
        end
      else
        args << "--#{key.to_s.tr("_", "-")}=#{value}"
      end
    end

    args
  end

  def wrap_component_for_hmr(content)
    # Wrap component with HMR runtime
    <<~JS
      import { hot } from '@hmr/runtime';
      
      #{content}
      
      if (import.meta.hot) {
        import.meta.hot.accept();
      }
    JS
  end

  def generate_package_json
    {
      name: "app-#{app.id}",
      version: "1.0.0",
      type: "module",
      dependencies: {
        react: "^18.2.0",
        "react-dom": "^18.2.0",
        "react-router-dom": "^6.20.0"
      }
    }.to_json
  end

  def generate_entry_point
    <<~TSX
      import React from 'react';
      import ReactDOM from 'react-dom/client';
      import App from './App';
      import './index.css';

      ReactDOM.createRoot(document.getElementById('root')!).render(
        <React.StrictMode>
          <App />
        </React.StrictMode>
      );
    TSX
  end

  def needs_compilation?(file_path)
    %w[.ts .tsx .js .jsx].include?(File.extname(file_path))
  end

  def extract_source_map(code)
    # Extract inline source map if present
    match = code.match(/\/\/# sourceMappingURL=data:application\/json;base64,(.+)/)
    return nil unless match

    Base64.decode64(match[1])
  end

  def find_esbuild_binary
    # Try common locations
    paths = [
      "node_modules/.bin/esbuild",
      "/usr/local/bin/esbuild",
      "/opt/homebrew/bin/esbuild"
    ]

    paths.each do |path|
      full_path = Rails.root.join(path).to_s
      return full_path if File.exist?(full_path)
    end

    # Fall back to system esbuild
    "esbuild"
  end
end
