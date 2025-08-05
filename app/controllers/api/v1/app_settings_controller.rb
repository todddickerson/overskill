# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppSettingsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_setting, through: :app, through_association: :app_settings

    # GET /api/v1/apps/:app_id/app_settings
    def index
    end

    # GET /api/v1/app_settings/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_settings
    def create
      if @app_setting.save
        render :show, status: :created, location: [:api, :v1, @app_setting]
      else
        render json: @app_setting.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_settings/:id
    def update
      if @app_setting.update(app_setting_params)
        render :show
      else
        render json: @app_setting.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_settings/:id
    def destroy
      @app_setting.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_setting_params
        strong_params = params.require(:app_setting).permit(
          *permitted_fields,
          :key,
          :value,
          :setting_type,
          :description,
          :encrypted,
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
  class Api::V1::AppSettingsController
  end
end
