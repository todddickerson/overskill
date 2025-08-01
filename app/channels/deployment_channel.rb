class DeploymentChannel < ApplicationCable::Channel
  def subscribed
    app = current_user.team.apps.find(params[:app_id])
    stream_from "app_#{app.id}_deployment"
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end