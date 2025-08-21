# DEPRECATED: This service is replaced by WorkersForPlatformsService
# AutomatedCloudflareDeploymentService was used for individual Cloudflare Workers per app
# Now using Workers for Platforms (WFP) with dispatch namespaces for unlimited apps
# See: app/services/deployment/workers_for_platforms_service.rb
#
# Automated Cloudflare Deployment Service
# Deploys static React apps from GitHub repositories to Cloudflare Workers
# Uses Wrangler API directly - no dashboard configuration needed

class Deployment::AutomatedCloudflareDeploymentService
  include HTTParty
  base_uri 'https://api.cloudflare.com/client/v4'

  def initialize(app)
    @app = app
    @cloudflare_token = ENV['CLOUDFLARE_API_TOKEN']
    @cloudflare_account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @github_org = ENV['GITHUB_ORG']
    @temp_dir = nil
    
    raise "Missing Cloudflare credentials" unless [@cloudflare_token, @cloudflare_account_id].all?(&:present?)
    
    self.class.headers({
      'Authorization' => "Bearer #{@cloudflare_token}",
      'Content-Type' => 'application/json'
    })
  end

  # Deploy app from GitHub repository to Cloudflare Workers
  def deploy_from_repository(repo_result)
    worker_name = generate_worker_name
    repo_name = repo_result[:repo_name]
    
    Rails.logger.info "[AutomatedDeploy] Deploying #{repo_name} as #{worker_name}"
    
    @temp_dir = Dir.mktmpdir("deploy-#{@app.id}")
    
    begin
      # Step 1: Clone the repository
      clone_repository(repo_name)
      
      # Step 2: Update wrangler.toml with correct values
      update_wrangler_config(worker_name)
      
      # Step 3: Install dependencies and build
      build_application
      
      # Step 4: Deploy to Cloudflare using Wrangler API
      deployment_result = deploy_to_cloudflare(worker_name)
      
      # Step 5: Set environment variables
      setup_environment_variables(worker_name)
      
      # Get the account subdomain for URLs
      subdomain = get_account_subdomain
      worker_url = "https://#{worker_name}.#{subdomain}.workers.dev"
      
      # Update app with deployment info
      @app.update!(
        cloudflare_worker_name: worker_name,
        preview_url: worker_url,
        deployment_status: 'deployed',
        last_deployed_at: Time.current
      )
      
      Rails.logger.info "[AutomatedDeploy] ✅ Deployment successful: #{worker_url}"
      
      {
        success: true,
        worker_name: worker_name,
        worker_url: worker_url,
        deployment_time: Time.current
      }
      
    rescue => e
      Rails.logger.error "[AutomatedDeploy] Deployment failed: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
      { success: false, error: e.message }
      
    ensure
      cleanup_temp_dir
    end
  end

  # Redeploy when repository is updated
  def redeploy_on_push
    return { success: false, error: 'No worker configured' } unless @app.cloudflare_worker_name
    
    deploy_from_repository({
      repo_name: @app.repository_name,
      success: true
    })
  end

  private

  def clone_repository(repo_name)
    Rails.logger.info "[AutomatedDeploy] Cloning repository..."
    
    # Get GitHub App token
    authenticator = Deployment::GithubAppAuthenticator.new
    token = authenticator.get_installation_token(@github_org)
    
    clone_url = "https://#{token}@github.com/#{@github_org}/#{repo_name}.git"
    
    result = system("git clone --depth 1 #{clone_url} #{@temp_dir} 2>&1")
    raise "Failed to clone repository" unless result
    
    Rails.logger.info "[AutomatedDeploy] Repository cloned"
  end

  def update_wrangler_config(worker_name)
    Rails.logger.info "[AutomatedDeploy] Updating wrangler.toml..."
    
    wrangler_path = File.join(@temp_dir, 'wrangler.toml')
    
    if File.exist?(wrangler_path)
      # Read existing wrangler.toml
      content = File.read(wrangler_path)
      
      # Replace placeholders
      content.gsub!('app-{{APP_ID}}', worker_name)
      content.gsub!('{{SUPABASE_URL}}', ENV['SUPABASE_URL'])
      content.gsub!('{{SUPABASE_ANON_KEY}}', ENV['SUPABASE_ANON_KEY'])
      content.gsub!('{{APP_ID}}', @app.obfuscated_id)
      content.gsub!('{{OWNER_ID}}', @app.team.id.to_s)
      
      # Remove route configuration (we'll use workers.dev)
      content.gsub!(/\[\[routes\]\].*?zone_name = "overskill.app"/m, '')
      
      File.write(wrangler_path, content)
    else
      # Create wrangler.toml if it doesn't exist
      create_wrangler_config(worker_name, wrangler_path)
    end
    
    Rails.logger.info "[AutomatedDeploy] wrangler.toml updated"
  end

  def create_wrangler_config(worker_name, path)
    content = <<~TOML
      name = "#{worker_name}"
      main = "dist/index.js"
      compatibility_date = "2024-08-01"
      
      [site]
      bucket = "./dist"
      
      [build]
      command = "npm run build"
      
      [vars]
      VITE_SUPABASE_URL = "#{ENV['SUPABASE_URL']}"
      VITE_SUPABASE_ANON_KEY = "#{ENV['SUPABASE_ANON_KEY']}"
      VITE_APP_ID = "#{@app.obfuscated_id}"
      VITE_OWNER_ID = "#{@app.team.id}"
      VITE_ENVIRONMENT = "production"
    TOML
    
    File.write(path, content)
  end

  def build_application
    Rails.logger.info "[AutomatedDeploy] Building application..."
    
    Dir.chdir(@temp_dir) do
      # Install dependencies
      Rails.logger.info "[AutomatedDeploy] Installing dependencies..."
      result = system("npm install --silent 2>&1")
      raise "Failed to install dependencies" unless result
      
      # Build the application
      Rails.logger.info "[AutomatedDeploy] Running build..."
      env_vars = {
        'VITE_APP_ID' => @app.obfuscated_id,
        'VITE_SUPABASE_URL' => ENV['SUPABASE_URL'],
        'VITE_SUPABASE_ANON_KEY' => ENV['SUPABASE_ANON_KEY'],
        'NODE_ENV' => 'production'
      }
      
      result = system(env_vars, "npm run build 2>&1")
      raise "Build failed" unless result
    end
    
    Rails.logger.info "[AutomatedDeploy] Build complete"
  end

  def deploy_to_cloudflare(worker_name)
    Rails.logger.info "[AutomatedDeploy] Deploying to Cloudflare..."
    
    Dir.chdir(@temp_dir) do
      # Read the built files
      dist_dir = File.join(@temp_dir, 'dist')
      raise "Build directory not found" unless Dir.exist?(dist_dir)
      
      # Create worker script for serving static files
      worker_script = create_static_site_worker
      
      # Deploy using multipart upload
      deploy_worker_with_assets(worker_name, worker_script, dist_dir)
    end
    
    Rails.logger.info "[AutomatedDeploy] Deployment complete"
    { success: true }
  end

  def create_static_site_worker
    # Worker script that serves static files for the React app
    <<~JS
      export default {
        async fetch(request, env, ctx) {
          const url = new URL(request.url);
          
          // Try to serve the requested path
          try {
            // For API routes, you could proxy to Supabase here
            if (url.pathname.startsWith('/api/')) {
              return new Response('API not implemented', { status: 501 });
            }
            
            // Serve static files - this will be handled by Cloudflare's [site] configuration
            // The actual serving is done by Cloudflare, not this script
            return env.ASSETS.fetch(request);
          } catch (e) {
            // For client-side routing, return index.html for any 404
            if (request.method === 'GET') {
              const indexRequest = new Request(url.origin + '/index.html', request);
              return env.ASSETS.fetch(indexRequest);
            }
            
            return new Response('Not found', { status: 404 });
          }
        }
      };
    JS
  end

  def deploy_worker_with_assets(worker_name, worker_script, dist_dir)
    # Create metadata for the worker
    metadata = {
      'main_module' => 'worker.js',
      'compatibility_date' => '2024-08-01'
    }
    
    # Prepare multipart form data
    boundary = "----WebKitFormBoundary#{SecureRandom.hex(8)}"
    body = []
    
    # Add metadata
    body << "--#{boundary}"
    body << 'Content-Disposition: form-data; name="metadata"'
    body << ''
    body << metadata.to_json
    
    # Add worker script
    body << "--#{boundary}"
    body << 'Content-Disposition: form-data; name="worker.js"; filename="worker.js"'
    body << 'Content-Type: application/javascript+module'
    body << ''
    body << worker_script
    
    # Note: For static sites, we should use Wrangler CLI or Pages API
    # Workers API doesn't directly support [site] bucket uploads
    # This is a simplified version - in production, use wrangler deploy
    
    # For now, we'll deploy the worker and note that assets need separate handling
    body << "--#{boundary}--"
    
    uri = URI("https://api.cloudflare.com/client/v4/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}")
    req = Net::HTTP::Put.new(uri)
    req['Authorization'] = "Bearer #{@cloudflare_token}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = body.join("\r\n")
    
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    response = http.request(req)
    
    if response.code != '200'
      # If API deployment fails, try using wrangler CLI as fallback
      Rails.logger.info "[AutomatedDeploy] API deployment failed, using wrangler CLI..."
      deploy_with_wrangler_cli(worker_name)
    end
  end

  def deploy_with_wrangler_cli(worker_name)
    # Use wrangler CLI for deployment (handles [site] bucket properly)
    Dir.chdir(@temp_dir) do
      # Set up wrangler authentication
      env_vars = {
        'CLOUDFLARE_API_TOKEN' => @cloudflare_token,
        'CLOUDFLARE_ACCOUNT_ID' => @cloudflare_account_id
      }
      
      # Deploy using wrangler
      result = system(env_vars, "npx wrangler deploy --name #{worker_name} 2>&1")
      raise "Wrangler deployment failed" unless result
    end
  end

  def setup_environment_variables(worker_name)
    Rails.logger.info "[AutomatedDeploy] Setting environment variables..."
    
    variables = {
      'VITE_APP_ID' => @app.obfuscated_id,
      'VITE_SUPABASE_URL' => ENV['SUPABASE_URL'],
      'VITE_SUPABASE_ANON_KEY' => ENV['SUPABASE_ANON_KEY']
    }
    
    # Set each variable using the API
    variables.each do |key, value|
      response = self.class.put(
        "/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}/settings/vars",
        body: { [key] => value }.to_json,
        headers: self.class.headers
      )
      
      Rails.logger.info "[AutomatedDeploy] Set variable: #{key}" if response.code == 200
    end
  end

  def generate_worker_name
    base_name = @app.name.parameterize.downcase
    "overskill-#{base_name}-#{@app.obfuscated_id.downcase}"
  end

  def get_account_subdomain
    response = self.class.get(
      "/accounts/#{@cloudflare_account_id}/workers/subdomain",
      headers: self.class.headers
    )
    
    if response.success? && response['result']
      response['result']['subdomain'] || 'todd-e03'
    else
      'todd-e03'
    end
  end

  def cleanup_temp_dir
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end
end