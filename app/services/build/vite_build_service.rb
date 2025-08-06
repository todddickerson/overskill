module Build
  # Service to build React/TypeScript apps using Vite
  # Compiles TypeScript, bundles modules, and prepares for Cloudflare deployment
  class ViteBuildService
    attr_reader :app, :build_dir
    
    def initialize(app)
      @app = app
      @build_id = SecureRandom.hex(8)
      @build_dir = Rails.root.join('tmp', 'builds', @build_id)
    end
    
    # Main build method
    def build!
      Rails.logger.info "[ViteBuild] Starting build for app #{app.id}"
      
      begin
        prepare_build_directory
        write_app_files
        write_build_config
        install_dependencies
        run_build
        collect_artifacts
        upload_to_storage
        cleanup
        
        { success: true, build_id: @build_id, artifacts: @artifacts }
      rescue => e
        Rails.logger.error "[ViteBuild] Build failed: #{e.message}"
        cleanup
        { success: false, error: e.message }
      end
    end
    
    private
    
    def prepare_build_directory
      FileUtils.mkdir_p(@build_dir)
      FileUtils.mkdir_p(@build_dir.join('src'))
      FileUtils.mkdir_p(@build_dir.join('public'))
    end
    
    def write_app_files
      app.app_files.each do |file|
        file_path = @build_dir.join(file.path)
        FileUtils.mkdir_p(File.dirname(file_path))
        File.write(file_path, file.content)
      end
    end
    
    def write_build_config
      # Write package.json if not present
      unless File.exist?(@build_dir.join('package.json'))
        package_json = {
          name: app.slug,
          version: "1.0.0",
          type: "module",
          scripts: {
            dev: "vite",
            build: "tsc && vite build",
            preview: "vite preview"
          },
          dependencies: {
            "react": "^18.2.0",
            "react-dom": "^18.2.0",
            "@supabase/supabase-js": "^2.39.0"
          },
          devDependencies: {
            "@types/react": "^18.2.43",
            "@types/react-dom": "^18.2.17",
            "@vitejs/plugin-react": "^4.2.1",
            "typescript": "^5.3.0",
            "vite": "^5.0.8",
            "tailwindcss": "^3.4.0",
            "autoprefixer": "^10.4.16",
            "postcss": "^8.4.32"
          }
        }
        File.write(@build_dir.join('package.json'), JSON.pretty_generate(package_json))
      end
      
      # Write vite.config.ts if not present
      unless File.exist?(@build_dir.join('vite.config.ts'))
        vite_config = <<~JS
          import { defineConfig } from 'vite'
          import react from '@vitejs/plugin-react'
          
          export default defineConfig({
            plugins: [react()],
            build: {
              outDir: 'dist',
              sourcemap: false,
              minify: true
            }
          })
        JS
        File.write(@build_dir.join('vite.config.ts'), vite_config)
      end
      
      # Write tsconfig.json if not present
      unless File.exist?(@build_dir.join('tsconfig.json'))
        tsconfig = {
          compilerOptions: {
            target: "ES2020",
            useDefineForClassFields: true,
            lib: ["ES2020", "DOM", "DOM.Iterable"],
            module: "ESNext",
            skipLibCheck: true,
            moduleResolution: "bundler",
            allowImportingTsExtensions: true,
            resolveJsonModule: true,
            isolatedModules: true,
            noEmit: true,
            jsx: "react-jsx",
            strict: true
          },
          include: ["src"],
          references: [{ path: "./tsconfig.node.json" }]
        }
        File.write(@build_dir.join('tsconfig.json'), JSON.pretty_generate(tsconfig))
      end
      
      # Write minimal tsconfig.node.json
      tsconfig_node = {
        compilerOptions: {
          composite: true,
          skipLibCheck: true,
          module: "ESNext",
          moduleResolution: "bundler",
          allowSyntheticDefaultImports: true
        },
        include: ["vite.config.ts"]
      }
      File.write(@build_dir.join('tsconfig.node.json'), JSON.pretty_generate(tsconfig_node))
    end
    
    def install_dependencies
      Rails.logger.info "[ViteBuild] Installing dependencies..."
      
      # Use npm for now (could switch to pnpm/yarn)
      result = system("cd #{@build_dir} && npm install --silent 2>&1")
      
      unless result
        raise "Failed to install dependencies"
      end
    end
    
    def run_build
      Rails.logger.info "[ViteBuild] Running vite build..."
      
      # Run the build
      result = system("cd #{@build_dir} && npm run build 2>&1")
      
      unless result
        raise "Build failed"
      end
    end
    
    def collect_artifacts
      @artifacts = {}
      dist_dir = @build_dir.join('dist')
      
      return unless Dir.exist?(dist_dir)
      
      Dir.glob("#{dist_dir}/**/*").each do |file|
        next if File.directory?(file)
        
        relative_path = file.sub("#{dist_dir}/", '')
        @artifacts[relative_path] = File.read(file)
      end
      
      Rails.logger.info "[ViteBuild] Collected #{@artifacts.keys.size} artifacts"
    end
    
    def upload_to_storage
      # For now, save to app_files as built artifacts
      # Later: Upload to Cloudflare R2
      
      @artifacts.each do |path, content|
        built_path = "dist/#{path}"
        
        # Check if file exists
        existing = app.app_files.find_by(path: built_path)
        
        if existing
          existing.update!(content: content)
        else
          app.app_files.create!(
            team: app.team,
            path: built_path,
            content: content,
            file_type: detect_file_type(path),
            is_built: true # Add this column to track built files
          )
        end
      end
      
      # Update app status
      app.update!(
        last_built_at: Time.current,
        build_status: 'success'
      )
    end
    
    def cleanup
      FileUtils.rm_rf(@build_dir) if Dir.exist?(@build_dir)
    end
    
    def detect_file_type(path)
      ext = File.extname(path).delete('.')
      case ext
      when 'html' then 'html'
      when 'js', 'mjs' then 'js'
      when 'css' then 'css'
      when 'json' then 'json'
      when 'map' then 'sourcemap'
      else 'text'
      end
    end
  end
end