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
          # If we have a pending prompt, redirect back to generator with the prompt
          redirect_to generator_index_path(prompt: pending_prompt), notice: "Signed in successfully. Creating your app..."
        else
          redirect_to after_sign_in_path_for(resource)
        end
      end
      format.json do
        if pending_prompt
          render json: { success: true, redirect_url: generator_index_path(prompt: pending_prompt) }
        else
          render json: { success: true, redirect_url: after_sign_in_path_for(resource) }
        end
      end
    end
  rescue Warden::Strategies::Base
    respond_to do |format|
      format.html { super }
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