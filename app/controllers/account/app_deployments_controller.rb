class Account::AppDeploymentsController < Account::ApplicationController
  before_action :set_app
  
  def show
    @deployment_status = get_deployment_status
    @deployment_history = @app.deployment_logs.order(created_at: :desc).limit(10)
    @environments = ['development', 'staging', 'production']
    
    respond_to do |format|
      format.html
      format.json { render json: @deployment_status }
    end
  end
  
  def deploy
    environment = params[:environment] || 'production'
    
    # Validate environment
    unless %w[development staging production].include?(environment)
      render json: { error: "Invalid environment" }, status: :unprocessable_entity
      return
    end
    
    # Check if files exist to deploy
    unless @app.app_files.any?
      render json: { error: "No files to deploy" }, status: :unprocessable_entity
      return
    end
    
    # Create deployment log
    deployment = @app.deployment_logs.create!(
      environment: environment,
      status: 'pending',
      initiated_by: current_user,
      started_at: Time.current
    )
    
    # Queue deployment job
    DeployAppJob.perform_later(@app.id, environment, deployment.id)
    
    render json: {
      message: "Deployment to #{environment} started",
      deployment_id: deployment.id,
      status: 'pending'
    }
  end
  
  def status
    deployment_id = params[:deployment_id]
    
    if deployment_id
      deployment = @app.deployment_logs.find(deployment_id)
      render json: {
        id: deployment.id,
        status: deployment.status,
        environment: deployment.environment,
        started_at: deployment.started_at,
        completed_at: deployment.completed_at,
        error_message: deployment.error_message,
        deployment_url: deployment.deployment_url
      }
    else
      render json: get_deployment_status
    end
  end
  
  def rollback
    deployment_id = params[:deployment_id]
    deployment = @app.deployment_logs.find(deployment_id)
    
    unless deployment.can_rollback?
      render json: { error: "Cannot rollback this deployment" }, status: :unprocessable_entity
      return
    end
    
    # Create rollback deployment
    rollback = @app.deployment_logs.create!(
      environment: deployment.environment,
      status: 'pending',
      initiated_by: current_user,
      started_at: Time.current,
      rollback_from_id: deployment.id
    )
    
    # Queue rollback job
    RollbackDeploymentJob.perform_later(@app.id, deployment.id, rollback.id)
    
    render json: {
      message: "Rollback initiated",
      deployment_id: rollback.id,
      status: 'pending'
    }
  end
  
  # POST /account/teams/:team_id/apps/:app_id/publish
  # Publish app from preview to production with unique subdomain
  def publish
    unless @app.can_publish?
      respond_to do |format|
        format.html { 
          redirect_to account_team_app_path(current_team, @app), 
            alert: "App must be in 'ready' state with a preview deployment before publishing."
        }
        format.json { 
          render json: { error: "App not ready for production" }, status: :unprocessable_entity 
        }
      end
      return
    end
    
    # Run deployment in background job
    # FIXED: Use DeployAppJob - PublishAppToProductionJob has been removed
    DeployAppJob.perform_later(@app, "production")
    
    respond_to do |format|
      format.html {
        redirect_to account_team_app_path(current_team, @app),
          notice: "Publishing app to production at #{@app.subdomain}.overskill.app. This may take a few minutes..."
      }
      format.json {
        render json: {
          message: "Publishing to production",
          subdomain: @app.subdomain,
          predicted_url: "https://#{@app.subdomain}.overskill.app"
        }
      }
    end
  end
  
  # PATCH /account/teams/:team_id/apps/:app_id/subdomain
  def update_subdomain
    new_subdomain = params[:subdomain]&.strip&.downcase
    
    if new_subdomain.blank?
      respond_to do |format|
        format.html { 
          redirect_to account_team_app_path(current_team, @app), 
            alert: "Subdomain cannot be blank."
        }
        format.json { 
          render json: { error: "Subdomain cannot be blank" }, status: :unprocessable_entity 
        }
      end
      return
    end
    
    # Validate format
    unless new_subdomain.match?(/\A[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?\z/)
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            alert: "Subdomain must be alphanumeric with hyphens, 1-63 characters, no leading/trailing hyphens."
        }
        format.json {
          render json: { error: "Invalid subdomain format" }, status: :unprocessable_entity
        }
      end
      return
    end
    
    # Check uniqueness
    if App.where(subdomain: new_subdomain).where.not(id: @app.id).exists?
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            alert: "Subdomain '#{new_subdomain}' is already taken. Please choose another."
        }
        format.json {
          render json: { error: "Subdomain already taken" }, status: :unprocessable_entity
        }
      end
      return
    end
    
    # Update subdomain (and redeploy if published)
    result = @app.update_subdomain!(new_subdomain)
    
    if result[:success]
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            notice: "Subdomain updated to '#{new_subdomain}'. " +
                    (@app.published? ? "Production URL: #{@app.production_url}" : "")
        }
        format.json {
          render json: {
            success: true,
            subdomain: new_subdomain,
            production_url: @app.production_url
          }
        }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            alert: "Failed to update subdomain: #{result[:error]}"
        }
        format.json {
          render json: { error: result[:error] }, status: :unprocessable_entity
        }
      end
    end
  end
  
  # POST /account/teams/:team_id/apps/:app_id/unpublish
  def unpublish
    if @app.published?
      @app.update!(status: 'ready', production_url: nil, published_at: nil)
      
      # REMOVED: ProductionDeploymentService deprecated
      # Worker cleanup now handled by Cloudflare TTL and manual cleanup if needed
      # To implement cleanup, use: Deployment::CloudflareWorkersDeployer
      # begin
      #   deployer = Deployment::CloudflareWorkersDeployer.new(@app)
      #   deployer.delete_worker("app-#{@app.obfuscated_id.downcase}")
      # rescue => e
      #   Rails.logger.error "Failed to cleanup production worker: #{e.message}"
      # end
      
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            notice: "App unpublished from production. Preview still available."
        }
        format.json {
          render json: {
            success: true,
            message: "App unpublished from production"
          }
        }
      end
    else
      respond_to do |format|
        format.html {
          redirect_to account_team_app_path(current_team, @app),
            alert: "App is not currently published."
        }
        format.json {
          render json: { error: "App not published" }, status: :unprocessable_entity
        }
      end
    end
  end
  
  def logs
    deployment_id = params[:deployment_id]
    deployment = @app.deployment_logs.find(deployment_id)
    
    logs = deployment.build_logs.order(created_at: :asc)
    
    respond_to do |format|
      format.json { 
        render json: logs.map { |log| 
          {
            timestamp: log.created_at,
            level: log.level,
            message: log.message
          }
        }
      }
      format.text {
        render plain: logs.map { |log| 
          "[#{log.created_at.strftime('%Y-%m-%d %H:%M:%S')}] #{log.level.upcase}: #{log.message}"
        }.join("\n")
      }
    end
  end
  
  private
  
  def set_app
    @app = current_team.apps.find(params[:app_id])
  end
  
  def get_deployment_status
    {
      production: {
        status: @app.deployment_status || 'not_deployed',
        url: @app.production_url || @app.deployment_url,
        deployed_at: @app.deployed_at,
        version: get_deployed_version(@app, 'production')
      },
      staging: {
        status: 'not_deployed', # No staging_deployment_status field exists
        url: @app.staging_url,
        deployed_at: @app.staging_deployed_at,
        version: get_deployed_version(@app, 'staging')
      },
      preview: {
        status: 'live',
        url: @app.preview_url,
        updated_at: @app.updated_at
      },
      visitor_stats: {
        total: @app.total_users || 0,
        daily: [], # No daily_visitors field exists
        trend: 'neutral'
      }
    }
  end
  
  def get_deployed_version(app, environment)
    # Get the latest successful deployment for this environment
    latest_deployment = app.deployment_logs
                          .where(environment: environment, status: 'success')
                          .order(completed_at: :desc)
                          .first
    
    if latest_deployment&.deployed_version.present?
      latest_deployment.deployed_version
    else
      # Fallback to latest app version if no deployment version is recorded
      latest_version = app.app_versions.order(created_at: :desc).first
      latest_version&.version_number || '1.0.0'
    end
  end
  
  def calculate_trend(daily_visitors)
    return 'neutral' if daily_visitors.empty? || daily_visitors.length < 2
    
    recent = daily_visitors.last(3).sum.to_f / 3
    previous = daily_visitors.first(3).sum.to_f / 3
    
    return 'neutral' if previous == 0
    
    change = ((recent - previous) / previous) * 100
    
    if change > 10
      'up'
    elsif change < -10
      'down'
    else
      'neutral'
    end
  end
end