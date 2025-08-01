# Service for deploying apps to Cloudflare Workers with unique subdomains
class Deployment::CloudflareWorkerService
  include HTTParty
  
  base_uri 'https://api.cloudflare.com/client/v4'
  
  def initialize(app)
    @app = app
    @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @api_key = ENV['CLOUDFLARE_API_KEY']
    @api_token = ENV['CLOUDFLARE_API_TOKEN']
    @email = ENV['CLOUDFLARE_EMAIL']
    @zone_id = ENV['CLOUDFLARE_ZONE_ID'] || ENV['CLOUDFLARE_ZONE'] # For overskill.app domain
    
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
  
  # Deploy app to Cloudflare Workers with unique subdomain
  def deploy!
    return failure("Missing Cloudflare credentials") unless credentials_present?
    
    subdomain = generate_subdomain
    worker_name = "overskill-#{@app.id}"
    
    # Step 1: Create the Worker script
    worker_script = generate_worker_script
    upload_response = upload_worker(worker_name, worker_script)
    
    return failure("Failed to upload worker: #{upload_response['errors']}") unless upload_response['success']
    
    # Step 2: Create subdomain route
    route_response = create_subdomain_route(subdomain, worker_name)
    
    return failure("Failed to create route: #{route_response['errors']}") unless route_response['success']
    
    # Step 3: Upload app files to R2 storage
    upload_files_to_r2
    
    # Step 4: Update app with deployment info
    deployment_url = "https://#{subdomain}.overskill.app"
    @app.update!(
      deployment_url: deployment_url,
      deployment_status: 'deployed',
      deployed_at: Time.current
    )
    
    success(deployment_url)
  rescue => e
    Rails.logger.error "Cloudflare deployment failed: #{e.message}"
    failure(e.message)
  end
  
  # Remove deployment
  def undeploy!
    return success("App not deployed") unless @app.deployment_url.present?
    
    worker_name = "overskill-#{@app.id}"
    
    # Delete worker
    delete_response = delete_worker(worker_name)
    
    # Remove app files from R2
    cleanup_r2_files
    
    @app.update!(
      deployment_url: nil,
      deployment_status: 'undeployed',
      deployed_at: nil
    )
    
    success("App undeployed successfully")
  rescue => e
    Rails.logger.error "Cloudflare undeployment failed: #{e.message}"
    failure(e.message)
  end
  
  private
  
  def credentials_present?
    @account_id.present? && @zone_id.present? && 
      (@api_token.present? || (@api_key.present? && @email.present?))
  end
  
  def generate_subdomain
    # Create URL-safe subdomain from app name
    base_name = @app.name.downcase
                         .gsub(/[^a-z0-9\-]/, '-')
                         .gsub(/-+/, '-')
                         .gsub(/^-|-$/, '')
    
    # Ensure uniqueness by appending app ID if needed
    subdomain = base_name.length > 20 ? "#{base_name[0..15]}-#{@app.id}" : "#{base_name}-#{@app.id}"
    subdomain
  end
  
  def generate_worker_script
    # Generate a Node.js Worker script that serves the app files
    <<~JAVASCRIPT
      addEventListener('fetch', event => {
        event.respondWith(handleRequest(event.request))
      })

      async function handleRequest(request) {
        const url = new URL(request.url)
        const pathname = url.pathname
        
        // Handle root path - serve index.html
        if (pathname === '/') {
          return serveFile('index.html', 'text/html')
        }
        
        // Serve static files
        const cleanPath = pathname.startsWith('/') ? pathname.slice(1) : pathname
        
        // Determine content type
        const contentType = getContentType(cleanPath)
        
        return serveFile(cleanPath, contentType)
      }

      async function serveFile(path, contentType) {
        try {
          // Fetch file from R2 storage
          const fileContent = await getFileFromR2(path)
          
          if (!fileContent) {
            return new Response('File not found', { status: 404 })
          }
          
          return new Response(fileContent, {
            headers: {
              'Content-Type': contentType,
              'Cache-Control': 'public, max-age=300',
              'Access-Control-Allow-Origin': '*'
            }
          })
        } catch (error) {
          return new Response('Internal Server Error', { status: 500 })
        }
      }

      async function getFileFromR2(path) {
        // This would be replaced with actual R2 binding in production
        // For now, we'll embed the file contents directly
        const files = #{app_files_as_json}
        
        return files[path] || null
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
  
  def create_subdomain_route(subdomain, worker_name)
    route_pattern = "#{subdomain}.overskill.app/*"
    
    response = self.class.post(
      "/zones/#{@zone_id}/workers/routes",
      headers: { 'Content-Type' => 'application/json' },
      body: JSON.generate({
        pattern: route_pattern,
        script: worker_name
      })
    )
    
    JSON.parse(response.body)
  end
  
  def delete_worker(worker_name)
    response = self.class.delete("/accounts/#{@account_id}/workers/scripts/#{worker_name}")
    JSON.parse(response.body)
  end
  
  def upload_files_to_r2
    # TODO: Implement R2 file upload for better performance
    # For now, files are embedded directly in the worker script
    Rails.logger.info "Files embedded in worker script for app #{@app.id}"
  end
  
  def cleanup_r2_files
    # TODO: Implement R2 file cleanup
    Rails.logger.info "R2 cleanup not implemented yet for app #{@app.id}"
  end
  
  def success(message)
    { success: true, message: message }
  end
  
  def failure(message)
    { success: false, error: message }
  end
end