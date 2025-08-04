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
        url: @app.published_url,
        deployed_at: @app.deployed_at,
        version: @app.deployed_version
      },
      staging: {
        status: @app.staging_deployment_status || 'not_deployed',
        url: @app.staging_url,
        deployed_at: @app.staging_deployed_at,
        version: @app.staging_version
      },
      preview: {
        status: 'live',
        url: @app.preview_url,
        updated_at: @app.updated_at
      },
      visitor_stats: {
        total: @app.visitor_count,
        daily: @app.daily_visitors,
        trend: calculate_trend(@app.daily_visitors)
      }
    }
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