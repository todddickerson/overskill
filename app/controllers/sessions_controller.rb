class SessionsController < Devise::SessionsController
  # Override to handle AJAX requests from the modal
  
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
  
  def respond_to_on_destroy
    respond_to do |format|
      format.html { super }
      format.json { render json: { success: true } }
    end
  end
end