# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppVersionsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_version, through: :team, through_association: :app_versions

    # GET /api/v1/teams/:team_id/app_versions
    def index
    end

    # GET /api/v1/app_versions/:id
    def show
    end

    # POST /api/v1/teams/:team_id/app_versions
    def create
      if @app_version.save
        render :show, status: :created, location: [:api, :v1, @app_version]
      else
        render json: @app_version.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_versions/:id
    def update
      if @app_version.update(app_version_params)
        render :show
      else
        render json: @app_version.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_versions/:id
    def destroy
      @app_version.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_version_params
        strong_params = params.require(:app_version).permit(
          *permitted_fields,
          :app_id,
          :user_id,
          :commit_sha,
          :commit_message,
          :version_number,
          :changelog,
          :files_snapshot,
          :changed_files,
          :external_commit,
          :deployed,
          :published_at,
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
  class Api::V1::AppVersionsController
  end
end
