class RegistrationsController < Devise::RegistrationsController
  # Override to handle AJAX requests from the modal
  
  def create
    build_resource(sign_up_params)
    
    resource.save
    if resource.persisted?
      if resource.active_for_authentication?
        sign_up(resource_name, resource)
        
        # Check if we have a pending generation in cookies
        redirect_path = if cookies.encrypted[:pending_generation].present?
          # Redirect to generator index where it will be processed
          Rails.logger.info "[AUTH] Found pending generation after signup, redirecting to generator"
          generator_index_path
        else
          after_sign_up_path_for(resource)
        end
        
        respond_to do |format|
          format.html do
            # Check if this is a Turbo Frame request for auth_modal
            if request.headers["Turbo-Frame"] == "auth_modal"
              # Return empty turbo frame to close modal, then redirect via Turbo
              render html: <<~HTML.html_safe
                <turbo-frame id="auth_modal"></turbo-frame>
                <script>
                  setTimeout(() => {
                    window.location.href = '#{redirect_path}';
                  }, 100);
                </script>
              HTML
            else
              redirect_to redirect_path, notice: "Welcome! Account created successfully."
            end
          end
          format.turbo_stream do
            # For Turbo Stream requests, handle redirect via JavaScript
            render turbo_stream: turbo_stream.append("body", 
              "<script>window.location.href = '#{redirect_path}';</script>")
          end
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