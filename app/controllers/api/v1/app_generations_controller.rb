# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::AppGenerationsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :app_generation, through: :app, through_association: :app_generations

    # GET /api/v1/apps/:app_id/app_generations
    def index
    end

    # GET /api/v1/app_generations/:id
    def show
    end

    # POST /api/v1/apps/:app_id/app_generations
    def create
      if @app_generation.save
        render :show, status: :created, location: [:api, :v1, @app_generation]
      else
        render json: @app_generation.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/app_generations/:id
    def update
      if @app_generation.update(app_generation_params)
        render :show
      else
        render json: @app_generation.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/app_generations/:id
    def destroy
      @app_generation.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def app_generation_params
        strong_params = params.require(:app_generation).permit(
          *permitted_fields,
          :status,
          :ai_model,
          :prompt,
          :enhanced_prompt,
          :started_at,
          :completed_at,
          :duration_seconds,
          :input_tokens,
          :output_tokens,
          :total_cost,
          :error_message,
          :retry_count,
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
  class Api::V1::AppGenerationsController
  end
end
