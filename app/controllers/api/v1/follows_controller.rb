# Api::V1::ApplicationController is in the starter repository and isn't
# needed for this package's unit tests, but our CI tests will try to load this
# class because eager loading is set to `true` when CI=true.
# We wrap this class in an `if` statement to circumvent this issue.
if defined?(Api::V1::ApplicationController)
  class Api::V1::FollowsController < Api::V1::ApplicationController
    account_load_and_authorize_resource :follow, through: :team, through_association: :follows

    # GET /api/v1/teams/:team_id/follows
    def index
    end

    # GET /api/v1/follows/:id
    def show
    end

    # POST /api/v1/teams/:team_id/follows
    def create
      if @follow.save
        render :show, status: :created, location: [:api, :v1, @follow]
      else
        render json: @follow.errors, status: :unprocessable_entity
      end
    end

    # PATCH/PUT /api/v1/follows/:id
    def update
      if @follow.update(follow_params)
        render :show
      else
        render json: @follow.errors, status: :unprocessable_entity
      end
    end

    # DELETE /api/v1/follows/:id
    def destroy
      @follow.destroy
    end

    private

    module StrongParameters
      # Only allow a list of trusted parameters through.
      def follow_params
        strong_params = params.require(:follow).permit(
          *permitted_fields,
          :follower_id,
          :followed_id,
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
  class Api::V1::FollowsController
  end
end
