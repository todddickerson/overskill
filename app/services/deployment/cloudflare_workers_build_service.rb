# Cloudflare Workers Build Service for GitHub Integration
# Handles multi-environment deployments with automatic git-based builds
# Privacy-first with app.obfuscated_id in worker names

class Deployment::CloudflareWorkersBuildService
  include HTTParty
  base_uri 'https://api.cloudflare.com/client/v4'

  def initialize(app)
    @app = app
    @cloudflare_token = ENV['CLOUDFLARE_API_TOKEN']
    @cloudflare_account_id = ENV['CLOUDFLARE_ACCOUNT_ID']
    @github_org = ENV['GITHUB_ORG']
    
    raise "Missing Cloudflare credentials" unless [@cloudflare_token, @cloudflare_account_id].all?(&:present?)
    
    self.class.headers({
      'Authorization' => "Bearer #{@cloudflare_token}",
      'Content-Type' => 'application/json'
    })
  end

  # Create Cloudflare Worker with GitHub integration for multi-environment deployment
  def create_worker_with_git_integration(repo_result)
    worker_name = generate_worker_name
    repo_name = repo_result[:repo_name]
    
    Rails.logger.info "[CloudflareWorkersBuildService] Creating worker with git integration: #{worker_name}"
    
    begin
      # Step 1: Create the worker script with git configuration
      worker_response = create_worker_with_github_builds(worker_name, repo_name)
      return worker_response unless worker_response[:success]
      
      # Step 2: Configure environment variables for all environments
      env_result = setup_worker_environment_variables(worker_name)
      return env_result unless env_result[:success]
      
      # Step 3: Setup custom domain routing (if configured)
      domain_result = setup_worker_domains(worker_name)
      # Domain setup is optional - continue even if it fails
      
      Rails.logger.info "[CloudflareWorkersBuildService] ✅ Worker created with git integration: #{worker_name}"
      
      {
        success: true,
        worker_name: worker_name,
        preview_url: generate_preview_url(worker_name),
        staging_url: generate_staging_url(worker_name),
        production_url: generate_production_url(worker_name),
        git_integration: true,
        auto_deploy: {
          preview: "Push to 'main' branch",
          staging: "Manual promotion",
          production: "Manual promotion"
        }
      }
    rescue => e
      Rails.logger.error "[CloudflareWorkersBuildService] Worker creation failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Trigger manual deployment to staging environment
  def promote_to_staging
    worker_name = @app.cloudflare_worker_name
    return { success: false, error: 'No worker configured' } unless worker_name
    
    Rails.logger.info "[CloudflareWorkersBuildService] Promoting #{worker_name} to staging"
    
    deployment_result = trigger_environment_deployment(worker_name, 'staging')
    
    if deployment_result[:success]
      @app.update!(
        deployment_status: 'staging_deployed',
        staging_deployed_at: Time.current
      )
      
      create_deployment_record('staging', deployment_result[:deployment_id])
    end
    
    deployment_result
  end

  # Trigger manual deployment to production environment  
  def promote_to_production
    worker_name = @app.cloudflare_worker_name
    return { success: false, error: 'No worker configured' } unless worker_name
    
    Rails.logger.info "[CloudflareWorkersBuildService] Promoting #{worker_name} to production"
    
    deployment_result = trigger_environment_deployment(worker_name, 'production')
    
    if deployment_result[:success]
      @app.update!(
        deployment_status: 'production_deployed',
        last_deployment_at: Time.current
      )
      
      create_deployment_record('production', deployment_result[:deployment_id])
    end
    
    deployment_result
  end

  # Get deployment status for all environments
  def get_deployment_status
    worker_name = @app.cloudflare_worker_name
    return { success: false, error: 'No worker configured' } unless worker_name
    
    begin
      # Get worker details including deployment status
      response = self.class.get(
        "/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}",
        headers: self.class.headers
      )
      
      if response.success?
        worker_data = response.parsed_response['result']
        
        {
          success: true,
          worker_name: worker_name,
          environments: {
            preview: {
              url: generate_preview_url(worker_name),
              status: 'active', # Preview auto-deploys
              last_deployed: worker_data.dig('modified_on')
            },
            staging: {
              url: generate_staging_url(worker_name),
              status: @app.staging_deployed_at ? 'deployed' : 'not_deployed',
              last_deployed: @app.staging_deployed_at
            },
            production: {
              url: generate_production_url(worker_name),
              status: @app.deployment_status == 'production_deployed' ? 'deployed' : 'not_deployed',
              last_deployed: @app.last_deployment_at
            }
          }
        }
      else
        { success: false, error: "Worker not found: #{response.code}" }
      end
    rescue => e
      { success: false, error: e.message }
    end
  end

  private

  def create_worker_with_github_builds(worker_name, repo_name)
    # Create worker with GitHub builds integration
    worker_script = generate_build_worker_script
    
    form_data = {
      'metadata' => {
        'main_module' => 'worker.js',
        'compatibility_date' => '2024-08-01',
        'compatibility_flags' => ['nodejs_compat'],
        'build_config' => {
          'github_integration' => {
            'repository' => "#{@github_org}/#{repo_name}",
            'production_branch' => 'main',
            'preview_deployments' => true
          }
        }
      }.to_json,
      'worker.js' => worker_script
    }
    
    response = self.class.put(
      "/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}",
      body: form_data,
      headers: self.class.headers.except('Content-Type') # Let HTTParty handle multipart
    )
    
    if response.success?
      { success: true, worker_created: true }
    else
      Rails.logger.error "[CloudflareWorkersBuildService] Worker creation failed: #{response.code} - #{response.body}"
      { success: false, error: "Worker creation failed: #{response.code}" }
    end
  end

  def setup_worker_environment_variables(worker_name)
    # Set up environment variables for the worker
    variables = {
      'VITE_APP_ID' => @app.obfuscated_id, # Use obfuscated ID for privacy
      'VITE_SUPABASE_URL' => ENV['SUPABASE_URL'],
      'VITE_SUPABASE_ANON_KEY' => ENV['SUPABASE_ANON_KEY'],
      'VITE_OWNER_ID' => @app.team.id.to_s,
      'VITE_ENVIRONMENT' => 'preview'
    }
    
    variables.each do |key, value|
      response = self.class.put(
        "/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}/secrets",
        body: { name: key, text: value.to_s, type: 'plain_text' }.to_json,
        headers: self.class.headers
      )
      
      unless response.success?
        Rails.logger.warn "[CloudflareWorkersBuildService] Failed to set variable #{key}: #{response.code}"
      end
    end
    
    { success: true, variables_set: variables.size }
  end

  def setup_worker_domains(worker_name)
    # Optional: Setup custom domains for different environments
    # This is a placeholder for future domain configuration
    { success: true, domains_configured: false }
  end

  def trigger_environment_deployment(worker_name, environment)
    # Trigger deployment for specific environment
    deployment_id = "#{environment}-#{@app.obfuscated_id}-#{Time.current.to_i}"
    
    response = self.class.post(
      "/accounts/#{@cloudflare_account_id}/workers/scripts/#{worker_name}/deployments",
      body: {
        environment: environment,
        deployment_id: deployment_id
      }.to_json,
      headers: self.class.headers
    )
    
    if response.success?
      {
        success: true,
        deployment_id: deployment_id,
        environment: environment,
        triggered_at: Time.current
      }
    else
      {
        success: false,
        error: "Deployment failed: #{response.code}"
      }
    end
  end

  def generate_build_worker_script
    # Generate a simple worker script that serves the built Vite app
    <<~JAVASCRIPT
      export default {
        async fetch(request, env, ctx) {
          // This worker will be replaced by Cloudflare Workers Builds
          // with the actual built application from your GitHub repository
          
          return new Response('OverSkill App - Building...', {
            headers: { 'Content-Type': 'text/html' }
          });
        }
      };
    JAVASCRIPT
  end

  def generate_worker_name
    # Use obfuscated_id for privacy in worker names
    base_name = (@app.slug.presence || @app.name).parameterize
    "overskill-#{base_name}-#{@app.obfuscated_id}"
  end

  def generate_preview_url(worker_name)
    "https://preview-#{worker_name}.overskill.workers.dev"
  end

  def generate_staging_url(worker_name)
    "https://staging-#{worker_name}.overskill.workers.dev"
  end

  def generate_production_url(worker_name)
    "https://#{worker_name}.overskill.workers.dev"
  end

  def create_deployment_record(environment, deployment_id)
    AppDeployment.create!(
      app: @app,
      environment: environment,
      deployment_id: deployment_id,
      deployment_url: case environment
                      when 'preview' then @app.preview_url
                      when 'staging' then @app.staging_url  
                      when 'production' then @app.production_url
                      end,
      deployed_at: Time.current
    )
  end
end