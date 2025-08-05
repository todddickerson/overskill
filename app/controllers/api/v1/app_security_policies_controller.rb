# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppSecurityPoliciesController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_security_policy, through: :app, through_association: :app_security_policies

    # GET /api/v1/apps/:app_id/app_security_policies
    def index
    end

    # GET /api/v1/app_security_policies/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_security_policies
    def create
      if @app_security_policy.save
        render :show, status: :created, location: [:api, :v1, @app_security_policy]
      else
        render json: @app_security_policy.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_security_policies/:id
    def update
      if @app_security_policy.update(app_security_policy_params)
        render :show
      else
        render json: @app_security_policy.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_security_policies/:id
    def destroy
      @app_security_policy.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_security_policy_params
        strong_params = params.require(:app_security_policy).permit(
          *permitted_fields,
          :policy_name,
          :policy_type,
          :enabled,
          :configuration,
          :description,
          :last_violation,
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
  class Api::V1::AppSecurityPoliciesController
  end
end
