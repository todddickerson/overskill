module Deployment
  # Simplified fast preview service - just serve the files
  class FastPreviewServiceSimple < CloudflarePreviewService
    
    def initialize(app)
      super(app)
    end
    
    def deploy_instant_preview!
      Rails.logger.info "[FastPreview] Deploying instant preview for app #{@app.id}"
      
      return { success: false, error: "Missing Cloudflare credentials" } unless credentials_present?
      
      worker_name = "preview-#{@app.obfuscated_id.downcase}"
      subdomain = "preview-#{@app.obfuscated_id.downcase}"
      
      # Generate simple worker script
      worker_script = generate_simple_worker
      
      # Upload worker
      upload_response = upload_worker(worker_name, worker_script)
      
      return { success: false, error: "Failed to upload worker: #{upload_response['error']}" } unless upload_response['success']
      
      # Set environment variables
      set_worker_env_vars(worker_name)
      
      # Enable workers.dev subdomain
      enable_workers_dev_subdomain(worker_name)
      
      # Ensure route exists
      ensure_preview_route(subdomain, worker_name)
      
      # URLs
      custom_domain_url = "https://#{subdomain}.overskill.app"
      
      # Update app
      @app.update!(
        preview_url: custom_domain_url,
        preview_updated_at: Time.current,
        deployment_status: 'preview'
      )
      
      { 
        success: true,
        preview_url: custom_domain_url,
        deployment_time: "< 3 seconds",
        message: "Instant preview deployed!"
      }
    rescue => e
      Rails.logger.error "[FastPreview] Deployment failed: #{e.message}"
      { success: false, error: e.message }
    end
    
    private
    
    def generate_simple_worker
      files_json = app_files_as_json
      
      # Generate a simple worker that just serves files
      <<~JAVASCRIPT
        // Simple Preview Worker - Just serve the files
        
        addEventListener('fetch', event => {
          event.respondWith(handleRequest(event.request))
        })
        
        async function handleRequest(request) {
          const url = new URL(request.url)
          let pathname = url.pathname
          
          // Files embedded in worker
          const files = #{files_json};
          
          // Serve index.html for root
          if (pathname === '/' || pathname === '') {
            const html = files['index.html'] || '<h1>No index.html found</h1>';
            return new Response(html, {
              headers: { 'Content-Type': 'text/html' }
            })
          }
          
          // Remove leading slash
          if (pathname.startsWith('/')) {
            pathname = pathname.slice(1)
          }
          
          // Try to serve the requested file
          const content = files[pathname]
          
          if (content) {
            // Determine content type
            let contentType = 'text/plain'
            if (pathname.endsWith('.html')) contentType = 'text/html'
            else if (pathname.endsWith('.js') || pathname.endsWith('.jsx')) contentType = 'application/javascript'
            else if (pathname.endsWith('.css')) contentType = 'text/css'
            else if (pathname.endsWith('.json')) contentType = 'application/json'
            else if (pathname.endsWith('.svg')) contentType = 'image/svg+xml'
            
            return new Response(content, {
              headers: { 'Content-Type': contentType }
            })
          }
          
          // File not found - return index.html for client-side routing
          const html = files['index.html'] || '<h1>404 - Not Found</h1>';
          return new Response(html, {
            status: 404,
            headers: { 'Content-Type': 'text/html' }
          })
        }
      JAVASCRIPT
    end
  end
end