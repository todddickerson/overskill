# Service for managing Cloudflare preview workers that auto-update with changes
class Deployment::CloudflarePreviewService
  include HTTParty
  
  base_uri 'https://api.cloudflare.com/client/v4'
  
  def initialize(app)
    @app = app
    @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @api_token = ENV['CLOUDFLARE_API_TOKEN'] || ENV['CLOUDFLARE_API_KEY']
    @zone_id = ENV['CLOUDFLARE_ZONE_ID'] || ENV['CLOUDFLARE_ZONE'] # For overskill.app domain
    
    self.class.headers 'Authorization' => "Bearer #{@api_token}"
  end
  
  # Create or update the auto-preview worker
  def update_preview!
    return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
    
    worker_name = "preview-#{@app.id}"
    preview_subdomain = "preview-#{@app.id}" # Use preview-{uuid} as subdomain
    
    # Upload worker script with latest files
    worker_script = generate_worker_script
    upload_response = upload_worker(worker_name, worker_script)
    
    return { success: false, error: "Failed to upload preview worker" } unless upload_response['success']
    
    # Ensure route exists for auto-preview domain (using overskill.app for now)
    ensure_preview_route(preview_subdomain, worker_name)
    
    # Update app with preview URLs
    preview_url = "https://#{preview_subdomain}.overskill.app"
    @app.update!(
      preview_url: preview_url,
      preview_updated_at: Time.current
    )
    
    { success: true, preview_url: preview_url }
  rescue => e
    Rails.logger.error "Preview update failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  # Deploy to staging (preview--app-name.overskill.app)
  def deploy_staging!
    staging_subdomain = "preview--#{generate_app_subdomain}"
    deploy_to_environment(:staging, staging_subdomain)
  end
  
  # Deploy to production (app-name.overskill.app)
  def deploy_production!
    production_subdomain = generate_app_subdomain
    deploy_to_environment(:production, production_subdomain)
  end
  
  private
  
  def credentials_present?
    [@account_id, @api_token, @zone_id].all?(&:present?)
  end
  
  def generate_app_subdomain
    base_name = @app.name.downcase
                         .gsub(/[^a-z0-9\-]/, '-')
                         .gsub(/-+/, '-')
                         .gsub(/^-|-$/, '')
    
    # Ensure uniqueness if needed
    base_name.presence || "app-#{@app.id}"
  end
  
  def generate_worker_script
    # Same worker script but with CORS headers for preview
    <<~JAVASCRIPT
      addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request))
      })

      async function handleRequest(request) {
        const url = new URL(request.url)
        const pathname = url.pathname
        
        // Handle root path
        if (pathname === '/') {
          return serveFile('index.html', 'text/html')
        }
        
        // Serve static files
        const cleanPath = pathname.startsWith('/') ? pathname.slice(1) : pathname
        const contentType = getContentType(cleanPath)
        
        return serveFile(cleanPath, contentType)
      }

      async function serveFile(path, contentType) {
        try {
          const files = #{app_files_as_json}
          const fileContent = files[path]
          
          if (!fileContent) {
            return new Response('File not found', { status: 404 })
          }
          
          return new Response(fileContent, {
            headers: {
              'Content-Type': contentType,
              'Cache-Control': 'no-cache, no-store, must-revalidate',
              'Access-Control-Allow-Origin': '*',
              'X-Frame-Options': 'ALLOWALL'
            }
          })
        } catch (error) {
          return new Response('Internal Server Error', { status: 500 })
        }
      }

      function getContentType(path) {
        const ext = path.split('.').pop().toLowerCase()
        const types = {
          'html': 'text/html',
          'js': 'application/javascript',
          'css': 'text/css',
          'json': 'application/json',
          'png': 'image/png',
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'gif': 'image/gif',
          'svg': 'image/svg+xml',
          'ico': 'image/x-icon'
        }
        return types[ext] || 'text/plain'
      }
    JAVASCRIPT
  end
  
  def app_files_as_json
    files_hash = {}
    @app.app_files.each do |file|
      files_hash[file.path] = file.content
    end
    JSON.generate(files_hash)
  end
  
  def upload_worker(worker_name, script)
    response = self.class.put(
      "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
      headers: { 'Content-Type' => 'application/javascript' },
      body: script
    )
    
    JSON.parse(response.body)
  end
  
  def ensure_preview_route(subdomain, worker_name)
    route_pattern = "#{subdomain}.overskill.app/*"
    
    # Check if route exists
    routes_response = self.class.get("/zones/#{@zone_id}/workers/routes")
    routes = JSON.parse(routes_response.body)['result'] || []
    
    existing_route = routes.find { |r| r['pattern'] == route_pattern }
    
    if existing_route
      # Update existing route
      self.class.put(
        "/zones/#{@zone_id}/workers/routes/#{existing_route['id']}",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          pattern: route_pattern,
          script: worker_name
        })
      )
    else
      # Create new route
      self.class.post(
        "/zones/#{@zone_id}/workers/routes",
        headers: { 'Content-Type' => 'application/json' },
        body: JSON.generate({
          pattern: route_pattern,
          script: worker_name
        })
      )
    end
  end
  
  def deploy_to_environment(environment, subdomain)
    return { success: false, error: "Missing credentials" } unless credentials_present?
    
    worker_name = "#{environment}-#{@app.id}"
    zone_id = ENV['CLOUDFLARE_ZONE_ID'] # For overskill.app domain
    
    # Upload worker
    worker_script = generate_worker_script
    upload_response = upload_worker(worker_name, worker_script)
    
    return { success: false, error: "Failed to upload worker" } unless upload_response['success']
    
    # Create route
    route_pattern = "#{subdomain}.overskill.app/*"
    route_response = self.class.post(
      "/zones/#{zone_id}/workers/routes",
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate({
        pattern: route_pattern,
        script: worker_name
      })
    )
    
    deployment_url = "https://#{subdomain}.overskill.app"
    
    # Update app based on environment
    if environment == :production
      @app.update!(
        deployment_url: deployment_url,
        deployment_status: 'deployed',
        deployed_at: Time.current
      )
    else
      @app.update!(
        staging_url: deployment_url,
        staging_deployed_at: Time.current
      )
    end
    
    # Create version record
    @app.app_versions.create!(
      version_number: next_version_number,
      changelog: "Deployed to #{environment} at #{deployment_url}",
      team: @app.team,
      environment: environment.to_s
    )
    
    { success: true, deployment_url: deployment_url, environment: environment }
  end
  
  def next_version_number
    last_version = @app.app_versions.order(created_at: :desc).first
    if last_version
      parts = last_version.version_number.split('.')
      parts[-1] = (parts[-1].to_i + 1).to_s
      parts.join('.')
    else
      "1.0.0"
    end
  end
end