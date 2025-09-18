# Service for building React/TypeScript apps using Vite
class Deployment::ViteBuildService
  include HTTParty

  def initialize(app)
    @app = app
    @temp_dir = nil
  end

  def build_app!
    Rails.logger.info "[ViteBuild] Starting build for app #{@app.id}"

    # Create temporary directory for build
    @temp_dir = Dir.mktmpdir("overskill-build-#{@app.id}")

    begin
      # 1. Write all app files to temp directory
      write_app_files!

      # 2. Install dependencies
      install_dependencies!

      # 3. Run Vite build
      run_vite_build!

      # 4. Read built artifacts
      built_files = read_built_artifacts!

      Rails.logger.info "[ViteBuild] Build complete for app #{@app.id} - #{built_files.keys.count} files"

      {success: true, files: built_files, build_dir: @temp_dir}
    rescue => e
      Rails.logger.error "[ViteBuild] Build failed for app #{@app.id}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n") if Rails.env.development?

      {success: false, error: e.message}
    ensure
      # Clean up temp directory after a delay to allow reading
      cleanup_temp_dir! if @temp_dir
    end
  end

  private

  def write_app_files!
    Rails.logger.info "[ViteBuild] Writing #{@app.app_files.count} files to #{@temp_dir}"

    @app.app_files.each do |app_file|
      file_path = File.join(@temp_dir, app_file.path)

      # Create directory if it doesn't exist
      FileUtils.mkdir_p(File.dirname(file_path))

      # Write file content
      File.write(file_path, app_file.content)
    end

    # Ensure package.json exists with required dependencies
    ensure_package_json!
  end

  def ensure_package_json!
    package_json_path = File.join(@temp_dir, "package.json")

    unless File.exist?(package_json_path)
      # Create default package.json if missing
      package_json = {
        "name" => "overskill-app-#{@app.id}",
        "private" => true,
        "version" => "0.0.0",
        "type" => "module",
        "scripts" => {
          "dev" => "vite",
          "build" => "vite build",
          "preview" => "vite preview"
        },
        "dependencies" => {
          "react" => "^18.2.0",
          "react-dom" => "^18.2.0"
        },
        "devDependencies" => {
          "@types/react" => "^18.2.66",
          "@types/react-dom" => "^18.2.22",
          "@vitejs/plugin-react-swc" => "^3.11.0",
          "typescript" => "^5.2.2",
          "vite" => "^5.2.0"
        }
      }

      File.write(package_json_path, JSON.pretty_generate(package_json))
      Rails.logger.info "[ViteBuild] Created default package.json"
    end

    # Ensure vite.config.ts exists
    ensure_vite_config!
  end

  def ensure_vite_config!
    vite_config_path = File.join(@temp_dir, "vite.config.ts")

    unless File.exist?(vite_config_path)
      vite_config = <<~TS
        import { defineConfig } from 'vite'
        import react from '@vitejs/plugin-react-swc'

        // https://vitejs.dev/config/
        export default defineConfig({
          plugins: [react()],
          build: {
            outDir: 'dist',
            assetsDir: 'assets',
            sourcemap: false,
            minify: 'terser'
          }
        })
      TS

      File.write(vite_config_path, vite_config)
      Rails.logger.info "[ViteBuild] Created default vite.config.ts"
    end
  end

  def install_dependencies!
    Rails.logger.info "[ViteBuild] Installing dependencies"

    # Check if npm is available
    unless system("which npm > /dev/null 2>&1")
      raise "npm is not installed or not in PATH"
    end

    # Run npm install
    Dir.chdir(@temp_dir) do
      install_output = `npm install 2>&1`
      install_status = $?.success?

      unless install_status
        Rails.logger.error "[ViteBuild] npm install failed: #{install_output}"
        raise "npm install failed: #{install_output}"
      end

      Rails.logger.info "[ViteBuild] Dependencies installed successfully"
    end
  end

  def run_vite_build!
    Rails.logger.info "[ViteBuild] Running Vite build"

    Dir.chdir(@temp_dir) do
      build_output = `npm run build 2>&1`
      build_status = $?.success?

      unless build_status
        Rails.logger.error "[ViteBuild] Vite build failed: #{build_output}"
        raise "Vite build failed: #{build_output}"
      end

      Rails.logger.info "[ViteBuild] Vite build completed successfully"
    end
  end

  def read_built_artifacts!
    dist_dir = File.join(@temp_dir, "dist")

    unless File.directory?(dist_dir)
      raise "Build output directory 'dist' not found after Vite build"
    end

    built_files = {}

    # Read all files from dist directory recursively
    Dir.glob("#{dist_dir}/**/*", File::FNM_DOTMATCH).each do |file_path|
      next if File.directory?(file_path)
      next if File.basename(file_path).start_with?(".")

      # Get relative path from dist directory
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(dist_dir)).to_s

      # Read file content
      built_files[relative_path] = if binary_file?(file_path)
        # For binary files, encode as base64
        {
          content: Base64.encode64(File.read(file_path)),
          binary: true,
          content_type: get_content_type(relative_path)
        }
      else
        # For text files, read as string
        {
          content: File.read(file_path),
          binary: false,
          content_type: get_content_type(relative_path)
        }
      end
    end

    Rails.logger.info "[ViteBuild] Read #{built_files.keys.count} built files"
    built_files
  end

  def binary_file?(file_path)
    # Check if file is binary based on extension
    binary_extensions = %w[.png .jpg .jpeg .gif .ico .woff .woff2 .ttf .eot .svg]
    extension = File.extname(file_path).downcase
    binary_extensions.include?(extension)
  end

  def get_content_type(file_path)
    extension = File.extname(file_path).downcase

    case extension
    when ".html" then "text/html"
    when ".js", ".mjs" then "application/javascript"
    when ".css" then "text/css"
    when ".json" then "application/json"
    when ".png" then "image/png"
    when ".jpg", ".jpeg" then "image/jpeg"
    when ".gif" then "image/gif"
    when ".ico" then "image/x-icon"
    when ".svg" then "image/svg+xml"
    when ".woff" then "font/woff"
    when ".woff2" then "font/woff2"
    when ".ttf" then "font/ttf"
    when ".eot" then "application/vnd.ms-fontobject"
    else "application/octet-stream"
    end
  end

  def cleanup_temp_dir!
    return unless @temp_dir && File.directory?(@temp_dir)

    # Schedule cleanup for later to allow reading built files
    Thread.new do
      sleep 30 # Wait 30 seconds before cleanup
      FileUtils.rm_rf(@temp_dir) if File.directory?(@temp_dir)
      Rails.logger.info "[ViteBuild] Cleaned up temp directory #{@temp_dir}"
    rescue => e
      Rails.logger.warn "[ViteBuild] Failed to clean up temp directory: #{e.message}"
    end
  end
end
