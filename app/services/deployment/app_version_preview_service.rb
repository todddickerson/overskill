# Service to deploy specific app versions to preview Workers
class Deployment::AppVersionPreviewService
  include HTTParty
  
  base_uri 'https://api.cloudflare.com/client/v4'
  
  def initialize(app_version)
    @app_version = app_version
    @app = app_version.app
    @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @api_key = ENV['CLOUDFLARE_API_KEY']
    @api_token = ENV['CLOUDFLARE_API_TOKEN']
    @email = ENV['CLOUDFLARE_EMAIL']
    
    # Use API Token if available, otherwise use Global API Key
    if @api_token.present?
      self.class.headers 'Authorization' => "Bearer #{@api_token}"
    elsif @api_key.present? && @email.present?
      self.class.headers({
        'X-Auth-Email' => @email,
        'X-Auth-Key' => @api_key
      })
    end
  end
  
  # Deploy a specific version to a preview Worker
  def deploy_version_preview!
    return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
    
    # Create a unique worker name for this version
    worker_name = "version-#{@app_version.id}"
    
    # Generate worker script with version's files
    worker_script = generate_worker_script_for_version
    
    # Upload worker
    upload_response = upload_worker(worker_name, worker_script)
    return { success: false, error: "Failed to upload version worker" } unless upload_response['success']
    
    # Enable workers.dev subdomain
    enable_workers_dev_subdomain(worker_name)
    
    # Get the preview URL
    preview_url = "https://#{worker_name}.#{@account_id.gsub('_', '-')}.workers.dev"
    
    { 
      success: true, 
      preview_url: preview_url,
      worker_name: worker_name
    }
  rescue => e
    Rails.logger.error "Version preview deployment failed: #{e.message}"
    { success: false, error: e.message }
  end
  
  private
  
  def credentials_present?
    @account_id.present? && 
      (@api_token.present? || (@api_key.present? && @email.present?))
  end
  
  def generate_worker_script_for_version
    # Get the state of files at this version
    files_hash = reconstruct_files_at_version
    
    <<~JAVASCRIPT
      addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request))
      })

      async function handleRequest(request) {
        const url = new URL(request.url)
        const pathname = url.pathname
        
        // Add version info header
        const headers = {
          'X-App-Version': '#{@app_version.version_number}',
          'X-App-Name': '#{@app.name}',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Access-Control-Allow-Origin': '*',
          'X-Frame-Options': 'ALLOWALL'
        }
        
        // Handle root path
        if (pathname === '/') {
          return serveFile('index.html', 'text/html', headers)
        }
        
        // Serve static files
        const cleanPath = pathname.startsWith('/') ? pathname.slice(1) : pathname
        const contentType = getContentType(cleanPath)
        
        return serveFile(cleanPath, contentType, headers)
      }

      async function serveFile(path, contentType, extraHeaders) {
        try {
          const files = #{JSON.generate(files_hash)}
          const fileContent = files[path]
          
          if (!fileContent) {
            return new Response('File not found', { status: 404, headers: extraHeaders })
          }
          
          return new Response(fileContent, {
            headers: {
              'Content-Type': contentType,
              ...extraHeaders
            }
          })
        } catch (error) {
          return new Response('Internal Server Error', { status: 500, headers: extraHeaders })
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
  
  def reconstruct_files_at_version
    # For now, we'll use the current files
    # In a full implementation, you'd track file changes per version
    files_hash = {}
    @app.app_files.each do |file|
      files_hash[file.path] = file.content
    end
    files_hash
  end
  
  def upload_worker(worker_name, script)
    response = self.class.put(
      "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
      headers: { 'Content-Type' => 'application/javascript' },
      body: script
    )
    
    JSON.parse(response.body)
  end
  
  def enable_workers_dev_subdomain(worker_name)
    response = self.class.patch(
      "/accounts/#{@account_id}/workers/scripts/#{worker_name}/subdomain",
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate({ enabled: true })
    )
    
    if response.code == 200
      Rails.logger.info "Enabled workers.dev subdomain for version worker #{worker_name}"
    else
      Rails.logger.warn "Failed to enable workers.dev subdomain: #{response.body}"
    end
  end
end