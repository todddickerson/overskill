class RegistrationsController < Devise::RegistrationsController
  # Override to handle AJAX requests from the modal
  
  def create
    build_resource(sign_up_params)
    
    resource.save
    if resource.persisted?
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        
        # Check if we have a pending generation in cookies
        if cookies.encrypted[:pending_generation].present?
          # Redirect to generator index where it will be processed
          redirect_to generator_index_path, notice: "Welcome! Creating your app..."
        else
          redirect_to after_sign_up_path_for(resource)
        end
      else
        expire_data_after_sign_in!
        flash.now[:notice] = "Please check your email to confirm your account"
        respond_to do |format|
          format.html { redirect_to after_inactive_sign_up_path_for(resource) }
          format.json { render json: { success: true, message: "Please check your email to confirm your account" } }
          format.turbo_stream # Will render create.turbo_stream.erb
        end
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_to do |format|
        format.html { render :new }
        format.json { render json: { success: false, error: resource.errors.full_messages.first }, status: :unprocessable_entity }
        format.turbo_stream # Will render create.turbo_stream.erb
      end
    end
  end
end