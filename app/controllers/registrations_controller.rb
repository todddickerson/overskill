class RegistrationsController < Devise::RegistrationsController
  # Override to handle AJAX requests from the modal
  
  def create
    build_resource(sign_up_params)
    
    resource.save
    if resource.persisted?
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        
        # Check if we have a pending app prompt
        pending_prompt = session.delete(:pending_app_prompt)
        
        respond_to do |format|
          format.html do
            if pending_prompt
              redirect_to generator_index_path, 
                          notice: "Welcome! Creating your app...",
                          params: { prompt: pending_prompt }
            else
              redirect_to after_sign_up_path_for(resource)
            end
          end
          format.json do
            if pending_prompt
              # For AJAX, we'll handle the app creation directly
              render json: { success: true, redirect_url: after_sign_up_path_for(resource), pending_prompt: pending_prompt }
            else
              render json: { success: true, redirect_url: after_sign_up_path_for(resource) }
            end
          end
        end
      else
        expire_data_after_sign_in!
        respond_to do |format|
          format.html { redirect_to after_inactive_sign_up_path_for(resource) }
          format.json { render json: { success: true, message: "Please check your email to confirm your account" } }
        end
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_to do |format|
        format.html { render :new }
        format.json { render json: { success: false, error: resource.errors.full_messages.first }, status: :unprocessable_entity }
      end
    end
  end
end