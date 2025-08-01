class DeploymentChannel < ApplicationCable::Channel
  def subscribed
    # Find the app and verify the user has access through any of their teams
    app = App.find(params[:app_id])
    
    # Check if the user has access to this app through any of their teams
    if current_user.teams.include?(app.team)
      stream_from "app_#{app.id}_deployment"
    else
      reject
    end
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end