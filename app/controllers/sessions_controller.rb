class SessionsController < Devise::SessionsController
  # Override to handle AJAX requests from the modal
  
  def create
    self.resource = warden.authenticate!(auth_options)
    sign_in(resource_name, resource)
    
    # Check if we have a pending app prompt
    pending_prompt = session.delete(:pending_app_prompt)
    
    respond_to do |format|
      format.html do
        if pending_prompt
          # If we have a pending prompt, go directly to create action
          redirect_to generator_index_path, 
                      notice: "Signed in successfully. Creating your app...",
                      params: { prompt: pending_prompt }
        else
          redirect_to after_sign_in_path_for(resource)
        end
      end
      format.json do
        if pending_prompt
          # For AJAX, we'll handle the app creation directly
          render json: { success: true, redirect_url: after_sign_in_path_for(resource), pending_prompt: pending_prompt }
        else
          render json: { success: true, redirect_url: after_sign_in_path_for(resource) }
        end
      end
    end
  rescue
    respond_to do |format|
      format.html { 
        flash.now[:alert] = "Invalid email or password"
        self.resource = User.new
        render :new
      }
      format.json { render json: { success: false, error: "Invalid email or password" }, status: :unauthorized }
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