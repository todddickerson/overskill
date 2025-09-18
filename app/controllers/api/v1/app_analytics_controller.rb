class Api::V1::AppAnalyticsController < Api::V1::ApplicationController
  before_action :set_app
  before_action :authorize_app_access

  # GET /api/v1/apps/:app_id/analytics
  def index
    analytics_service = Analytics::AppAnalyticsService.new(@app)

    result = analytics_service.get_analytics_summary(
      time_range: params[:time_range] || "7d",
      metrics: params[:metrics]
    )

    if result[:success]
      render json: result[:data]
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # GET /api/v1/apps/:app_id/analytics/realtime
  def realtime
    analytics_service = Analytics::AppAnalyticsService.new(@app)
    result = analytics_service.get_realtime_analytics

    if result[:success]
      render json: result[:data]
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # GET /api/v1/apps/:app_id/analytics/insights
  def insights
    analytics_service = Analytics::AppAnalyticsService.new(@app)
    result = analytics_service.get_performance_insights

    if result[:success]
      render json: {
        insights: result[:insights],
        performance_score: result[:performance_score],
        recommendations: result[:recommendations]
      }
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # POST /api/v1/apps/:app_id/analytics/track
  def track
    analytics_service = Analytics::AppAnalyticsService.new(@app)

    result = analytics_service.track_event(
      params[:event_type],
      event_params
    )

    if result[:success]
      render json: {success: true, event_id: result[:event_id]}
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # GET /api/v1/apps/:app_id/analytics/funnel
  def funnel
    analytics_service = Analytics::AppAnalyticsService.new(@app)

    funnel_steps = params[:steps] || default_funnel_steps

    result = analytics_service.get_funnel_analytics(
      funnel_steps,
      time_range: params[:time_range] || "7d"
    )

    if result[:success]
      render json: result
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # GET /api/v1/apps/:app_id/analytics/export
  def export
    analytics_service = Analytics::AppAnalyticsService.new(@app)

    result = analytics_service.export_analytics(
      format: params[:format] || "json",
      time_range: params[:time_range] || "30d"
    )

    if result[:success]
      send_data result[:data],
        type: result[:content_type],
        filename: result[:filename],
        disposition: "attachment"
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  # POST /api/v1/apps/:app_id/analytics/deployment
  def track_deployment
    analytics_service = Analytics::AppAnalyticsService.new(@app)

    result = analytics_service.track_deployment(
      params[:version],
      deployment_params
    )

    if result[:success]
      render json: result[:deployment]
    else
      render json: {error: result[:error]}, status: :unprocessable_entity
    end
  end

  private

  def set_app
    @app = App.find(params[:app_id])
  rescue ActiveRecord::RecordNotFound
    render json: {error: "App not found"}, status: :not_found
  end

  def authorize_app_access
    # Check if user has access to this app
    unless current_user && @app.team.users.include?(current_user)
      render json: {error: "Unauthorized"}, status: :unauthorized
    end
  end

  def event_params
    params.permit(
      :session_id, :user_id, :ip_address, :user_agent,
      :referrer, :url, :value, :metadata,
      properties: {}
    ).to_h
  end

  def deployment_params
    params.permit(
      :environment, :commit_sha, :deployed_by,
      :deployment_time, :files_changed, :status
    ).to_h
  end

  def default_funnel_steps
    [
      {name: "Visit Homepage", event: "page_view"},
      {name: "View Product", event: "button_click"},
      {name: "Add to Cart", event: "button_click"},
      {name: "Complete Purchase", event: "conversion"}
    ]
  end
end
