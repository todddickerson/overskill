# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app, through: :team, through_association: :apps

    # GET /api/v1/teams/:team_id/apps
    def index
    end

    # GET /api/v1/apps/:id
    def show
    end

    # POST /api/v1/teams/:team_id/apps
    def create
      if @app.save
        render :show, status: :created, location: [:api, :v1, @app]
      else
        render json: @app.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/apps/:id
    def update
      if @app.update(app_params)
        render :show
      else
        render json: @app.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/apps/:id
    def destroy
      @app.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_params
        strong_params = params.require(:app).permit(
          *permitted_fields,
          :name,
          :subdomain,
          :description,
          :creator_id,
          :prompt,
          :app_type,
          :framework,
          :status,
          :visibility,
          :base_price,
          :stripe_product_id,
          :preview_url,
          :production_url,
          :github_repo,
          :featured,
          :featured_until,
          :launch_date,
          :ai_model,
          :show_overskill_badge,
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
  class Api::V1::AppsController
  end
end
