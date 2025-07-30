class SessionsController < Devise::SessionsController
  include Sessions::ControllerBase
  
  # Explicitly skip CSRF for create action
  skip_before_action :verify_authenticity_token, only: [:create]
  
  def create
    Rails.logger.info "=== Session Create Debug ==="
    Rails.logger.info "Session ID: #{session.id}"
    Rails.logger.info "Session empty?: #{session.empty?}"
    super do |resource|
      if resource.persisted?
        Rails.logger.info "User signed in: #{resource.email}"
        Rails.logger.info "Session after sign in: #{session.inspect}"
        Rails.logger.info "Warden user: #{warden.user}"
      end
    end
  end
end
