# Service for deploying apps to production with unique subdomains
module Deployment
  class ProductionDeploymentService
    include HTTParty
    base_uri 'https://api.cloudflare.com/client/v4'
    
    def initialize(app)
      @app = app
      @account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
      @api_token = ENV['CLOUDFLARE_API_TOKEN']
      @zone_id = ENV['CLOUDFLARE_ZONE_ID']
      
      self.class.headers('Authorization' => "Bearer #{@api_token}")
    end
    
    # Deploy app from preview to production
    def deploy_to_production!
      return { success: false, error: "App not ready for production" } unless can_deploy_to_production?
      
      Rails.logger.info "[ProductionDeployment] Deploying app ##{@app.id} to production"
      
      begin
        # 1. Ensure unique subdomain
        subdomain = ensure_unique_subdomain
        
        # 2. Build production-optimized version
        build_result = build_for_production
        return build_result unless build_result[:success]
        
        # 3. Deploy to production worker
        deploy_result = deploy_production_worker(build_result[:built_code])
        return deploy_result unless deploy_result[:success]
        
        # 4. Update app with production URL
        production_url = "https://#{subdomain}.overskill.app"
        @app.update!(
          production_url: production_url,
          subdomain: subdomain,
          status: 'published',
          last_deployed_at: Time.current
        )
        
        # 5. Create production version record
        create_production_version
        
        {
          success: true,
          production_url: production_url,
          subdomain: subdomain,
          worker_name: deploy_result[:worker_name],
          deployed_at: Time.current
        }
      rescue => e
        Rails.logger.error "[ProductionDeployment] Failed: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        
        { success: false, error: e.message }
      end
    end
    
    # Update subdomain (must remain unique)
    def update_subdomain(new_subdomain)
      return { success: false, error: "Invalid subdomain" } unless valid_subdomain?(new_subdomain)
      return { success: false, error: "Subdomain already taken" } unless subdomain_available?(new_subdomain)
      
      old_subdomain = @app.subdomain || @app.slug
      
      begin
        # 1. Deploy to new subdomain
        deploy_result = deploy_to_subdomain(new_subdomain)
        return deploy_result unless deploy_result[:success]
        
        # 2. Update app
        @app.update!(
          subdomain: new_subdomain,
          slug: new_subdomain, # Keep slug in sync
          production_url: "https://#{new_subdomain}.overskill.app"
        )
        
        # 3. Remove old worker (after successful migration)
        cleanup_old_worker(old_subdomain) if old_subdomain != new_subdomain
        
        {
          success: true,
          new_subdomain: new_subdomain,
          new_url: @app.production_url,
          old_subdomain: old_subdomain
        }
      rescue => e
        Rails.logger.error "[ProductionDeployment] Subdomain update failed: #{e.message}"
        { success: false, error: e.message }
      end
    end
    
    private
    
    def can_deploy_to_production?
      # App must be in ready state with files
      @app.status == 'ready' && @app.app_files.exists?
    end
    
    def ensure_unique_subdomain
      # Use existing subdomain if set, otherwise generate from slug
      subdomain = @app.subdomain || @app.slug
      
      # Ensure it's valid and unique
      subdomain = sanitize_subdomain(subdomain)
      
      # If not unique, append number
      if !subdomain_available?(subdomain) && subdomain != @app.subdomain
        base = subdomain
        counter = 2
        loop do
          subdomain = "#{base}-#{counter}"
          break if subdomain_available?(subdomain)
          counter += 1
          raise "Cannot find available subdomain" if counter > 100
        end
      end
      
      # Save the subdomain to the app
      @app.update!(subdomain: subdomain) if @app.subdomain != subdomain
      
      subdomain
    end
    
    def sanitize_subdomain(subdomain)
      # Convert to lowercase, replace non-alphanumeric with hyphens
      subdomain.downcase
        .gsub(/[^a-z0-9\-]/, '-')  # Replace invalid chars with hyphen
        .gsub(/-+/, '-')            # Collapse multiple hyphens
        .gsub(/^-|-$/, '')          # Remove leading/trailing hyphens
        .slice(0, 63)               # Max 63 chars for subdomain
    end
    
    def valid_subdomain?(subdomain)
      # Must be 1-63 chars, alphanumeric + hyphens, no leading/trailing hyphens
      subdomain.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/)
    end
    
    def subdomain_available?(subdomain)
      # Check if subdomain is already taken by another app
      existing = App.where(subdomain: subdomain).where.not(id: @app.id).exists?
      
      # Also check slug field for backwards compatibility
      existing ||= App.where(slug: subdomain).where.not(id: @app.id).exists?
      
      !existing
    end
    
    def build_for_production
      Rails.logger.info "[ProductionDeployment] Building production version"
      
      # Use ExternalViteBuilder - using preview mode for now to avoid TypeScript errors
      # TODO: Fix TypeScript errors and switch to production build
      builder = Deployment::ExternalViteBuilder.new(@app)
      build_result = builder.build_for_preview  # Using preview mode temporarily
      
      if build_result[:success]
        Rails.logger.info "[ProductionDeployment] Build successful (#{build_result[:output_size]} bytes)"
        { success: true, built_code: build_result[:built_code] }
      else
        Rails.logger.error "[ProductionDeployment] Build failed: #{build_result[:error]}"
        { success: false, error: "Build failed: #{build_result[:error]}" }
      end
    end
    
    def deploy_production_worker(built_code)
      deployer = CloudflareWorkersDeployer.new(@app)
      deployer.deploy_with_secrets(
        built_code: built_code,
        deployment_type: :production
      )
    end
    
    def deploy_to_subdomain(subdomain)
      # Build first
      build_result = build_for_production
      return build_result unless build_result[:success]
      
      # Deploy with custom worker name
      worker_name = "app-#{subdomain}"
      
      Rails.logger.info "[ProductionDeployment] Deploying to worker: #{worker_name}"
      
      response = self.class.put(
        "/accounts/#{@account_id}/workers/scripts/#{worker_name}",
        body: build_result[:built_code],
        headers: { 'Content-Type' => 'application/javascript' }
      )
      
      if response.success?
        # Configure route for this subdomain
        configure_subdomain_route(subdomain, worker_name)
        
        { success: true, worker_name: worker_name }
      else
        error = response.parsed_response['errors']&.first&.dig('message') || 'Unknown error'
        { success: false, error: error }
      end
    end
    
    def configure_subdomain_route(subdomain, worker_name)
      # Configure Cloudflare route for subdomain -> worker mapping
      route_pattern = "#{subdomain}.overskill.app/*"
      
      Rails.logger.info "[ProductionDeployment] Configuring route: #{route_pattern} -> #{worker_name}"
      
      # Check if route exists
      existing_route = find_existing_route(route_pattern)
      
      if existing_route
        # Update existing route
        self.class.put(
          "/zones/#{@zone_id}/workers/routes/#{existing_route['id']}",
          body: {
            pattern: route_pattern,
            script: worker_name
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      else
        # Create new route
        self.class.post(
          "/zones/#{@zone_id}/workers/routes",
          body: {
            pattern: route_pattern,
            script: worker_name
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )
      end
    end
    
    def find_existing_route(pattern)
      response = self.class.get("/zones/#{@zone_id}/workers/routes")
      return nil unless response.success?
      
      routes = response.parsed_response['result'] || []
      routes.find { |r| r['pattern'] == pattern }
    end
    
    def cleanup_old_worker(old_subdomain)
      old_worker_name = "app-#{old_subdomain}"
      
      Rails.logger.info "[ProductionDeployment] Cleaning up old worker: #{old_worker_name}"
      
      # Delete old worker
      self.class.delete("/accounts/#{@account_id}/workers/scripts/#{old_worker_name}")
      
      # Delete old route
      old_pattern = "#{old_subdomain}.overskill.app/*"
      old_route = find_existing_route(old_pattern)
      
      if old_route
        self.class.delete("/zones/#{@zone_id}/workers/routes/#{old_route['id']}")
      end
    rescue => e
      Rails.logger.warn "[ProductionDeployment] Cleanup failed: #{e.message}"
    end
    
    def create_production_version
      # Create a version record for this production deployment
      version = @app.app_versions.create!(
        version_number: next_version_number,
        commit_message: "Production deployment",
        deployed: true,
        published_at: Time.current,
        changelog: "Deployed to production at #{@app.production_url}"
      )
      
      # Link current files to this version
      @app.app_files.each do |file|
        version.app_version_files.create!(
          app_file: file,
          action: 'deployed'
        )
      end
      
      version
    end
    
    def next_version_number
      last_version = @app.app_versions.order(:created_at).last
      
      if last_version&.version_number.present?
        # Increment version
        parts = last_version.version_number.split('.')
        parts[-1] = (parts[-1].to_i + 1).to_s
        parts.join('.')
      else
        "1.0.0"
      end
    end
  end
end