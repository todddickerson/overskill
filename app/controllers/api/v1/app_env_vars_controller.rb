# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppEnvVarsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_env_var, through: :app, through_association: :app_env_vars

    # GET /api/v1/apps/:app_id/app_env_vars
    def index
    end

    # GET /api/v1/app_env_vars/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_env_vars
    def create
      if @app_env_var.save
        render :show, status: :created, location: [:api, :v1, @app_env_var]
      else
        render json: @app_env_var.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_env_vars/:id
    def update
      if @app_env_var.update(app_env_var_params)
        render :show
      else
        render json: @app_env_var.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_env_vars/:id
    def destroy
      @app_env_var.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_env_var_params
        strong_params = params.require(:app_env_var).permit(
          *permitted_fields,
          :key,
          :value,
          :description,
          :is_secret,
          # 🚅 super scaffolding will insert new fields above this line.
          *permitted_arrays,
          # 🚅 super scaffolding will insert new arrays above this line.
        )

        process_params(strong_params)

        strong_params
      end
    end

    include StrongParameters
  end
else
  class Api::V1::AppEnvVarsController
  end
end
