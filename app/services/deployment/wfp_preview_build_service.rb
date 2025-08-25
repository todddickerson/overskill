# Service for building Vite apps for WFP preview environments
# Bridges the gap between raw source files and production builds
class Deployment::WfpPreviewBuildService
  def initialize(app)
    @app = app
    @temp_dir = nil
  end
  
  # Build app files and return built files for KV upload
  def build_for_preview
    Rails.logger.info "[WfpPreviewBuild] Building app #{@app.id} for live preview"
    
    @temp_dir = Dir.mktmpdir("wfp-preview-build-#{@app.id}")
    
    begin
      # 1. Write source files to temp directory
      write_source_files_to_disk
      
      # 2. Install dependencies
      install_dependencies
      
      # 3. Build with Vite
      run_vite_build
      
      # 4. Read built files from dist/
      built_files = read_built_files
      
      Rails.logger.info "[WfpPreviewBuild] ✅ Build complete: #{built_files.count} files generated"
      
      { success: true, files: built_files }
      
    rescue => e
      Rails.logger.error "[WfpPreviewBuild] Build failed: #{e.message}"
      
      # Fall back to raw source files on build failure
      raw_files = @app.app_files.map { |f| { path: f.path, content: f.content } }
      { success: false, error: e.message, files: raw_files }
      
    ensure
      cleanup_temp_dir
    end
  end
  
  private
  
  def write_source_files_to_disk
    Rails.logger.info "[WfpPreviewBuild] Writing #{@app.app_files.count} source files to #{@temp_dir}"
    
    @app.app_files.each do |file|
      file_path = File.join(@temp_dir, file.path)
      
      # Create directory structure
      FileUtils.mkdir_p(File.dirname(file_path))
      
      # Write file content
      File.write(file_path, file.content)
    end
  end
  
  def install_dependencies
    Rails.logger.info "[WfpPreviewBuild] Installing dependencies..."
    
    Dir.chdir(@temp_dir) do
      # Use npm ci for faster, reproducible builds if package-lock.json exists
      install_cmd = File.exist?('package-lock.json') ? 'npm ci' : 'npm install'
      
      result = system("#{install_cmd} --silent 2>&1")
      raise "Failed to install dependencies" unless result
    end
    
    Rails.logger.info "[WfpPreviewBuild] Dependencies installed"
  end
  
  def run_vite_build
    Rails.logger.info "[WfpPreviewBuild] Running Vite build..."
    
    Dir.chdir(@temp_dir) do
      # Set environment variables for the build
      env = {
        'VITE_APP_ID' => @app.obfuscated_id,
        'VITE_SUPABASE_URL' => ENV['SUPABASE_URL'],
        'VITE_SUPABASE_ANON_KEY' => ENV['SUPABASE_ANON_KEY'],
        'NODE_ENV' => 'production'
      }
      
      # Run build command (typically 'tsc && vite build')
      result = system(env, "npm run build 2>&1")
      raise "Vite build failed" unless result
    end
    
    Rails.logger.info "[WfpPreviewBuild] Vite build completed"
  end
  
  def read_built_files
    dist_dir = File.join(@temp_dir, 'dist')
    raise "Build output directory not found at #{dist_dir}" unless Dir.exist?(dist_dir)
    
    built_files = []
    
    # Read all files from dist/ directory
    Dir.glob(File.join(dist_dir, '**', '*'), File::FNM_DOTMATCH).each do |file_path|
      next if File.directory?(file_path)
      
      # Calculate relative path from dist/
      relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(dist_dir)).to_s
      
      # Read file content
      content = File.read(file_path)
      
      built_files << {
        path: relative_path,
        content: content,
        built: true
      }
    end
    
    Rails.logger.info "[WfpPreviewBuild] Read #{built_files.count} built files from dist/"
    built_files
  end
  
  def cleanup_temp_dir
    return unless @temp_dir && Dir.exist?(@temp_dir)
    
    Rails.logger.info "[WfpPreviewBuild] Cleaning up temp directory #{@temp_dir}"
    FileUtils.rm_rf(@temp_dir)
  rescue => e
    Rails.logger.warn "[WfpPreviewBuild] Failed to cleanup temp directory: #{e.message}"
  end
end