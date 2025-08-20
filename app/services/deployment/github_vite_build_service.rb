# Service for building and deploying Vite apps from GitHub repositories
class Deployment::GithubViteBuildService
  include HTTParty
  
  def initialize(app)
    @app = app
    @temp_dir = nil
    @cloudflare_token = ENV['CLOUDFLARE_API_TOKEN']
    @cloudflare_account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
  end
  
  def build_and_deploy!
    Rails.logger.info "[GithubViteBuild] Starting build for app #{@app.id} from repository"
    
    return { success: false, error: 'No repository URL' } unless @app.repository_url
    return { success: false, error: 'No worker name' } unless @app.cloudflare_worker_name
    
    @temp_dir = Dir.mktmpdir("github-build-#{@app.id}")
    
    begin
      # 1. Clone repository from GitHub
      clone_repository!
      
      # 2. Install dependencies
      install_dependencies!
      
      # 3. Build the Vite app
      run_vite_build!
      
      # 4. Deploy to Cloudflare Worker
      deploy_to_cloudflare!
      
      Rails.logger.info "[GithubViteBuild] ✅ Build and deploy complete for app #{@app.id}"
      
      { success: true, worker_url: worker_url }
      
    rescue => e
      Rails.logger.error "[GithubViteBuild] Build failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      
      { success: false, error: e.message }
      
    ensure
      cleanup_temp_dir! if @temp_dir
    end
  end
  
  private
  
  def clone_repository!
    Rails.logger.info "[GithubViteBuild] Cloning repository: #{@app.repository_url}"
    
    # Use GitHub App token for authentication
    authenticator = Deployment::GithubAppAuthenticator.new
    token = authenticator.get_installation_token(ENV['GITHUB_ORG'])
    
    # Clone with token authentication
    clone_url = @app.repository_url.gsub('https://github.com/', "https://#{token}@github.com/")
    
    result = system("git clone --depth 1 #{clone_url} #{@temp_dir} 2>&1")
    raise "Failed to clone repository" unless result
    
    Rails.logger.info "[GithubViteBuild] Repository cloned successfully"
  end
  
  def install_dependencies!
    Rails.logger.info "[GithubViteBuild] Installing dependencies..."
    
    Dir.chdir(@temp_dir) do
      result = system("npm install --silent 2>&1")
      raise "Failed to install dependencies" unless result
    end
    
    Rails.logger.info "[GithubViteBuild] Dependencies installed"
  end
  
  def run_vite_build!
    Rails.logger.info "[GithubViteBuild] Running Vite build..."
    
    Dir.chdir(@temp_dir) do
      # Set environment variables for the build
      env = {
        'VITE_APP_ID' => @app.obfuscated_id,
        'VITE_SUPABASE_URL' => ENV['SUPABASE_URL'],
        'VITE_SUPABASE_ANON_KEY' => ENV['SUPABASE_ANON_KEY'],
        'NODE_ENV' => 'production'
      }
      
      result = system(env, "npm run build 2>&1")
      raise "Vite build failed" unless result
    end
    
    Rails.logger.info "[GithubViteBuild] Build completed"
  end
  
  def deploy_to_cloudflare!
    Rails.logger.info "[GithubViteBuild] Deploying to Cloudflare Worker..."
    
    # Read the built files
    dist_dir = File.join(@temp_dir, 'dist')
    raise "Build directory not found" unless Dir.exist?(dist_dir)
    
    # Create worker script that serves the built app
    worker_script = generate_worker_script(dist_dir)
    
    # Deploy to Cloudflare
    deploy_worker(worker_script)
    
    Rails.logger.info "[GithubViteBuild] Deployed to Cloudflare"
  end
  
  def generate_worker_script(dist_dir)
    # Read index.html
    index_html = File.read(File.join(dist_dir, 'index.html'))
    
    # Read all assets and create a simple file map
    assets = {}
    Dir.glob(File.join(dist_dir, 'assets', '*')).each do |file|
      filename = File.basename(file)
      content = File.read(file)
      content_type = case File.extname(file)
                      when '.js' then 'application/javascript'
                      when '.css' then 'text/css'
                      when '.svg' then 'image/svg+xml'
                      else 'application/octet-stream'
                      end
      assets["/assets/#{filename}"] = { content: content, type: content_type }
    end
    
    # Generate worker script that serves the files
    <<~JS
      const HTML = #{index_html.inspect};
      const ASSETS = #{assets.to_json};
      
      export default {
        async fetch(request, env, ctx) {
          const url = new URL(request.url);
          const path = url.pathname;
          
          // Serve assets
          if (path.startsWith('/assets/')) {
            const asset = ASSETS[path];
            if (asset) {
              return new Response(asset.content, {
                headers: {
                  'Content-Type': asset.type,
                  'Cache-Control': 'public, max-age=31536000, immutable'
                }
              });
            }
          }
          
          // Serve index.html for all other routes (SPA)
          return new Response(HTML, {
            headers: {
              'Content-Type': 'text/html; charset=utf-8',
              'Cache-Control': 'public, max-age=3600'
            }
          });
        }
      };
    JS
  end
  
  def deploy_worker(worker_script)
    worker_name = @app.cloudflare_worker_name
    
    # Create multipart form data
    metadata = {
      'main_module' => 'worker.js',
      'compatibility_date' => '2024-08-01',
      'compatibility_flags' => ['nodejs_compat']
    }
    
    boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
    body = []
    body << "--#{boundary}"
    body << 'Content-Disposition: form-data; name="metadata"'
    body << ''
    body << metadata.to_json
    body << "--#{boundary}"
    body << 'Content-Disposition: form-data; name="worker.js"; filename="worker.js"'
    body << 'Content-Type: application/javascript+module'
    body << ''
    body << worker_script
    body << "--#{boundary}--"
    
    uri = URI("https://api.cloudflare.com/client/v4/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}")
    req = Net::HTTP::Put.new(uri)
    req['Authorization'] = "Bearer #{@cloudflare_token}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = body.join("\r\n")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.request(req)
    
    raise "Worker deployment failed: #{response.code} - #{response.body}" unless response.code == '200'
    
    # Update app deployment status
    @app.update!(
      deployment_status: 'deployed',
      last_deployment_at: Time.current
    )
  end
  
  def worker_url
    # Get the account subdomain
    subdomain_response = HTTParty.get(
      "https://api.cloudflare.com/client/v4/accounts/#{@cloudflare_account_id}/workers/subdomain",
      headers: {
        'Authorization' => "Bearer #{@cloudflare_token}",
        'Content-Type' => 'application/json'
      }
    )
    
    subdomain = subdomain_response.dig('result', 'subdomain') || 'workers'
    "https://#{@app.cloudflare_worker_name}.#{subdomain}.workers.dev"
  end
  
  def cleanup_temp_dir!
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end
end