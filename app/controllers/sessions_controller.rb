class SessionsController < Devise::SessionsController
  # Override to handle AJAX requests from the modal
  
  # Email-first flow to determine whether to show login or signup.
  # Posts to /users/pre_otp from the home page's email capture form.
  def pre_otp
    email = params[:email].to_s.strip.downcase
    return render_pre_otp_error("Please enter a valid email address") if email.blank?

    existing_user = User.find_by(email: email)

    # Keep email in a short-lived, encrypted cookie to prefill forms.
    cookies.encrypted[:pre_auth_email] = {value: email, expires: 10.minutes.from_now}

    if existing_user
      # Render the auth modal with login tab active and email prefilled.
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "auth_modal",
            partial: "shared/auth_modal",
            locals: { show: true, show_signup: false, email: email }
          )
        end
        format.html { redirect_to new_user_session_path(email: email) }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "auth_modal",
            partial: "shared/auth_modal",
            locals: { show: true, show_signup: true, email: email }
          )
        end
        format.html { redirect_to new_user_registration_path(email: email) }
      end
    end
  end
  
  def create
    self.resource = warden.authenticate!(auth_options)
    sign_in(resource_name, resource)
    
    # Check if we have a pending generation in cookies
    if cookies.encrypted[:pending_generation].present?
      # Redirect to generator index where it will be processed
      redirect_to generator_index_path, notice: "Signed in successfully. Creating your app..."
    else
      redirect_to after_sign_in_path_for(resource)
    end
  rescue
    # Handle authentication failure
    self.resource = User.new
    flash.now[:alert] = "Invalid email or password"
    
    respond_to do |format|
      format.html { render :new }
      format.turbo_stream # Will render create.turbo_stream.erb
    end
  end
  
  private
  
  def render_pre_otp_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "auth_modal",
          partial: "shared/auth_modal",
          locals: { show: true, error: message, show_login: false }
        )
      end
      format.html do
        redirect_to root_path, alert: message
      end
    end
  end

  def respond_to_on_destroy
    respond_to do |format|
      format.html { super }
      format.json { render json: { success: true } }
    end
  end
end